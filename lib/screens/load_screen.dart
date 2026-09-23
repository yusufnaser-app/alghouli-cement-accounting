import 'package:flutter/material.dart';
import '../core/db.dart';
import '../core/permissions.dart';
import '../operations/load_operation_service.dart';
import 'dashboard_screen.dart' show money;

class LoadListScreen extends StatefulWidget {
  const LoadListScreen({super.key});
  @override
  State<LoadListScreen> createState() => _LoadListScreenState();
}

class _LoadListScreenState extends State<LoadListScreen> {
  Future<List<Map<String, Object?>>> _query() => AppDb.instance.q('''
    SELECT l.*, f.name AS factory_name, d.name AS driver_name, t.plate AS truck_plate
    FROM loads l
    JOIN parties f ON f.id=l.factory_id
    JOIN drivers d ON d.id=l.driver_id
    JOIN trucks t ON t.id=l.truck_id
    ORDER BY l.id DESC LIMIT 200
  ''');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تسجيل وترحيل الحمولة')),
      floatingActionButton: FutureBuilder<bool>(
        future: Permissions.can('loads', PermAction.add),
        builder: (c, s) => (s.data ?? false)
            ? FloatingActionButton.extended(
                icon: const Icon(Icons.add),
                label: const Text('حمولة جديدة'),
                onPressed: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const LoadFormScreen()));
                  setState(() {});
                },
              )
            : const SizedBox.shrink(),
      ),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: _query(),
        builder: (c, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final rows = snap.data!;
          if (rows.isEmpty) return const Center(child: Text('لا توجد عمليات حمولة بعد'));
          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (c, i) {
              final r = rows[i];
              final status = r['status'] as String;
              final statusColor = switch (status) {
                'posted' => Colors.green,
                'reversed' => Colors.red,
                'cancelled' => Colors.grey,
                _ => Colors.orange,
              };
              final statusLabel = switch (status) {
                'posted' => 'مرحّلة',
                'reversed' => 'معكوسة',
                'cancelled' => 'ملغاة',
                _ => 'مسودة',
              };
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: ListTile(
                  title: Text('${r['operation_no']} — ${r['factory_name']}'),
                  subtitle: Text(
                      'السائق: ${r['driver_name']} | القاطرة: ${r['truck_plate']} | أكياس: ${money.format(r['bags'] as num)}'),
                  trailing: Chip(label: Text(statusLabel), backgroundColor: statusColor.withOpacity(0.15)),
                  onTap: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => LoadDetailScreen(loadId: r['id'] as int))),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class LoadFormScreen extends StatefulWidget {
  const LoadFormScreen({super.key});
  @override
  State<LoadFormScreen> createState() => _LoadFormScreenState();
}

class _LoadFormScreenState extends State<LoadFormScreen> {
  int? factoryId, traderId, driverId, truckId, routeId, productId, paymentAccountId;
  final bags = TextEditingController();
  final weight = TextEditingController();
  final bulk = TextEditingController(text: '0');
  final purchasePrice = TextEditingController(text: '0');
  final transportFare = TextEditingController(text: '0');
  final commission = TextEditingController(text: '0');
  final incentive = TextEditingController(text: '0');
  final notes = TextEditingController();
  TransportBeneficiary beneficiary = TransportBeneficiary.driver;
  bool _saving = false;

  double _d(TextEditingController c) => double.tryParse(c.text) ?? 0;

  Future<List<Map<String, Object?>>> _parties(String type) =>
      AppDb.instance.q('SELECT id,name FROM parties WHERE type=? AND active=1', [type]);
  Future<List<Map<String, Object?>>> _drivers() => AppDb.instance.q('SELECT id,name FROM drivers WHERE active=1');
  Future<List<Map<String, Object?>>> _trucks() => AppDb.instance.q('SELECT id,plate FROM trucks WHERE active=1');
  Future<List<Map<String, Object?>>> _routes() => AppDb.instance.q('SELECT id,name FROM routes WHERE active=1');
  Future<List<Map<String, Object?>>> _products() => AppDb.instance.q('SELECT id,name FROM products WHERE active=1');
  Future<List<Map<String, Object?>>> _moneyAccounts() =>
      AppDb.instance.q('SELECT id,name,kind FROM money_accounts WHERE active=1');

  Future<void> _save({required bool postImmediately}) async {
    if (factoryId == null || driverId == null || truckId == null || productId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('يرجى تحديد المصنع والسائق والقاطرة ونوع الأسمنت')));
      return;
    }
    setState(() => _saving = true);
    try {
      final input = LoadInput(
        dateTime: DateTime.now(),
        factoryId: factoryId!,
        traderId: traderId,
        driverId: driverId!,
        truckId: truckId!,
        routeId: routeId,
        productId: productId!,
        bags: _d(bags),
        weightTons: _d(weight),
        bulkTotal: _d(bulk),
        purchasePriceBag: _d(purchasePrice),
        transportFareBag: _d(transportFare),
        commissionBag: _d(commission),
        incentiveBag: _d(incentive),
        transportBeneficiary: beneficiary,
        paymentAccountId: paymentAccountId,
        notes: notes.text,
      );
      final user = Session.instance.user!;
      final id = await LoadOperationService.registerDraft(input, createdBy: user.id);
      if (postImmediately) {
        await LoadOperationService.postLoad(id, postedBy: user.id);
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(postImmediately ? 'تم تسجيل وترحيل الحمولة بنجاح' : 'تم حفظ الحمولة كمسودة')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تسجيل وترحيل الحمولة')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _dropdown('المصنع *', _parties('factory'), (v) => factoryId = v, 'name'),
          _dropdown('التاجر (اختياري)', _parties('trader'), (v) => traderId = v, 'name', allowEmpty: true),
          _dropdown('السائق *', _drivers(), (v) => driverId = v, 'name'),
          _dropdown('القاطرة *', _trucks(), (v) => truckId = v, 'plate'),
          _dropdown('الطريق', _routes(), (v) => routeId = v, 'name', allowEmpty: true),
          _dropdown('نوع الأسمنت *', _products(), (v) => productId = v, 'name'),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _num('عدد الأكياس', bags)),
            const SizedBox(width: 8),
            Expanded(child: _num('الوزن بالطن', weight)),
          ]),
          _num('إجمالي السائب', bulk),
          Row(children: [
            Expanded(child: _num('سعر شراء الكيس', purchasePrice)),
            const SizedBox(width: 8),
            Expanded(child: _num('أجرة النقل/كيس', transportFare)),
          ]),
          Row(children: [
            Expanded(child: _num('العمولة/كيس', commission)),
            const SizedBox(width: 8),
            Expanded(child: _num('الحافز/كيس', incentive)),
          ]),
          const SizedBox(height: 10),
          DropdownButtonFormField<TransportBeneficiary>(
            value: beneficiary,
            decoration: const InputDecoration(labelText: 'جهة استحقاق النقل', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: TransportBeneficiary.driver, child: Text('السائق')),
              DropdownMenuItem(value: TransportBeneficiary.truckOwner, child: Text('مالك القاطرة')),
              DropdownMenuItem(value: TransportBeneficiary.trader, child: Text('التاجر')),
              DropdownMenuItem(value: TransportBeneficiary.driverAndOwner, child: Text('السائق ومالك القاطرة')),
              DropdownMenuItem(value: TransportBeneficiary.other, child: Text('جهة أخرى')),
            ],
            onChanged: (v) => setState(() => beneficiary = v!),
          ),
          const SizedBox(height: 10),
          _dropdown('حساب الصراف/البنك/النقد (تسوية فورية اختيارية)', _moneyAccounts(), (v) => paymentAccountId = v,
              'name', allowEmpty: true),
          const SizedBox(height: 10),
          TextField(
              controller: notes,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'ملاحظات', border: OutlineInputBorder())),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _saving ? null : () => _save(postImmediately: false),
                child: const Text('حفظ كمسودة'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: _saving ? null : () => _confirmPost(),
                icon: const Icon(Icons.send),
                label: const Text('تسجيل وترحيل الحمولة'),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _confirmPost() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تأكيد الترحيل'),
        content: const Text(
            'سيتم ترحيل الحمولة وإنشاء كل الحركات المحاسبية والمخزنية تلقائيًا، ولا يمكن حذفها بعد الترحيل (فقط عكس محاسبي). هل تريد المتابعة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('تأكيد وترحيل')),
        ],
      ),
    );
    if (ok == true) await _save(postImmediately: true);
  }

  Widget _num(String label, TextEditingController c) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        ),
      );

  Widget _dropdown(String label, Future<List<Map<String, Object?>>> future, void Function(int?) onChanged,
      String labelField,
      {bool allowEmpty = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: FutureBuilder<List<Map<String, Object?>>>(
        future: future,
        builder: (c, snap) {
          final items = snap.data ?? [];
          return DropdownButtonFormField<int>(
            decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
            items: [
              if (allowEmpty) const DropdownMenuItem(value: -1, child: Text('بدون')),
              ...items.map((r) => DropdownMenuItem(value: r['id'] as int, child: Text(r[labelField].toString()))),
            ],
            onChanged: (v) => onChanged(v == -1 ? null : v),
          );
        },
      ),
    );
  }
}

