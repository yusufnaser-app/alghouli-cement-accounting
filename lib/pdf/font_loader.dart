// ============================================================================
// محمّل الخط العربي لملفات PDF
// ============================================================================
// يحاول تحميل خط عربي حقيقي من assets/fonts. إن لم يكن الملف موجودًا (لم
// يُضَف بعد من قبل المطوّر قبل البناء)، يعود لخط افتراضي مع تفعيل علم
// [PdfFontStatus.usingFallback] بحيث تعرض الواجهة تنبيهًا صريحًا للمستخدم بدل
// إنتاج مستندات عربية مكسورة الحروف بصمت.
// ============================================================================

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

class PdfFontStatus {
  static bool usingFallback = false;
}

class ArabicFontLoader {
  static pw.Font? _cached;

  /// المسار المتوقع لملف الخط العربي. أضف ملف TTF عربيًا حقيقيًا هنا قبل
  /// البناء النهائي (راجع README لقائمة خطوط عربية مجانية مقترحة).
  static const assetPath = 'assets/fonts/NotoNaskhArabic-Regular.ttf';

  static Future<pw.Font> load() async {
    if (_cached != null) return _cached!;
    try {
      final data = await rootBundle.load(assetPath);
      _cached = pw.Font.ttf(data);
      PdfFontStatus.usingFallback = false;
    } catch (_) {
      // لا يوجد ملف خط عربي مضاف بعد — نستخدم خطًا افتراضيًا كحل مؤقت فقط.
      // العربية لن تظهر بشكل صحيح (بدون ربط حروف) حتى يُضاف الخط الحقيقي.
      _cached = pw.Font.helvetica();
      PdfFontStatus.usingFallback = true;
    }
    return _cached!;
  }
}
