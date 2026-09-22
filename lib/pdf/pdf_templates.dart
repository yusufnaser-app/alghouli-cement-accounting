// ============================================================================
// قوالب PDF الاحترافية — عربي RTL
// ============================================================================
// ملاحظة تقنية مهمة (صدق تقني وليس ادّعاءً):
// حزمة `pdf` تحتاج خط TrueType يدعم الأحرف العربية وربط الحروف (shaping) حتى
// تظهر الكتابة العربية بشكل صحيح (متصلة وليست حروفًا منفصلة). يجب إضافة ملف
// خط عربي (مثل Cairo أو Noto Naskh Arabic أو Amiri) تحت:
//   assets/fonts/NotoNaskhArabic-Regular.ttf
// وتسجيله في pubspec.yaml ضمن fonts: — ثم تحميله هنا عبر:
//   final font = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf'));
// هذا الملف مكتوب بحيث يقبل الخط كوسيط (fontLoader) بدل تضمينه مباشرة، لأن
// بيئة التطوير الحالية لا تملك اتصال إنترنت لتنزيل ملف خط فعلي — إضافة الخط
// خطوة يدوية واحدة موثقة في README قبل أول بناء فعلي.
// ============================================================================

import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';

typedef ArabicFontLoader = Future<pw.Font> Function();

class DocHeaderInfo {
  final String companyName;
  final String companyAddress;
  final String companyPhone;
  final Uint8List? logoBytes;
  final String docTitle;
  final String docNumber;
  final DateTime date;
  final String userName;
  final Uint8List? stampBytes;
  final String? qrData;

  const DocHeaderInfo({
    required this.companyName,
    this.companyAddress = '',
    this.companyPhone = '',
    this.logoBytes,
    required this.docTitle,
    required this.docNumber,
    required this.date,
    required this.userName,
    this.stampBytes,
    this.qrData,
  });
}

final _money = NumberFormat('#,##0.##', 'en');
final _dateFmt = DateFormat('yyyy-MM-dd HH:mm');

class PdfTemplates {
  /// يبني مستند PDF كامل بالهيكل الموحّد: رأس (شعار/اسم مؤسسة/عنوان مستند/
  /// رقم/تاريخ/مستخدم)، محتوى، إجماليات، تذييل (توقيع/ختم/QR).
  /// [contentBuilder] يُدرج جدول أو تفاصيل خاصة بكل نوع مستند.
  /// [totalsRows] أزواج (تسمية، قيمة) تُعرض في صندوق الإجماليات.
  static Future<pw.Document> buildDocument({
    required DocHeaderInfo header,
    required pw.Font arabicFont,
    required pw.Widget Function() contentBuilder,
    List<MapEntry<String, String>> totalsRows = const [],
    bool showSignatureLine = true,
  }) async {
    final doc = pw.Document();
    final theme = pw.ThemeData.withFont(base: arabicFont, bold: arabicFont);

    doc.addPage(
      pw.MultiPage(
        theme: theme,
        textDirection: pw.TextDirection.rtl,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (ctx) => _buildHeader(header),
        footer: (ctx) => _buildFooter(header, ctx.pageNumber, ctx.pagesCount),
        build: (ctx) => [
          pw.SizedBox(height: 10),
          contentBuilder(),
          if (totalsRows.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            _buildTotalsBox(totalsRows),
          ],
          if (showSignatureLine) ...[
            pw.SizedBox(height: 30),
            _buildSignatureRow(header),
          ],
        ],
      ),
    );
    return doc;
  }

  static pw.Widget _buildHeader(DocHeaderInfo h) {
    return pw.Column(children: [
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(h.companyName, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            if (h.companyAddress.isNotEmpty) pw.Text(h.companyAddress, style: const pw.TextStyle(fontSize: 9)),
            if (h.companyPhone.isNotEmpty) pw.Text('هاتف: ${h.companyPhone}', style: const pw.TextStyle(fontSize: 9)),
          ]),
          if (h.logoBytes != null) pw.Image(pw.MemoryImage(h.logoBytes!), width: 60, height: 60),
        ],
      ),
      pw.Divider(thickness: 1.2),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(h.docTitle, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('رقم المستند: ${h.docNumber}', style: const pw.TextStyle(fontSize: 10)),
            pw.Text('التاريخ: ${_dateFmt.format(h.date)}', style: const pw.TextStyle(fontSize: 10)),
            pw.Text('المستخدم: ${h.userName}', style: const pw.TextStyle(fontSize: 10)),
          ]),
        ],
      ),
      pw.SizedBox(height: 6),
    ]);
  }

  static pw.Widget _buildFooter(DocHeaderInfo h, int page, int totalPages) {
    return pw.Column(children: [
      pw.Divider(thickness: 0.6),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          if (h.qrData != null)
            pw.BarcodeWidget(
              barcode: pw.Barcode.qrCode(),
              data: h.qrData!,
              width: 40,
              height: 40,
            )
          else
            pw.SizedBox(width: 40, height: 40),
          pw.Text('صفحة $page من $totalPages', style: const pw.TextStyle(fontSize: 8)),
          pw.Text(h.companyName, style: const pw.TextStyle(fontSize: 8)),
        ],
      ),
    ]);
  }

  static pw.Widget _buildTotalsBox(List<MapEntry<String, String>> rows) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.8), borderRadius: pw.BorderRadius.circular(4)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: rows
            .map((e) => pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(e.key, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      pw.Text(e.value, style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }

  static pw.Widget _buildSignatureRow(DocHeaderInfo h) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(children: [
          pw.SizedBox(height: h.stampBytes != null ? 0 : 50, width: 100),
          if (h.stampBytes != null) pw.Image(pw.MemoryImage(h.stampBytes!), width: 80, height: 80),
          pw.Text('الختم', style: const pw.TextStyle(fontSize: 9)),
        ]),
        pw.Column(children: const [
          pw.SizedBox(height: 50, width: 140),
          pw.Text('توقيع المستلم', style: pw.TextStyle(fontSize: 9)),
        ]),
        pw.Column(children: const [
          pw.SizedBox(height: 50, width: 140),
          pw.Text('توقيع المحاسب', style: pw.TextStyle(fontSize: 9)),
        ]),
      ],
    );
  }

  /// جدول بيانات عام لعرض قائمة صفوف (يُستخدم في أغلب المستندات).
  static pw.Widget dataTable(List<String> headers, List<List<String>> rows) {
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellAlignment: pw.Alignment.centerRight,
      headerAlignment: pw.Alignment.centerRight,
      border: pw.TableBorder.all(width: 0.5),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    );
  }

  static String money(num v) => _money.format(v);
}

