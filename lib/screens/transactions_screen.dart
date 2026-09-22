import 'package:flutter/material.dart';
import '../core/db.dart';
import '../core/permissions.dart';
import '../core/audit.dart';
import '../accounting/accounting_engine.dart';
import '../accounting/subaccounts.dart';
import 'dashboard_screen.dart' show money;

class OperationsHubScreen extends StatelessWidget {
  const OperationsHubScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return ListView(children: [
      ListTile(
          leading: const Icon(Icons.point_of_sale),
          title: const Text('المبيعات'),
          trailing: const Icon(Icons.chevron_left),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SalesScreen()))),
      ListTile(
          leading: const Icon(Icons.shopping_cart),
          title: const Text('المشتريات'),
          trailing: const Icon(Icons.chevron_left),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchasesScreen()))),
      ListTile(
          leading: const Icon(Icons.money_off),
          title: const Text('المصروفات'),
          trailing: const Icon(Icons.chevron_left),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExpensesScreen()))),
      ListTile(
          leading: const Icon(Icons.receipt_long),
          title: const Text('السندات (قبض/صرف)'),
          trailing: const Icon(Icons.chevron_left),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VouchersScreen()))),
    ]);
  }
}

// --------------------------------------------------------------------------
// المبيعات
// --------------------------------------------------------------------------
class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});
  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  Future<List<Map<String, Object?>>> _list() => AppDb.instance.q('SELECT * FROM sales ORDER BY id DESC');

  Future<void> _addAndPost() async {
    await Permissions.require('sales', Action.add);
    final customers = await AppDb.instance.q("SELECT id,name,account_id FROM parties WHERE type='customer'");
    final products = await AppDb.instance.q('SELECT id,name,stock_bags,avg_unit_cost FROM products');
    final moneyAccounts = await AppDb.instance.q('SELECT id,name,account_id FROM money_accounts');
    if (customers.isEmpty || products.isEmpty || moneyAccounts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('يجب إضافة عميل ومنتج وحساب مالي واحد على الأقل أولًا')));
      }
      return;
    }
    int customerId = customers.first['id'] as int;
    int productId = products.first['id'] as int;
    int moneyAccountId = moneyAccounts.first['id'] as int;
    final bags = TextEditingController();
    final price = TextEditingController();
    final paid = TextEditingController(text: '0');

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('فاتورة بيع'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<int>(
                value: customerId,
                decoration: const InputDecoration(labelText: 'العميل'),
                items: customers.map((c) => DropdownMenuItem(value: c['id'] as int, child: Text(c['name'].toString()))).toList(),
                onChanged: (v) => setD(() => customerId = v!),
              ),
              DropdownButtonFormField<int>(
                value: productId,
                decoration: const InputDecoration(labelText: 'المنتج'),
                items: products.map((p) => DropdownMenuItem(value: p['id'] as int, child: Text(p['name'].toString()))).toList(),
                onChanged: (v) => setD(() => productId = v!),
              ),
              TextField(controller: bags, decoration: const InputDecoration(labelText: 'عدد الأكياس'), keyboardType: TextInputType.number),
              TextField(controller: price, decoration: const InputDecoration(labelText: 'سعر الكيس'), keyboardType: TextInputType.number),
              TextField(controller: paid, decoration: const InputDecoration(labelText: 'المدفوع الآن'), keyboardType: TextInputType.number),
              DropdownButtonFormField<int>(
                value: moneyAccountId,
                decoration: const InputDecoration(labelText: 'حساب استلام الدفعة'),
                items: moneyAccounts.map((m) => DropdownMenuItem(value: m['id'] as int, child: Text(m['name'].toString()))).toList(),
                onChanged: (v) => setD(() => moneyAccountId = v!),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حفظ وترحيل')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final b = double.tryParse(bags.text) ?? 0;
    final p = double.tryParse(price.text) ?? 0;
    final pd = double.tryParse(paid.text) ?? 0;
    final total = b * p;
    final chosenProduct = products.firstWhere((x) => x['id'] == productId);
    final stockBags = (chosenProduct['stock_bags'] as num).toDouble();
    if (b > stockBags) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('الكمية المطلوبة ($b) أكبر من المخزون المتاح ($stockBags)')));
      }
      return;
    }
    final avgCost = (chosenProduct['avg_unit_cost'] as num).toDouble();
    final now = DateTime.now().toIso8601String();
    await AppDb.instance.db.transaction((tx) async {
      final prefixRow = await tx.query('settings', where: "key='doc_prefix_sale'");
      final prefix = prefixRow.isNotEmpty ? prefixRow.first['value'] as String : 'SI';
      final countRow = await tx.rawQuery('SELECT COUNT(*) c FROM sales');
      final no = '$prefix-${DateTime.now().year}-${((countRow.first['c'] as int) + 1).toString().padLeft(5, '0')}';
      final saleId = await tx.insert('sales', {
        'no': no, 'date': now, 'customer_id': customerId, 'product_id': productId,
        'bags': b, 'price': p, 'total': total, 'paid': pd, 'remaining': total - pd,
        'money_account_id': moneyAccountId, 'status': 'draft', 'created_by': Session.instance.user!.id, 'created': now,
      });
      final customerAccId = await SubAccountService.ensureForParty(tx, customerId);
      final moneyRow = (await tx.query('money_accounts', where: 'id=?', whereArgs: [moneyAccountId])).first;
      final moneyAcc = moneyRow['account_id'] as int;
      final cogs = b * avgCost;
      final lines = <JournalLineInput>[
        JournalLineInput(accountId: moneyAcc, debit: pd, description: 'تحصيل بيع $no'),
        JournalLineInput(accountId: customerAccId, debit: total - pd, description: 'ذمم بيع $no'),
        JournalLineInput(accountCode: '4000', credit: total, description: 'إيراد بيع $no'),
        if (cogs > 0) JournalLineInput(accountCode: '5000', debit: cogs, description: 'تكلفة بضاعة مباعة $no'),
        if (cogs > 0) JournalLineInput(accountCode: '1400', credit: cogs, description: 'إخراج مخزون $no'),
      ];
      final journalId = await AccountingEngine.postJournal(tx,
          description: 'ترحيل بيع $no', sourceType: 'sales', sourceId: saleId, lines: lines, createdBy: Session.instance.user!.id);
      await tx.update('sales', {'status': 'posted', 'journal_id': journalId}, where: 'id=?', whereArgs: [saleId]);
      await tx.rawUpdate('UPDATE products SET stock_bags=stock_bags-?, stock_tons=stock_tons-?/bags_per_ton WHERE id=?', [b, b, productId]);
      await tx.insert('stock_moves', {
        'date': now, 'product_id': productId, 'bags': b, 'tons': 0, 'unit_cost': avgCost,
        'direction': 'out', 'move_type': 'sale', 'source_type': 'sales', 'source_id': saleId, 'note': 'بيع $no', 'created': now,
      });
    });
    await Audit.log(action: 'post', entity: 'sales', after: {'total': total});
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المبيعات')),
      floatingActionButton: FloatingActionButton(onPressed: _addAndPost, child: const Icon(Icons.add)),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: _list(),
        builder: (c, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return ListView(children: [
            for (final r in snap.data!)
              ListTile(
                title: Text(r['no'].toString()),
                subtitle: Text('الحالة: ${r['status']}'),
                trailing: Text(money.format(r['total'] as num)),
              )
          ]);
        },
      ),
    );
  }
}

