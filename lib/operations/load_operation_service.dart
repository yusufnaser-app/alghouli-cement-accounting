// ============================================================================
// عملية "تسجيل وترحيل الحمولة" — العملية المحورية في النظام
// ============================================================================
// عند نجاح الترحيل تُنشأ تلقائيًا من نفس رقم العملية:
//   - حركة المصنع (شراء بضاعة / التزام تجاه المصنع)
//   - حركة التاجر (إن وُجد وسيط تجاري)
//   - حركة السائق / حركة القاطرة (حسب جهة استحقاق النقل)
//   - حركة المخزون (وارد بكلفة الشراء + إعادة حساب متوسط التكلفة المرجح)
//   - حركة النقل، حركة العمولة، حركة الحافز
//   - حركة النقد/البنك/الصراف (إن تمت التسوية الفورية)
//   - القيد المحاسبي الموحّد المتوازن
//   - سجل تدقيق كامل
//
// الضمانات:
//   - Idempotency: فحص حالة السجل داخل نفس المعاملة قبل الترحيل، ومنع إعادة
//     الترحيل لعملية مرحّلة أصلًا (unique operation_no + قفل الحالة).
//   - لا حذف لعملية مرحّلة — فقط عكس محاسبي كامل عبر [cancelPostedLoad].
//   - الصلاحيات تُفرض قبل أي كتابة عبر [Permissions.require].
// ============================================================================

import 'package:sqflite/sqflite.dart';
import '../core/db.dart';
import '../core/permissions.dart';
import '../core/audit.dart';
import '../accounting/accounting_engine.dart';
import '../accounting/subaccounts.dart';
import '../messaging/message_service.dart';

enum TransportBeneficiary { driver, truckOwner, trader, driverAndOwner, other }

extension on TransportBeneficiary {
  String get dbValue => switch (this) {
        TransportBeneficiary.driver => 'driver',
        TransportBeneficiary.truckOwner => 'truck_owner',
        TransportBeneficiary.trader => 'trader',
        TransportBeneficiary.driverAndOwner => 'driver_and_owner',
        TransportBeneficiary.other => 'other',
      };
}

class LoadInput {
  final DateTime dateTime;
  final int factoryId;
  final int? traderId;
  final int driverId;
  final int truckId;
  final int? routeId;
  final int productId;
  final double bags;
  final double weightTons;
  final double bulkTotal;
  final double purchasePriceBag;
  final double transportFareBag;
  final double commissionBag;
  final double incentiveBag;
  final TransportBeneficiary transportBeneficiary;
  final int? transportBeneficiaryOtherPartyId; // إن كانت الجهة "أخرى" مرتبطة بطرف موجود
  final String? transportBeneficiaryOtherName; // اسم حر إن لم يكن طرفًا مسجّلًا
  final int? paymentAccountId; // صراف/بنك/نقد — null يعني: يُقيّد كمستحق آجل
  final String? notes;

  const LoadInput({
    required this.dateTime,
    required this.factoryId,
    this.traderId,
    required this.driverId,
    required this.truckId,
    this.routeId,
    required this.productId,
    required this.bags,
    required this.weightTons,
    this.bulkTotal = 0,
    required this.purchasePriceBag,
    this.transportFareBag = 0,
    this.commissionBag = 0,
    this.incentiveBag = 0,
    this.transportBeneficiary = TransportBeneficiary.driver,
    this.transportBeneficiaryOtherPartyId,
    this.transportBeneficiaryOtherName,
    this.paymentAccountId,
    this.notes,
  });

  double get purchaseTotal => bags * purchasePriceBag;
  double get transportTotal => bags * transportFareBag;
  double get commissionTotal => bags * commissionBag;
  double get incentiveTotal => bags * incentiveBag;
  // صافي العمولة = إجمالي العمولة + الحافز (المبلغ الصافي المستحق لجهة العمولة)
  double get netCommission => commissionTotal + incentiveTotal;
}

