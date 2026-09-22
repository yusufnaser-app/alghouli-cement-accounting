import 'package:flutter_test/flutter_test.dart';
import 'package:cement_accounting_complete/core/db.dart';
import 'package:cement_accounting_complete/accounting/accounting_engine.dart';
import 'test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await freshTestDb();
  });

  test('القيد غير المتوازن يُرفض برمي UnbalancedJournalException', () async {
    final db = AppDb.instance.db;
    await expectLater(
      db.transaction((tx) => AccountingEngine.postJournal(
            tx,
            description: 'اختبار قيد غير متوازن',
            sourceType: 'test',
            lines: const [
              JournalLineInput(accountCode: '1000', debit: 100),
              JournalLineInput(accountCode: '4000', credit: 90), // فرق متعمد
            ],
          )),
      throwsA(isA<UnbalancedJournalException>()),
    );
  });

  test('القيد المتوازن يُنشأ بنجاح وتظهر أسطره في ميزان المراجعة', () async {
    final db = AppDb.instance.db;
    await db.transaction((tx) => AccountingEngine.postJournal(
          tx,
          description: 'اختبار قيد متوازن',
          sourceType: 'test',
          lines: const [
            JournalLineInput(accountCode: '1000', debit: 500),
            JournalLineInput(accountCode: '4000', credit: 500),
          ],
        ));
    final tb = await AccountingEngine.trialBalance();
    final cash = tb.firstWhere((r) => r['code'] == '1000');
    expect((cash['debit'] as num).toDouble(), 500);
    final unbalanced = await AccountingEngine.findUnbalancedJournals();
    expect(unbalanced, isEmpty, reason: 'لا يجب وجود أي قيد غير متوازن في القاعدة');
  });

  test('العكس المحاسبي ينشئ قيدًا جديدًا بعلامات معكوسة ولا يحذف القيد الأصلي', () async {
    final db = AppDb.instance.db;
    late int journalId;
    await db.transaction((tx) async {
      journalId = await AccountingEngine.postJournal(
        tx,
        description: 'قيد سيُعكس',
        sourceType: 'test',
        lines: const [
          JournalLineInput(accountCode: '1000', debit: 200),
          JournalLineInput(accountCode: '4000', credit: 200),
        ],
      );
    });

    late int reversalId;
    await db.transaction((tx) async {
      reversalId = await AccountingEngine.reverseJournal(tx, originalJournalId: journalId, reason: 'اختبار العكس');
    });

    // القيد الأصلي ما زال موجودًا (لم يُحذف)
    final original = await AppDb.instance.q('SELECT * FROM journals WHERE id=?', [journalId]);
    expect(original, isNotEmpty);
    expect(original.first['reversed_by'], reversalId);

    // القيد العكسي متوازن أيضًا وبعلامات مبدّلة
    final reversalLines = await AppDb.instance.q('SELECT * FROM journal_lines WHERE journal_id=?', [reversalId]);
    expect(reversalLines.length, 2);
    final totalDebit = reversalLines.fold<double>(0, (s, l) => s + (l['debit'] as num).toDouble());
    final totalCredit = reversalLines.fold<double>(0, (s, l) => s + (l['credit'] as num).toDouble());
    expect(totalDebit, totalCredit);

    // صافي الأثر على حساب النقدية = صفر بعد الأصل + العكس
    final tb = await AccountingEngine.trialBalance();
    final cash = tb.firstWhere((r) => r['code'] == '1000');
    expect((cash['balance'] as num).toDouble(), 0);
  });
}
