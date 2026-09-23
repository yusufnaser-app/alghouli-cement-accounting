import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../core/db.dart';
import '../core/permissions.dart';
import '../accounting/accounting_engine.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final Map<String, TextEditingController> _controllers = {};
  bool _loading = true;

  static const _keys = [
    'company_name', 'company_short_name', 'company_phone', 'company_address',
    'currency', 'decimal_places', 'bags_per_ton_default',
    'doc_prefix_load', 'doc_prefix_sale', 'doc_prefix_purchase', 'doc_prefix_expense',
    'whatsapp_template_load', 'sms_template_load',
  ];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    for (final k in _keys) {
      final r = await AppDb.instance.q('SELECT value FROM settings WHERE key=?', [k]);
      _controllers[k] = TextEditingController(text: r.isNotEmpty ? r.first['value'] as String : '');
    }
    setState(() => _loading = false);
  }

  Future<void> _saveAll() async {
    await Permissions.require('settings', PermAction.settings);
    for (final k in _keys) {
      final v = _controllers[k]!.text;
      final exists = await AppDb.instance.q('SELECT id FROM settings WHERE key=?', [k]);
      if (exists.isEmpty) {
        await AppDb.instance.ins('settings', {'key': k, 'value': v});
      } else {
        await AppDb.instance.upd('settings', {'value': v}, 'key=?', [k]);
      }
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ الإعدادات')));
  }

  Future<void> _backup() async {
    final path = await AppDb.instance.backupToFile();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم حفظ النسخة الاحتياطية: $path')));
    }
  }

  Future<void> _restore() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
    if (res == null || res.files.single.path == null) return;
    final file = File(res.files.single.path!);
    final content = await file.readAsString();
    final check = AppDb.validateBackup(content);
    if (!check.ok) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذّرت الاستعادة: ${check.message}')));
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تأكيد الاستعادة'),
        content: const Text('سيتم استبدال كل البيانات الحالية بمحتوى النسخة الاحتياطية. هل أنت متأكد؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('استعادة')),
        ],
      ),
    );
    if (confirm != true) return;
    await AppDb.instance.restoreFromJson(content);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت الاستعادة بنجاح')));
  }

  Future<void> _runIntegrityCheck() async {
    final unbalanced = await AccountingEngine.findUnbalancedJournals();
    if (mounted) {
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('نتيجة فحص سلامة القيود'),
          content: Text(unbalanced.isEmpty
              ? 'كل القيود المحاسبية متوازنة ✅'
              : 'تم العثور على ${unbalanced.length} قيد غير متوازن! يجب المراجعة فورًا.'),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('حسنًا'))],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          const Text('بيانات المؤسسة', style: TextStyle(fontWeight: FontWeight.bold)),
          _field('company_name', 'اسم المؤسسة'),
          _field('company_short_name', 'الاسم المختصر'),
          _field('company_phone', 'الهاتف'),
          _field('company_address', 'العنوان'),
          const Divider(height: 30),
          const Text('العملة والترقيم', style: TextStyle(fontWeight: FontWeight.bold)),
          _field('currency', 'العملة'),
          _field('decimal_places', 'عدد المنازل العشرية'),
          _field('bags_per_ton_default', 'أكياس/طن افتراضي'),
          _field('doc_prefix_load', 'بادئة رقم الحمولة'),
          _field('doc_prefix_sale', 'بادئة فاتورة البيع'),
          _field('doc_prefix_purchase', 'بادئة فاتورة الشراء'),
          _field('doc_prefix_expense', 'بادئة سند المصروف'),
          const Divider(height: 30),
          const Text('قوالب الرسائل (WhatsApp / SMS)', style: TextStyle(fontWeight: FontWeight.bold)),
          const Text('المتغيرات المتاحة: {{factory}} {{driver}} {{truck}} {{bags}} {{tons}} {{transport}} {{operation_no}} {{date}}',
              style: TextStyle(fontSize: 11, color: Colors.grey)),
          _field('whatsapp_template_load', 'قالب واتساب لإشعار الحمولة', lines: 6),
          _field('sms_template_load', 'قالب SMS لإشعار الحمولة', lines: 3),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: _saveAll, icon: const Icon(Icons.save), label: const Text('حفظ الإعدادات')),
          const Divider(height: 30),
          const Text('النسخ الاحتياطي والاستعادة', style: TextStyle(fontWeight: FontWeight.bold)),
          Row(children: [
            Expanded(
                child: OutlinedButton.icon(
                    onPressed: _backup, icon: const Icon(Icons.backup), label: const Text('نسخة احتياطية'))),
            const SizedBox(width: 10),
            Expanded(
                child: OutlinedButton.icon(
                    onPressed: _restore, icon: const Icon(Icons.restore), label: const Text('استعادة'))),
          ]),
          const Divider(height: 30),
          const Text('فحص سلامة النظام', style: TextStyle(fontWeight: FontWeight.bold)),
          OutlinedButton.icon(
              onPressed: _runIntegrityCheck,
              icon: const Icon(Icons.health_and_safety),
              label: const Text('فحص توازن القيود المحاسبية')),
        ],
      ),
    );
  }

  Widget _field(String key, String label, {int lines = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: _controllers[key],
          maxLines: lines,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        ),
      );
}