class LoadOperationService {
  /// المرحلة 1: تسجيل الحمولة كمسودة (draft) — لا تُنشأ أي حركات محاسبية بعد.
  static Future<int> registerDraft(LoadInput input, {required int createdBy}) async {
    await Permissions.require('loads', Action.add);
    final db = AppDb.instance.db;
    final now = DateTime.now().toIso8601String();
    final opNo = await _nextOperationNo();
    final id = await db.insert('loads', {
      'operation_no': opNo,
      'datetime': input.dateTime.toIso8601String(),
      'factory_id': input.factoryId,
      'trader_id': input.traderId,
      'driver_id': input.driverId,
      'truck_id': input.truckId,
      'route_id': input.routeId,
      'product_id': input.productId,
      'bags': input.bags,
      'weight_tons': input.weightTons,
      'bulk_total': input.bulkTotal,
      'purchase_price_bag': input.purchasePriceBag,
      'purchase_total': input.purchaseTotal,
      'transport_fare_bag': input.transportFareBag,
      'transport_total': input.transportTotal,
      'commission_bag': input.commissionBag,
      'commission_total': input.commissionTotal,
      'incentive_bag': input.incentiveBag,
      'incentive_total': input.incentiveTotal,
      'net_commission': input.netCommission,
      'transport_beneficiary_type': input.transportBeneficiary.dbValue,
      'transport_beneficiary_id': input.transportBeneficiaryOtherPartyId,
      'transport_beneficiary_other_name': input.transportBeneficiaryOtherName,
      'payment_account_id': input.paymentAccountId,
      'status': 'draft',
      'notes': input.notes,
      'created_by': createdBy,
      'created': now,
    });
    await Audit.log(action: 'create_draft', entity: 'loads', entityId: id, after: {'operation_no': opNo});
    return id;
  }

  static Future<String> _nextOperationNo() async {
    final settings = await AppDb.instance.q("SELECT value FROM settings WHERE key='doc_prefix_load'");
    final prefix = settings.isNotEmpty ? settings.first['value'] as String : 'LD';
    final countRow = await AppDb.instance.q('SELECT COUNT(*) c FROM loads');
    final seq = (countRow.first['c'] as int) + 1;
    final year = DateTime.now().year;
    return '$prefix-$year-${seq.toString().padLeft(5, '0')}';
  }

