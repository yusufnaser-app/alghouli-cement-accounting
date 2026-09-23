import 'package:flutter/material.dart';
import '../core/db.dart';
import '../core/permissions.dart';
import '../core/audit.dart';
import 'dashboard_screen.dart' show money;

class PartiesHubScreen extends StatelessWidget {
  const PartiesHubScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return ListView(children: [
      _tile(context, 'المصانع', Icons.factory, 'factory'),
      _tile(context, 'التجار', Icons.handshake, 'trader'),
      _tile(context, 'العملاء', Icons.person, 'customer'),
      _tile(context, 'الموردون', Icons.local_shipping, 'supplier'),
      ListTile(
        leading: const Icon(Icons.drive_eta),
        title: const Text('السائقون'),
        trailing: const Icon(Icons.chevron_left),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DriversScreen())),
      ),
      ListTile(
        leading: const Icon(Icons.local_shipping_outlined),
        title: const Text('القاطرات'),
        trailing: const Icon(Icons.chevron_left),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TrucksScreen())),
      ),
    ]);
  }

  Widget _tile(BuildContext context, String title, IconData icon, String type) => ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: const Icon(Icons.chevron_left),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PartyListScreen(type: type, title: title))),
      );
}

class PartyListScreen extends StatefulWidget {
  final String type;
  final String title;
  const PartyListScreen({super.key, required this.type, required this.title});
  @override
  State<PartyListScreen> createState() => _PartyListScreenState();
}

class _PartyListScreenState extends State<PartyListScreen> {
  Future<List<Map<String, Object?>>> _list() =>
      AppDb.instance.q('SELECT * FROM parties WHERE type=? ORDER BY id DESC', [widget.type]);

  Future<void> _add() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final address = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('إضافة ${widget.title}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم *')),
          TextField(controller: phone, decoration: const InputDecoration(labelText: 'الهاتف')),
          TextField(controller: address, decoration: const InputDecoration(labelText: 'العنوان')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final id = await AppDb.instance.ins('parties', {
      'type': widget.type,
      'name': name.text.trim(),
      'phone': phone.text.trim(),
      'address': address.text.trim(),
      'created': DateTime.now().toIso8601String(),
    });
    await Audit.log(action: 'create', entity: 'parties', entityId: id, after: {'name': name.text});
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      floatingActionButton: FutureBuilder<bool>(
        future: Permissions.can('parties', PermAction.add),
        builder: (c, s) =>
            (s.data ?? false) ? FloatingActionButton(onPressed: _add, child: const Icon(Icons.add)) : const SizedBox.shrink(),
      ),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: _list(),
        builder: (c, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final rows = snap.data!;
          if (rows.isEmpty) return const Center(child: Text('لا توجد سجلات بعد'));
          return ListView(children: [
            for (final r in rows)
              ListTile(
                title: Text(r['name'].toString()),
                subtitle: Text(r['phone']?.toString() ?? ''),
                trailing: Text(money.format((r['opening'] as num?) ?? 0)),
              )
          ]);
        },
      ),
    );
  }
}

class DriversScreen extends StatefulWidget {
  const DriversScreen({super.key});
  @override
  State<DriversScreen> createState() => _DriversScreenState();
}

class _DriversScreenState extends State<DriversScreen> {
  Future<List<Map<String, Object?>>> _list() => AppDb.instance.q('SELECT * FROM drivers ORDER BY id DESC');
  Future<List<Map<String, Object?>>> _traders() =>
      AppDb.instance.q("SELECT id,name FROM parties WHERE type='trader'");

  Future<void> _add() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    String kind = 'independent';
    int? traderId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('إضافة سائق'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم *')),
            TextField(controller: phone, decoration: const InputDecoration(labelText: 'الهاتف (لإشعارات واتساب)')),
            DropdownButtonFormField<String>(
              value: kind,
              decoration: const InputDecoration(labelText: 'نوع السائق'),
              items: const [
                DropdownMenuItem(value: 'institution', child: Text('تابع للمؤسسة')),
                DropdownMenuItem(value: 'trader_driver', child: Text('تابع لتاجر آخر')),
                DropdownMenuItem(value: 'truck_owner', child: Text('مالك قاطرة')),
                DropdownMenuItem(value: 'independent', child: Text('مستقل')),
              ],
              onChanged: (v) => setD(() => kind = v!),
            ),
            if (kind == 'trader_driver')
              FutureBuilder<List<Map<String, Object?>>>(
                future: _traders(),
                builder: (c, s) => DropdownButtonFormField<int>(
                  decoration: const InputDecoration(labelText: 'التاجر التابع له'),
                  items: (s.data ?? [])
                      .map((t) => DropdownMenuItem(value: t['id'] as int, child: Text(t['name'].toString())))
                      .toList(),
                  onChanged: (v) => traderId = v,
                ),
              ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    await AppDb.instance.ins('drivers', {
      'name': name.text.trim(),
      'phone': phone.text.trim(),
      'driver_kind': kind,
      'linked_trader_id': traderId,
      'created': DateTime.now().toIso8601String(),
    });
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('السائقون')),
      floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.add)),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: _list(),
        builder: (c, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return ListView(children: [
            for (final r in snap.data!)
              ListTile(title: Text(r['name'].toString()), subtitle: Text('${r['driver_kind']} | ${r['phone'] ?? ''}'))
          ]);
        },
      ),
    );
  }
}

class TrucksScreen extends StatefulWidget {
  const TrucksScreen({super.key});
  @override
  State<TrucksScreen> createState() => _TrucksScreenState();
}

class _TrucksScreenState extends State<TrucksScreen> {
  Future<List<Map<String, Object?>>> _list() => AppDb.instance.q('SELECT * FROM trucks ORDER BY id DESC');
  Future<List<Map<String, Object?>>> _drivers() => AppDb.instance.q('SELECT id,name FROM drivers');

  Future<void> _add() async {
    final plate = TextEditingController();
    String ownerKind = 'driver';
    int? ownerDriverId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('إضافة قاطرة'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: plate, decoration: const InputDecoration(labelText: 'رقم اللوحة *')),
            DropdownButtonFormField<String>(
              value: ownerKind,
              decoration: const InputDecoration(labelText: 'ملكية القاطرة'),
              items: const [
                DropdownMenuItem(value: 'institution', child: Text('المؤسسة')),
                DropdownMenuItem(value: 'driver', child: Text('السائق نفسه')),
                DropdownMenuItem(value: 'trader', child: Text('تاجر')),
              ],
              onChanged: (v) => setD(() => ownerKind = v!),
            ),
            FutureBuilder<List<Map<String, Object?>>>(
              future: _drivers(),
              builder: (c, s) => DropdownButtonFormField<int>(
                decoration: const InputDecoration(labelText: 'السائق الافتراضي'),
                items: (s.data ?? [])
                    .map((d) => DropdownMenuItem(value: d['id'] as int, child: Text(d['name'].toString())))
                    .toList(),
                onChanged: (v) => ownerDriverId = v,
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (ok != true || plate.text.trim().isEmpty) return;
    await AppDb.instance.ins('trucks', {
      'plate': plate.text.trim(),
      'owner_kind': ownerKind,
      'owner_driver_id': ownerDriverId,
      'default_driver_id': ownerDriverId,
      'created': DateTime.now().toIso8601String(),
    });
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('القاطرات')),
      floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.add)),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: _list(),
        builder: (c, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return ListView(children: [
            for (final r in snap.data!) ListTile(title: Text(r['plate'].toString()), subtitle: Text(r['owner_kind'].toString()))
          ]);
        },
      ),
    );
  }
}