// --------------------------------------------------------------------------
// المشتريات (نمط مبسّط مشابه؛ شراء مباشر بدون دورة الحمولة الكاملة)
// --------------------------------------------------------------------------
class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key});
  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  Future<List<Map<String, Object?>>> _list() => AppDb.instance.q('SELECT * FROM purchases ORDER BY id DESC');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المشتريات')),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: _list(),
        builder: (c, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          if (snap.data!.isEmpty) {
            return const Center(
                child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                  'شراء الأسمنت من المصانع يتم عادة عبر "تسجيل وترحيل الحمولة" (تبويب العمليات) لأنه يربط تلقائيًا بالنقل والعمولة والمخزون. '
                  'استخدم هذه الشاشة فقط للمشتريات الأخرى غير المرتبطة بحمولة (مثل مستلزمات تشغيل).',
                  textAlign: TextAlign.center),
            ));
          }
          return ListView(children: [
            for (final r in snap.data!)
              ListTile(title: Text(r['no'].toString()), trailing: Text(money.format(r['total'] as num)))
          ]);
        },
      ),
    );
  }
}

// --------------------------------------------------------------------------
// المصروفات
// --------------------------------------------------------------------------
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});
  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  Future<List<Map<String, Object?>>> _list() => AppDb.instance.q('SELECT * FROM expenses ORDER BY id DESC');

  Future<void> _add() async {
    await Permissions.require('expenses', Action.add);
    final moneyAccounts = await AppDb.instance.q('SELECT id,name,account_id FROM money_accounts');
    if (moneyAccounts.isEmpty) return;
    final category = TextEditingController();
    final amount = TextEditingController();
    int moneyAccountId = moneyAccounts.first['id'] as int;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('مصروف جديد'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: category, decoration: const InputDecoration(labelText: 'التصنيف')),
            TextField(controller: amount, decoration: const InputDecoration(labelText: 'المبلغ'), keyboardType: TextInputType.number),
            DropdownButtonFormField<int>(
              value: moneyAccountId,
              decoration: const InputDecoration(labelText: 'الدفع من حساب'),
              items: moneyAccounts.map((m) => DropdownMenuItem(value: m['id'] as int, child: Text(m['name'].toString()))).toList(),
              onChanged: (v) => setD(() => moneyAccountId = v!),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حفظ وترحيل')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final amt = double.tryParse(amount.text) ?? 0;
    final now = DateTime.now().toIso8601String();
    await AppDb.instance.db.transaction((tx) async {
      final countRow = await tx.rawQuery('SELECT COUNT(*) c FROM expenses');
      final no = 'EX-${DateTime.now().year}-${((countRow.first['c'] as int) + 1).toString().padLeft(5, '0')}';
      final id = await tx.insert('expenses', {
        'no': no, 'date': now, 'category': category.text, 'amount': amt,
        'money_account_id': moneyAccountId, 'status': 'draft', 'created_by': Session.instance.user!.id, 'created': now,
      });
      final moneyRow = (await tx.query('money_accounts', where: 'id=?', whereArgs: [moneyAccountId])).first;
      final moneyAcc = moneyRow['account_id'] as int;
      final journalId = await AccountingEngine.postJournal(tx,
          description: 'مصروف $no - ${category.text}',
          sourceType: 'expenses',
          sourceId: id,
          lines: [
            JournalLineInput(accountCode: '5300', debit: amt, description: category.text),
            JournalLineInput(accountId: moneyAcc, credit: amt, description: 'دفع مصروف $no'),
          ],
          createdBy: Session.instance.user!.id);
      await tx.update('expenses', {'status': 'posted', 'journal_id': journalId, 'expense_account_id': moneyAcc}, where: 'id=?', whereArgs: [id]);
    });
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المصروفات')),
      floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.add)),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: _list(),
        builder: (c, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return ListView(children: [
            for (final r in snap.data!)
              ListTile(title: Text('${r['no']} — ${r['category']}'), trailing: Text(money.format(r['amount'] as num)))
          ]);
        },
      ),
    );
  }
}