  /// المرحلة 2: "ترحيل الحمولة" — العملية الجوهرية. تُنفَّذ داخل معاملة واحدة
  /// ذرّية (atomic transaction): إما تنجح كل الحركات معًا أو تفشل كلها معًا.
  static Future<void> postLoad(int loadId, {required int postedBy}) async {
    await Permissions.require('loads', Action.post);
    final db = AppDb.instance.db;

    await db.transaction((tx) async {
      final rows = await tx.query('loads', where: 'id=?', whereArgs: [loadId]);
      if (rows.isEmpty) throw Exception('عملية الحمولة غير موجودة: $loadId');
      final load = rows.first;

      // --- منع الترحيل المكرر (Idempotency) ---
      final status = load['status'] as String;
      if (status == 'posted') {
        throw AlreadyPostedException('loads', loadId);
      }
      if (status == 'cancelled' || status == 'reversed') {
        throw NotPostedException('لا يمكن ترحيل عملية ملغاة أو معكوسة مسبقًا');
      }

      final bags = (load['bags'] as num).toDouble();
      final purchaseTotal = (load['purchase_total'] as num).toDouble();
      final transportTotal = (load['transport_total'] as num).toDouble();
      final commissionTotal = (load['commission_total'] as num).toDouble();
      final incentiveTotal = (load['incentive_total'] as num).toDouble();
      final productId = load['product_id'] as int;
      final factoryId = load['factory_id'] as int;
      final traderId = load['trader_id'] as int?;
      final driverId = load['driver_id'] as int;
      final truckId = load['truck_id'] as int;
      final paymentAccountId = load['payment_account_id'] as int?;
      final beneficiaryType = load['transport_beneficiary_type'] as String;
      final opNo = load['operation_no'] as String;

      // --- حسابات فرعية للأطراف (تُنشأ تلقائيًا عند أول استخدام) ---
      final factoryAccId = await SubAccountService.ensureForParty(tx, factoryId);
      final driverAccId = await SubAccountService.ensureForDriver(tx, driverId);
      final truckAccId = await SubAccountService.ensureForTruck(tx, truckId);
      final traderAccId = traderId != null ? await SubAccountService.ensureForParty(tx, traderId) : null;

      // --- جهة استحقاق النقل ---
      late final int transportPayableAccId;
      switch (beneficiaryType) {
        case 'driver':
          transportPayableAccId = driverAccId;
          break;
        case 'truck_owner':
          transportPayableAccId = truckAccId;
          break;
        case 'trader':
          if (traderAccId == null) {
            throw Exception('جهة استحقاق النقل "تاجر" لكن لم يتم تحديد تاجر للعملية');
          }
          transportPayableAccId = traderAccId;
          break;
        case 'driver_and_owner':
          // تُقسّم مناصفة بين السائق ومالك القاطرة (راجع الأسطر أدناه)
          transportPayableAccId = driverAccId; // للحساب الأساسي؛ يُضاف سطر إضافي أدناه
          break;
        default:
          transportPayableAccId = driverAccId; // 'other' بدون طرف مسجل: يُقيّد على السائق افتراضيًا
      }

      // --- المخزون: متوسط التكلفة المرجح ---
      final productRow = (await tx.query('products', where: 'id=?', whereArgs: [productId])).first;
      final curBags = (productRow['stock_bags'] as num).toDouble();
      final curAvgCost = (productRow['avg_unit_cost'] as num).toDouble();
      final newBags = curBags + bags;
      final unitCostThisLoad = bags > 0 ? purchaseTotal / bags : 0.0;
      final newAvgCost = newBags > 0
          ? ((curBags * curAvgCost) + (bags * unitCostThisLoad)) / newBags
          : 0.0;
      final bagsPerTon = (productRow['bags_per_ton'] as num).toDouble();
      await tx.update(
        'products',
        {
          'stock_bags': newBags,
          'stock_tons': newBags / (bagsPerTon == 0 ? 20 : bagsPerTon),
          'avg_unit_cost': newAvgCost,
        },
        where: 'id=?',
        whereArgs: [productId],
      );
      final now = DateTime.now().toIso8601String();
      await tx.insert('stock_moves', {
        'date': now,
        'product_id': productId,
        'bags': bags,
        'tons': (load['weight_tons'] as num).toDouble(),
        'unit_cost': unitCostThisLoad,
        'direction': 'in',
        'move_type': 'load',
        'source_type': 'loads',
        'source_id': loadId,
        'note': 'وارد من حمولة $opNo',
        'created': now,
      });

      // --- بناء القيد المحاسبي الموحّد المتوازن ---
      final lines = <JournalLineInput>[
        // 1) شراء البضاعة من المصنع: مدين مخزون / دائن حساب المصنع
        JournalLineInput(accountCode: '1400', debit: purchaseTotal, description: 'شراء حمولة $opNo'),
        JournalLineInput(accountId: factoryAccId, credit: purchaseTotal, description: 'استحقاق مصنع - حمولة $opNo'),
      ];

      // 2) النقل: مدين مصروف نقل / دائن جهة الاستحقاق (أو النقد إن دُفع فورًا)
      if (transportTotal > 0) {
        lines.add(JournalLineInput(accountCode: '5100', debit: transportTotal, description: 'أجرة نقل - $opNo'));
        if (beneficiaryType == 'driver_and_owner') {
          final half = transportTotal / 2;
          lines.add(JournalLineInput(accountId: driverAccId, credit: half, description: 'نصف أجرة نقل - $opNo'));
          lines.add(JournalLineInput(accountId: truckAccId, credit: half, description: 'نصف أجرة نقل - $opNo'));
        } else {
          lines.add(JournalLineInput(accountId: transportPayableAccId, credit: transportTotal, description: 'أجرة نقل - $opNo'));
        }
      }

      // 3) العمولة والحافز: مدين مصروفات / دائن جهة العمولة (التاجر إن وُجد، وإلا السائق)
      final commissionBeneficiaryAccId = traderAccId ?? driverAccId;
      if (commissionTotal > 0) {
        lines.add(JournalLineInput(accountCode: '5200', debit: commissionTotal, description: 'عمولة - $opNo'));
        lines.add(JournalLineInput(accountId: commissionBeneficiaryAccId, credit: commissionTotal, description: 'استحقاق عمولة - $opNo'));
      }
      if (incentiveTotal > 0) {
        lines.add(JournalLineInput(accountCode: '5210', debit: incentiveTotal, description: 'حافز - $opNo'));
        lines.add(JournalLineInput(accountId: commissionBeneficiaryAccId, credit: incentiveTotal, description: 'استحقاق حافز - $opNo'));
      }

      // 4) التسوية الفورية (اختياري): إن حُدد حساب صراف/بنك/نقد، تُسوّى
      //    مستحقات المصنع فورًا بدل بقائها كالتزام آجل.
      if (paymentAccountId != null) {
        final moneyRow = (await tx.query('money_accounts', where: 'id=?', whereArgs: [paymentAccountId])).first;
        final moneyAccId = moneyRow['account_id'] as int;
        lines.add(JournalLineInput(accountId: factoryAccId, debit: purchaseTotal, description: 'تسوية نقدية فورية - $opNo'));
        lines.add(JournalLineInput(accountId: moneyAccId, credit: purchaseTotal, description: 'دفعة نقدية لمصنع - $opNo'));
      }

      final journalId = await AccountingEngine.postJournal(
        tx,
        description: 'ترحيل حمولة رقم $opNo',
        sourceType: 'loads',
        sourceId: loadId,
        lines: lines,
        createdBy: postedBy,
      );

      await tx.update(
        'loads',
        {
          'status': 'posted',
          'journal_id': journalId,
          'posted_by': postedBy,
          'posted_at': now,
        },
        where: 'id=?',
        whereArgs: [loadId],
      );
    });

    await Audit.log(action: 'post', entity: 'loads', entityId: loadId);

    // بعد نجاح الترحيل فعليًا (خارج المعاملة): تجهيز إشعار السائق.
    await MessageService.queueLoadNotification(loadId);
  }

