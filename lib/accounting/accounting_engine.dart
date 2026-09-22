// ============================================================================
// محرك المحاسبة
// ============================================================================
// القواعد الصلبة المطبّقة هنا:
//  1) أي قيد يجب أن يكون متوازنًا (مجموع المدين = مجموع الدائن) وإلا يُرفض.
//  2) لا يمكن حذف عملية مرحّلة أبدًا — فقط: إلغاء (قبل الترحيل) أو
//     عكس محاسبي (بعد الترحيل) عبر قيد عكسي مرتبط بالقيد الأصلي.
//  3) منع الترحيل المكرر لنفس العملية (Idempotency) عبر التحقق من الحالة
//     الحالية داخل معاملة واحدة (transaction) قبل أي كتابة.
// ============================================================================

import 'package:sqflite/sqflite.dart';
import '../core/db.dart';
import '../core/audit.dart';

class JournalLineInput {
  /// إما كود حساب من دليل الحسابات الثابت (مثل '1400') أو رقم حساب فرعي
  /// (accountId) خاص بطرف معيّن (مصنع/تاجر/سائق/قاطرة) تم إنشاؤه عبر
  /// [SubAccountService]. يجب توفير أحدهما فقط.
  final String? accountCode;
  final int? accountId;
  final double debit;
  final double credit;
  final String? description;
  const JournalLineInput({
    this.accountCode,
    this.accountId,
    this.debit = 0,
    this.credit = 0,
    this.description,
  }) : assert(accountCode != null || accountId != null,
            'يجب تحديد accountCode أو accountId');
}

class UnbalancedJournalException implements Exception {
  final double debitTotal, creditTotal;
  UnbalancedJournalException(this.debitTotal, this.creditTotal);
  @override
  String toString() =>
      'القيد غير متوازن: مدين=$debitTotal دائن=$creditTotal — الفرق=${(debitTotal - creditTotal).abs()}';
}

class AlreadyPostedException implements Exception {
  final String entity;
  final Object id;
  AlreadyPostedException(this.entity, this.id);
  @override
  String toString() => 'العملية "$entity#$id" مرحّلة مسبقًا — لا يمكن ترحيلها مرة أخرى';
}

class NotPostedException implements Exception {
  final String message;
  NotPostedException(this.message);
  @override
  String toString() => message;
}

class AccountingEngine {
  static const double _epsilon = 0.005; // هامش تقريب للعملة

  static Future<int> _accountId(DatabaseExecutor tx, String code) async {
    final r = await tx.query('accounts', where: 'code=?', whereArgs: [code]);
    if (r.isEmpty) throw Exception('الحساب غير موجود في دليل الحسابات: $code');
    return r.first['id'] as int;
  }

  /// ينشئ قيدًا محاسبيًا متوازنًا داخل معاملة قائمة بالفعل. لا يتحقق من
  /// الترحيل المكرر بنفسه — هذا مسؤولية الخدمة المستدعية (مثل تسجيل الحمولة)
  /// التي يجب أن تتحقق من حالة السجل ضمن نفس المعاملة قبل النداء هنا.
  static Future<int> postJournal(
    DatabaseExecutor tx, {
    required String description,
    required String sourceType,
    int? sourceId,
    required List<JournalLineInput> lines,
    int? createdBy,
    int? reversedOf,
  }) async {
    final debitTotal = lines.fold<double>(0, (s, l) => s + l.debit);
    final creditTotal = lines.fold<double>(0, (s, l) => s + l.credit);
    if ((debitTotal - creditTotal).abs() > _epsilon) {
      throw UnbalancedJournalException(debitTotal, creditTotal);
    }
    final now = DateTime.now().toIso8601String();
    final no = 'JE-${DateTime.now().microsecondsSinceEpoch}';
    final journalId = await tx.insert('journals', {
      'no': no,
      'date': now,
      'source_type': sourceType,
      'source_id': sourceId,
      'description': description,
      'reversed_of': reversedOf,
      'posted': 1,
      'created_by': createdBy,
      'created': now,
    });
    for (final l in lines) {
      final accId = l.accountId ?? await _accountId(tx, l.accountCode!);
      await tx.insert('journal_lines', {
        'journal_id': journalId,
        'account_id': accId,
        'debit': l.debit,
        'credit': l.credit,
        'description': l.description ?? description,
      });
    }
    return journalId;
  }