// --------------------------------------------------------------------------
// السندات (قبض / صرف)
// --------------------------------------------------------------------------
class VouchersScreen extends StatefulWidget {
  const VouchersScreen({super.key});
  @override
  State<VouchersScreen> createState() => _VouchersScreenState();
}

class _VouchersScreenState extends State<VouchersScreen> {
  Future<List<Map<String, Object?>>> _list() => AppDb.instance.q('SELECT * FROM vouchers ORDER BY id DESC');

  Future<void> _add() async {
    await Permissions.require('vouchers', Action.add);
    final moneyAccounts = await AppDb.instance.q('SELECT id,name,account_id FROM money_accounts');
    if (moneyAccounts.isEmpty) return;
    String kind = 'receipt';
    int moneyAccountId = moneyAccounts.first['id'] as int;
    final amount = TextEditingController();
    final desc = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('سند مالي'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: kind,
              decoration: const InputDecoration(labelText: 'النوع'),
              items: const [
                DropdownMenuItem(value: 'receipt', child: Text('سند قبض')),
                DropdownMenuItem(value: 'payment', child: Text('سند صرف')),
              ],
              onChanged: (v) => setD(() => kind = v!),
            ),
            DropdownButtonFormField<int>(
              value: moneyAccountId,
              decoration: const InputDecoration(labelText: 'الحساب المالي'),
              items: moneyAccounts.map((m) => DropdownMenuItem(value: m['id'] as int, child: Text(m['name'].toString()))).toList(),
              onChanged: (v) => setD(() => moneyAccountId = v!),
            ),
            TextField(controller: amount, decoration: const InputDecoration(labelText: 'المبلغ'), keyboardType: TextInputType.number),
            TextField(controller: desc, decoration: const InputDecoration(labelText: 'البيان')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حفظ وترحيل')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final amt = double.tryParse(amount.text) ?? 0;
    final now = DateTime.now().toIso8601String();
    await AppDb.instance.db.transaction((tx) async {
      final countRow = await tx.rawQuery('SELECT COUNT(*) c FROM vouchers');
      final no = '${kind == 'receipt' ? 'RC' : 'PV'}-${DateTime.now().year}-${((countRow.first['c'] as int) + 1).toString().padLeft(5, '0')}';
      final id = await tx.insert('vouchers', {
        'no': no, 'kind': kind, 'date': now, 'money_account_id': moneyAccountId, 'amount': amt,
        'description': desc.text, 'status': 'draft', 'created_by': Session.instance.user!.id, 'created': now,
      });
      final moneyRow = (await tx.query('money_accounts', where: 'id=?', whereArgs: [moneyAccountId])).first;
      final moneyAcc = moneyRow['account_id'] as int;
      // سند قبض/صرف عام بدون طرف محدد يُقيّد مقابل حساب "عهد وسلف" (1500) كافتراضي قابل للتخصيص لاحقًا
      final lines = kind == 'receipt'
          ? [
              JournalLineInput(accountId: moneyAcc, debit: amt, description: desc.text),
              JournalLineInput(accountCode: '1500', credit: amt, description: desc.text),
            ]
          : [
              JournalLineInput(accountCode: '1500', debit: amt, description: desc.text),
              JournalLineInput(accountId: moneyAcc, credit: amt, description: desc.text),
            ];
      final journalId = await AccountingEngine.postJournal(tx,
          description: '$no - ${desc.text}', sourceType: 'vouchers', sourceId: id, lines: lines, createdBy: Session.instance.user!.id);
      await tx.update('vouchers', {'status': 'posted', 'journal_id': journalId}, where: 'id=?', whereArgs: [id]);
    });
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('السندات')),
      floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.add)),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: _list(),
        builder: (c, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return ListView(children: [
            for (final r in snap.data!)
              ListTile(title: Text('${r['no']} — ${r['kind'] == 'receipt' ? 'قبض' : 'صرف'}'), trailing: Text(money.format(r['amount'] as num)))
          ]);
        },
      ),
    );
  }
}