// ----------------------------------------------------------------------
// مولّدات المستندات المحددة (14 قالبًا كما هو مطلوب)
// كل دالة تبني محتوى (pw.Widget) خاصًا بنوع المستند وتُمرَّر إلى buildDocument
// ----------------------------------------------------------------------
class LoadVoucherContent {
  static pw.Widget build(Map<String, Object?> load) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          PdfTemplates.dataTable(
            ['البيان', 'القيمة'],
            [
              ['رقم العملية', load['operation_no'].toString()],
              ['المصنع', load['factory_name'].toString()],
              ['التاجر', (load['trader_name'] ?? '-').toString()],
              ['السائق', load['driver_name'].toString()],
              ['القاطرة', load['truck_plate'].toString()],
              ['نوع الأسمنت', load['product_name'].toString()],
              ['عدد الأكياس', PdfTemplates.money(load['bags'] as num)],
              ['الوزن (طن)', PdfTemplates.money(load['weight_tons'] as num)],
              ['سعر شراء الكيس', PdfTemplates.money(load['purchase_price_bag'] as num)],
              ['إجمالي الشراء', PdfTemplates.money(load['purchase_total'] as num)],
              ['أجرة النقل', PdfTemplates.money(load['transport_total'] as num)],
              ['صافي العمولة', PdfTemplates.money(load['net_commission'] as num)],
            ],
          ),
        ],
      );
}

/// كشف حساب عام (يُستخدم لكل من: مصنع، سائق، قاطرة، تاجر، عميل، صراف، بنك)
class StatementContent {
  static pw.Widget build(List<Map<String, Object?>> lines) => PdfTemplates.dataTable(
        ['التاريخ', 'البيان', 'مدين', 'دائن', 'الرصيد'],
        lines
            .map((l) => [
                  l['date'].toString().substring(0, 10),
                  (l['description'] ?? '').toString(),
                  PdfTemplates.money((l['debit'] as num?) ?? 0),
                  PdfTemplates.money((l['credit'] as num?) ?? 0),
                  PdfTemplates.money((l['running_balance'] as num?) ?? 0),
                ])
            .toList(),
      );
}

class SimpleVoucherContent {
  static pw.Widget build({
    required String kind,
    required String partyName,
    required double amount,
    required String description,
  }) =>
      pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        PdfTemplates.dataTable(['البيان', 'القيمة'], [
          ['نوع السند', kind],
          ['الطرف', partyName],
          ['المبلغ', PdfTemplates.money(amount)],
          ['البيان', description],
        ]),
      ]);
}

class StockReportContent {
  static pw.Widget build(List<Map<String, Object?>> products) => PdfTemplates.dataTable(
        ['المنتج', 'الأكياس', 'الأطنان', 'متوسط التكلفة'],
        products
            .map((p) => [
                  p['name'].toString(),
                  PdfTemplates.money(p['stock_bags'] as num),
                  PdfTemplates.money(p['stock_tons'] as num),
                  PdfTemplates.money(p['avg_unit_cost'] as num),
                ])
            .toList(),
      );
}

class ProfitLossContent {
  static pw.Widget build({required double revenue, required double cogs, required double expenses}) {
    final gross = revenue - cogs;
    final net = gross - expenses;
    return PdfTemplates.dataTable(['البند', 'القيمة'], [
      ['إجمالي المبيعات', PdfTemplates.money(revenue)],
      ['تكلفة البضاعة المباعة', PdfTemplates.money(cogs)],
      ['مجمل الربح', PdfTemplates.money(gross)],
      ['إجمالي المصروفات (نقل + عمولات + حوافز + عمومية)', PdfTemplates.money(expenses)],
      ['صافي الربح', PdfTemplates.money(net)],
    ]);
  }
}
