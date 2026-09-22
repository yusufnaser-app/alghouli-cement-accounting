import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../core/db.dart';
import '../core/reports.dart';
import '../accounting/accounting_engine.dart';
import '../pdf/pdf_templates.dart';
import '../pdf/font_loader.dart';
import '../core/permissions.dart';
import 'dashboard_screen.dart' show money;

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  Future<DocHeaderInfo> _header(String title, String no) async {
    final rows = await AppDb.instance.q("SELECT key,value FROM settings WHERE key IN ('company_name','company_address','company_phone')");
    final map = {for (final r in rows) r['key'] as String: r['value'] as String};
    return DocHeaderInfo(
      companyName: map['company_name'] ?? 'مؤسسة الغولي لتجارة وتسويق الأسمنت',
      companyAddress: map['company_address'] ?? '',
      companyPhone: map['company_phone'] ?? '',
      docTitle: title,
      docNumber: no,
      date: DateTime.now(),
      userName: Session.instance.user?.fullName ?? '-',
    );
  }

  Future<void> _exportAndPrint(BuildContext context, Future<pw.Document> Function() build) async {
    await Permissions.require('reports', Action.print);
    final doc = await build();
    if (PdfFontStatus.usingFallback && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تنبيه: لم يُضف خط عربي بعد للمشروع — النص العربي في PDF لن يظهر بشكل صحيح حتى تضيفه (راجع README)'),
        duration: Duration(seconds: 5),
      ));
    }
    await Printing.layoutPdf(onLayout: (format) => doc.save());
  }

  @override
  Widget build(BuildContext context) {
    final items = <_ReportItem>[
      _ReportItem('تقرير الحمولة اليومية', Icons.today, () => _dailyLoads(context)),
      _ReportItem('تقرير الحمولة الشهرية', Icons.calendar_month, () => _monthlyLoads(context)),
      _ReportItem('تقرير المخزون', Icons.inventory, () => _stockReport(context)),
      _ReportItem('ميزان المراجعة', Icons.balance, () => _trialBalance(context)),
      _ReportItem('الأرباح والخسائر', Icons.trending_up, () => _profitLoss(context)),
      _ReportItem('كشف حساب مصنع', Icons.factory, () => _statementByType(context, 'factory')),
      _ReportItem('كشف حساب تاجر', Icons.handshake, () => _statementByType(context, 'trader')),
      _ReportItem('كشف حساب عميل', Icons.person, () => _statementByType(context, 'customer')),
      _ReportItem('كشف حساب سائق', Icons.drive_eta, () => _statementDriver(context)),
      _ReportItem('كشف حساب قاطرة', Icons.local_shipping, () => _statementTruck(context)),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('التقارير')),
      body: ListView.builder(
        itemCount: items.length,
        itemBuilder: (c, i) => ListTile(
          leading: Icon(items[i].icon),
          title: Text(items[i].title),
          trailing: const Icon(Icons.picture_as_pdf),
          onTap: items[i].onTap,
        ),
      ),
    );
  }

  Future<void> _dailyLoads(BuildContext context) async {
    final rows = await Reports.dailyLoads(DateTime.now());
    await _exportAndPrint(context, () async {
      final font = await ArabicFontLoader.load();
      final header = await _header('تقرير الحمولة اليومية', DateTime.now().toIso8601String().substring(0, 10));
      return PdfTemplates.buildDocument(
        header: header,
        arabicFont: font,
        contentBuilder: () => PdfTemplates.dataTable(
          ['رقم العملية', 'المصنع', 'السائق', 'القاطرة', 'الأكياس', 'الطن', 'إجمالي الشراء'],
          rows
              .map((r) => [
                    r['operation_no'].toString(),
                    r['factory_name'].toString(),
                    r['driver_name'].toString(),
                    r['truck_plate'].toString(),
                    money.format(r['bags'] as num),
                    money.format(r['weight_tons'] as num),
                    money.format(r['purchase_total'] as num),
                  ])
              .toList(),
        ),
      );
    });
  }

  Future<void> _monthlyLoads(BuildContext context) async {
    final now = DateTime.now();
    final rows = await Reports.monthlyLoads(now.year, now.month);
    await _exportAndPrint(context, () async {
      final font = await ArabicFontLoader.load();
      final header = await _header('تقرير الحمولة الشهرية', '${now.year}-${now.month}');
      return PdfTemplates.buildDocument(
        header: header,
        arabicFont: font,
        contentBuilder: () => PdfTemplates.dataTable(
          ['رقم العملية', 'المصنع', 'السائق', 'القاطرة', 'الأكياس'],
          rows
              .map((r) => [
                    r['operation_no'].toString(),
                    r['factory_name'].toString(),
                    r['driver_name'].toString(),
                    r['truck_plate'].toString(),
                    money.format(r['bags'] as num),
                  ])
              .toList(),
        ),
        totalsRows: [
          MapEntry('إجمالي الأكياس', money.format(rows.fold<double>(0, (s, r) => s + (r['bags'] as num).toDouble()))),
          MapEntry('إجمالي النقل', money.format(rows.fold<double>(0, (s, r) => s + (r['transport_total'] as num).toDouble()))),
        ],
      );
    });
  }

  Future<void> _stockReport(BuildContext context) async {
    final products = await Reports.stock();
    await _exportAndPrint(context, () async {
      final font = await ArabicFontLoader.load();
      final header = await _header('تقرير المخزون', DateTime.now().toIso8601String().substring(0, 10));
      return PdfTemplates.buildDocument(
          header: header, arabicFont: font, contentBuilder: () => StockReportContent.build(products));
    });
  }

  Future<void> _trialBalance(BuildContext context) async {
    final rows = await AccountingEngine.trialBalance();
    await _exportAndPrint(context, () async {
      final font = await ArabicFontLoader.load();
      final header = await _header('ميزان المراجعة', DateTime.now().toIso8601String().substring(0, 10));
      return PdfTemplates.buildDocument(
        header: header,
        arabicFont: font,
        contentBuilder: () => PdfTemplates.dataTable(
          ['الكود', 'الحساب', 'مدين', 'دائن', 'الرصيد'],
          rows
              .map((r) => [
                    r['code'].toString(),
                    r['name'].toString(),
                    money.format(r['debit'] as num),
                    money.format(r['credit'] as num),
                    money.format(r['balance'] as num),
                  ])
              .toList(),
        ),
      );
    });
  }

  Future<void> _profitLoss(BuildContext context) async {
    final pnl = await Reports.profitAndLoss();
    await _exportAndPrint(context, () async {
      final font = await ArabicFontLoader.load();
      final header = await _header('الأرباح والخسائر', DateTime.now().toIso8601String().substring(0, 10));
      return PdfTemplates.buildDocument(
        header: header,
        arabicFont: font,
        contentBuilder: () => ProfitLossContent.build(revenue: pnl.revenue, cogs: pnl.cogs, expenses: pnl.expenses),
      );
    });
  }

  Future<void> _statementByType(BuildContext context, String type) async {
    final parties = await AppDb.instance.q('SELECT id,name,account_id FROM parties WHERE type=?', [type]);
    if (!context.mounted) return;
    final chosen = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('اختر الطرف'),
        children: parties
            .map((p) => SimpleDialogOption(child: Text(p['name'].toString()), onPressed: () => Navigator.pop(c, p)))
            .toList(),
      ),
    );
    if (chosen == null || chosen['account_id'] == null) return;
    final lines = await AccountingEngine.statement(chosen['account_id'] as int);
    await _exportAndPrint(context, () async {
      final font = await ArabicFontLoader.load();
      final header = await _header('كشف حساب: ${chosen['name']}', DateTime.now().toIso8601String().substring(0, 10));
      return PdfTemplates.buildDocument(header: header, arabicFont: font, contentBuilder: () => StatementContent.build(lines));
    });
  }

  Future<void> _statementDriver(BuildContext context) async {
    final drivers = await AppDb.instance.q('SELECT id,name,account_id FROM drivers');
    if (!context.mounted) return;
    final chosen = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('اختر السائق'),
        children: drivers
            .map((p) => SimpleDialogOption(child: Text(p['name'].toString()), onPressed: () => Navigator.pop(c, p)))
            .toList(),
      ),
    );
    if (chosen == null || chosen['account_id'] == null) return;
    final lines = await AccountingEngine.statement(chosen['account_id'] as int);
    await _exportAndPrint(context, () async {
      final font = await ArabicFontLoader.load();
      final header = await _header('كشف حساب سائق: ${chosen['name']}', DateTime.now().toIso8601String().substring(0, 10));
      return PdfTemplates.buildDocument(header: header, arabicFont: font, contentBuilder: () => StatementContent.build(lines));
    });
  }

  Future<void> _statementTruck(BuildContext context) async {
    final trucks = await AppDb.instance.q('SELECT id,plate,account_id FROM trucks');
    if (!context.mounted) return;
    final chosen = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('اختر القاطرة'),
        children: trucks
            .map((p) => SimpleDialogOption(child: Text(p['plate'].toString()), onPressed: () => Navigator.pop(c, p)))
            .toList(),
      ),
    );
    if (chosen == null || chosen['account_id'] == null) return;
    final lines = await AccountingEngine.statement(chosen['account_id'] as int);
    await _exportAndPrint(context, () async {
      final font = await ArabicFontLoader.load();
      final header = await _header('كشف حساب قاطرة: ${chosen['plate']}', DateTime.now().toIso8601String().substring(0, 10));
      return PdfTemplates.buildDocument(header: header, arabicFont: font, contentBuilder: () => StatementContent.build(lines));
    });
  }
}

class _ReportItem {
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  _ReportItem(this.title, this.icon, this.onTap);
}
