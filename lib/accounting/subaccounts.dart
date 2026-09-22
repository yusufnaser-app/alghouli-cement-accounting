// ============================================================================
// حسابات الأطراف الفرعية (Sub-Accounts)
// ============================================================================
// كل طرف (مصنع، تاجر، عميل، مورد، سائق، مالك قاطرة) يجب أن يملك حسابًا فرعيًا
// مستقلًا في دليل الحسابات حتى يتسنى إخراج كشف حساب مستقل له. هذه الخدمة
// تضمن وجود ذلك الحساب — تنشئه تلقائيًا إن لم يكن موجودًا بعد (على سبيل
// المثال لأطراف أُدخلت من إصدار سابق من التطبيق قبل تفعيل هذه الآلية).
// ============================================================================

import 'package:sqflite/sqflite.dart';
import '../core/db.dart';

class SubAccountService {
  static const _parentByPartyType = {
    'factory': '2000', // المصانع والموردون
    'supplier': '2000',
    'customer': '1300', // العملاء
    'trader': '1310', // التجار
  };

  static Future<int> _parentId(DatabaseExecutor tx, String code) async {
    final r = await tx.query('accounts', where: 'code=?', whereArgs: [code]);
    if (r.isEmpty) throw Exception('حساب النظام الأب غير موجود: $code');
    return r.first['id'] as int;
  }

  static Future<int> _createChildAccount(
    DatabaseExecutor tx, {
    required String namePrefix,
    required String name,
    required String parentCode,
    required String type,
  }) async {
    final parentId = await _parentId(tx, parentCode);
    // كود فرعي فريد: كود الأب + رقم تسلسلي
    final parent = (await tx.query('accounts', where: 'id=?', whereArgs: [parentId])).first;
    final siblings = await tx.query('accounts', where: 'parent_id=?', whereArgs: [parentId]);
    final seq = siblings.length + 1;
    final code = '${parent['code']}-${seq.toString().padLeft(3, '0')}';
    final now = DateTime.now().toIso8601String();
    return tx.insert('accounts', {
      'code': code,
      'name': '$namePrefix: $name',
      'type': type,
      'parent_id': parentId,
      'is_system': 0,
      'created': now,
    });
  }

  /// يعيد account_id لطرف من جدول parties، وينشئه إن لم يوجد.
  static Future<int> ensureForParty(DatabaseExecutor tx, int partyId) async {
    final rows = await tx.query('parties', where: 'id=?', whereArgs: [partyId]);
    if (rows.isEmpty) throw Exception('الطرف غير موجود: $partyId');
    final p = rows.first;
    if (p['account_id'] != null) return p['account_id'] as int;
    final type = p['type'] as String;
    final parentCode = _parentByPartyType[type] ?? '1300';
    final acctType = (type == 'factory' || type == 'supplier') ? 'liability' : 'asset';
    final label = switch (type) {
      'factory' => 'مصنع',
      'supplier' => 'مورد',
      'customer' => 'عميل',
      'trader' => 'تاجر',
      _ => 'طرف',
    };
    final accId = await _createChildAccount(tx,
        namePrefix: label, name: p['name'] as String, parentCode: parentCode, type: acctType);
    await tx.update('parties', {'account_id': accId}, where: 'id=?', whereArgs: [partyId]);
    return accId;
  }

  /// يعيد account_id لسائق، وينشئه إن لم يوجد. مستحقات السائق دائمًا التزام
  /// (liability) على المؤسسة تجاهه بغض النظر عن نوعه (موظف/تابع لتاجر/مستقل).
  static Future<int> ensureForDriver(DatabaseExecutor tx, int driverId) async {
    final rows = await tx.query('drivers', where: 'id=?', whereArgs: [driverId]);
    if (rows.isEmpty) throw Exception('السائق غير موجود: $driverId');
    final d = rows.first;
    if (d['account_id'] != null) return d['account_id'] as int;
    final accId = await _createChildAccount(tx,
        namePrefix: 'سائق', name: d['name'] as String, parentCode: '2100', type: 'liability');
    await tx.update('drivers', {'account_id': accId}, where: 'id=?', whereArgs: [driverId]);
    return accId;
  }

  /// يعيد account_id لقاطرة (يُستخدم عادة عند استحقاق النقل لمالك القاطرة).
  static Future<int> ensureForTruck(DatabaseExecutor tx, int truckId) async {
    final rows = await tx.query('trucks', where: 'id=?', whereArgs: [truckId]);
    if (rows.isEmpty) throw Exception('القاطرة غير موجودة: $truckId');
    final t = rows.first;
    if (t['account_id'] != null) return t['account_id'] as int;
    final accId = await _createChildAccount(tx,
        namePrefix: 'قاطرة', name: t['plate'] as String, parentCode: '2110', type: 'liability');
    await tx.update('trucks', {'account_id': accId}, where: 'id=?', whereArgs: [truckId]);
    return accId;
  }
}