  /// ينشئ قيدًا عكسيًا كاملًا لقيد سابق (يبدّل المدين/الدائن لكل سطر) بدلًا
  /// من حذف أي شيء. يُستخدم عند عكس عملية مرحّلة (فاتورة، حمولة، سند...).
  static Future<int> reverseJournal(
    DatabaseExecutor tx, {
    required int originalJournalId,
    required String reason,
    int? createdBy,
  }) async {
    final origLines = await tx.query('journal_lines', where: 'journal_id=?', whereArgs: [originalJournalId]);
    final orig = (await tx.query('journals', where: 'id=?', whereArgs: [originalJournalId])).first;
    final now = DateTime.now().toIso8601String();
    final no = 'JE-REV-${DateTime.now().microsecondsSinceEpoch}';
    final journalId = await tx.insert('journals', {
      'no': no,
      'date': now,
      'source_type': orig['source_type'],
      'source_id': orig['source_id'],
      'description': 'عكس محاسبي: $reason (للقيد ${orig['no']})',
      'reversed_of': originalJournalId,
      'posted': 1,
      'created_by': createdBy,
      'created': now,
    });
    for (final l in origLines) {
      await tx.insert('journal_lines', {
        'journal_id': journalId,
        'account_id': l['account_id'],
        'debit': l['credit'], // انعكاس كامل
        'credit': l['debit'],
        'description': 'عكس: ${l['description'] ?? ''}',
      });
    }
    await tx.update('journals', {'reversed_by': journalId}, where: 'id=?', whereArgs: [originalJournalId]);
    return journalId;
  }

  /// ميزان المراجعة: رصيد كل حساب = مدين - دائن (للأصول والمصروفات) أو
  /// العكس منطقيًا حسب نوع الحساب — هنا نعرض الإجماليات الخام ويُترك العرض
  /// للطبقة الأعلى (تقارير) لتفسيرها حسب النوع.
  static Future<List<Map<String, Object?>>> trialBalance() async {
    return AppDb.instance.q('''
      SELECT a.id, a.code, a.name, a.type,
             COALESCE(SUM(l.debit),0) AS debit,
             COALESCE(SUM(l.credit),0) AS credit,
             COALESCE(SUM(l.debit),0) - COALESCE(SUM(l.credit),0) AS balance
      FROM accounts a
      LEFT JOIN journal_lines l ON l.account_id = a.id
      WHERE a.active = 1
      GROUP BY a.id
      ORDER BY a.code
    ''');
  }

  /// كشف حساب لحساب معيّن (حركات مدينة/دائنة مرتبة بالتاريخ) مع رصيد متحرك.
  static Future<List<Map<String, Object?>>> statement(int accountId,
      {String? fromDate, String? toDate}) async {
    final where = StringBuffer('l.account_id = ?');
    final args = <Object?>[accountId];
    if (fromDate != null) {
      where.write(' AND j.date >= ?');
      args.add(fromDate);
    }
    if (toDate != null) {
      where.write(' AND j.date <= ?');
      args.add(toDate);
    }
    final rows = await AppDb.instance.q('''
      SELECT j.no, j.date, j.description, j.source_type, j.source_id, l.debit, l.credit
      FROM journal_lines l
      JOIN journals j ON j.id = l.journal_id
      WHERE $where
      ORDER BY j.date ASC, j.id ASC
    ''', args);
    double running = 0;
    final out = <Map<String, Object?>>[];
    for (final r in rows) {
      running += (r['debit'] as num).toDouble() - (r['credit'] as num).toDouble();
      out.add({...r, 'running_balance': running});
    }
    return out;
  }

  /// التحقق العام من توازن كل القيود في قاعدة البيانات — يُستخدم كاختبار سلامة
  /// دوري ويمكن استدعاؤه من شاشة "فحص النظام" في الإعدادات.
  static Future<List<Map<String, Object?>>> findUnbalancedJournals() async {
    return AppDb.instance.q('''
      SELECT j.id, j.no, j.date,
             COALESCE(SUM(l.debit),0) AS debit,
             COALESCE(SUM(l.credit),0) AS credit
      FROM journals j
      JOIN journal_lines l ON l.journal_id = j.id
      GROUP BY j.id
      HAVING ABS(COALESCE(SUM(l.debit),0) - COALESCE(SUM(l.credit),0)) > 0.005
    ''');
  }
}