  /// عكس محاسبي كامل لعملية مرحّلة — لا حذف إطلاقًا. يُنشئ قيدًا عكسيًا
  /// مرتبطًا بالقيد الأصلي، ويعيد حالة الحمولة إلى 'reversed'، مع تصحيح
  /// المخزون بعملية إخراج مقابلة.
  static Future<void> reversePostedLoad(int loadId, {required int userId, required String reason}) async {
    await Permissions.require('loads', Action.reverse);
    final db = AppDb.instance.db;
    await db.transaction((tx) async {
      final rows = await tx.query('loads', where: 'id=?', whereArgs: [loadId]);
      if (rows.isEmpty) throw Exception('العملية غير موجودة');
      final load = rows.first;
      if ((load['status'] as String) != 'posted') {
        throw NotPostedException('لا يمكن عكس عملية غير مرحّلة أصلًا');
      }
      final journalId = load['journal_id'] as int;
      final revJournalId = await AccountingEngine.reverseJournal(
        tx,
        originalJournalId: journalId,
        reason: reason,
        createdBy: userId,
      );
      // عكس أثر المخزون
      final productId = load['product_id'] as int;
      final bags = (load['bags'] as num).toDouble();
      final bagsPerTon = (await tx.query('products', where: 'id=?', whereArgs: [productId])).first['bags_per_ton'] as num;
      await tx.rawUpdate(
        'UPDATE products SET stock_bags = stock_bags - ?, stock_tons = stock_tons - ? WHERE id=?',
        [bags, bags / (bagsPerTon == 0 ? 20 : bagsPerTon), productId],
      );
      final now = DateTime.now().toIso8601String();
      await tx.insert('stock_moves', {
        'date': now,
        'product_id': productId,
        'bags': bags,
        'tons': (load['weight_tons'] as num).toDouble(),
        'unit_cost': 0,
        'direction': 'out',
        'move_type': 'load_reversal',
        'source_type': 'loads',
        'source_id': loadId,
        'note': 'عكس حمولة ${load['operation_no']}: $reason',
        'created': now,
      });
      await tx.update(
        'loads',
        {'status': 'reversed', 'reversal_journal_id': revJournalId},
        where: 'id=?',
        whereArgs: [loadId],
      );
    });
    await Audit.log(action: 'reverse', entity: 'loads', entityId: loadId, after: {'reason': reason});
  }

  /// إلغاء مسودة قبل الترحيل فقط — لا يمس أي حسابات لأنه لم يُرحّل بعد.
  static Future<void> cancelDraft(int loadId) async {
    await Permissions.require('loads', Action.cancel);
    final rows = await AppDb.instance.q('SELECT status FROM loads WHERE id=?', [loadId]);
    if (rows.isEmpty) throw Exception('العملية غير موجودة');
    if (rows.first['status'] != 'draft') {
      throw Exception('لا يمكن إلغاء عملية بهذه الطريقة إلا وهي مسودة — استخدم العكس المحاسبي للعمليات المرحّلة');
    }
    await AppDb.instance.upd('loads', {'status': 'cancelled'}, 'id=?', [loadId]);
    await Audit.log(action: 'cancel_draft', entity: 'loads', entityId: loadId);
  }
}