class LoadDetailScreen extends StatelessWidget {
  final int loadId;
  const LoadDetailScreen({super.key, required this.loadId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تفاصيل عملية الحمولة')),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: AppDb.instance.q('''
          SELECT l.*, f.name AS factory_name, d.name AS driver_name, t.plate AS truck_plate,
                 p.name AS product_name, tr.name AS trader_name
          FROM loads l
          JOIN parties f ON f.id=l.factory_id
          JOIN drivers d ON d.id=l.driver_id
          JOIN trucks t ON t.id=l.truck_id
          JOIN products p ON p.id=l.product_id
          LEFT JOIN parties tr ON tr.id=l.trader_id
          WHERE l.id=?
        ''', [loadId]),
        builder: (c, snap) {
          if (!snap.hasData || snap.data!.isEmpty) return const Center(child: CircularProgressIndicator());
          final r = snap.data!.first;
          final status = r['status'] as String;
          return ListView(
            padding: const EdgeInsets.all(14),
            children: [
              _row('رقم العملية', r['operation_no'].toString()),
              _row('الحالة', status),
              _row('المصنع', r['factory_name'].toString()),
              _row('التاجر', (r['trader_name'] ?? '-').toString()),
              _row('السائق', r['driver_name'].toString()),
              _row('القاطرة', r['truck_plate'].toString()),
              _row('نوع الأسمنت', r['product_name'].toString()),
              _row('عدد الأكياس', money.format(r['bags'] as num)),
              _row('الوزن (طن)', money.format(r['weight_tons'] as num)),
              _row('إجمالي الشراء', money.format(r['purchase_total'] as num)),
              _row('إجمالي النقل', money.format(r['transport_total'] as num)),
              _row('صافي العمولة', money.format(r['net_commission'] as num)),
              const SizedBox(height: 20),
              if (status == 'posted')
                FutureBuilder<bool>(
                  future: Permissions.can('loads', PermAction.reverse),
                  builder: (c, s) => (s.data ?? false)
                      ? OutlinedButton.icon(
                          icon: const Icon(Icons.undo, color: Colors.red),
                          label: const Text('عكس محاسبي للعملية', style: TextStyle(color: Colors.red)),
                          onPressed: () => _reverse(context),
                        )
                      : const SizedBox.shrink(),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _reverse(BuildContext context) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('عكس محاسبي'),
        content: TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: 'سبب العكس *')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('تراجع')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('تأكيد العكس')),
        ],
      ),
    );
    if (ok != true || reasonCtrl.text.trim().isEmpty) return;
    try {
      await LoadOperationService.reversePostedLoad(loadId,
          userId: Session.instance.user!.id, reason: reasonCtrl.text.trim());
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم العكس المحاسبي بنجاح')));
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    }
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(k, style: const TextStyle(color: Colors.grey)),
          Text(v, style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
      );
}
