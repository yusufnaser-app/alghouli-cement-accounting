# قائمة تحقق ما قبل النشر

راجع أيضًا BUILD_GUIDE_AR.md و QA_REPORT_AR.md.

- [ ] `flutter pub get` بدون أخطاء
- [ ] خط عربي حقيقي مُضاف تحت assets/fonts وأُشير إليه في pubspec.yaml
- [ ] `flutter analyze` بدون أخطاء
- [ ] `flutter test` كل الاختبارات ناجحة
- [ ] تغيير كلمة مرور admin الافتراضية فور أول تشغيل
- [ ] مراجعة/تخصيص دليل الحسابات (lib/core/db.dart → _ensureSystemAccounts) حسب الحاجة الفعلية للمؤسسة
- [ ] `android/key.properties` مُعد بتوقيع حقيقي (غير مرفوع لـ Git)
- [ ] applicationId فريد ومطابق لحساب Play Console: com.alghouli.cement
- [ ] اختبار يدوي كامل على جهاز حقيقي: حمولة → ترحيل → عكس → PDF → نسخة احتياطية/استعادة
- [ ] مراجعة الهوية البصرية مع مصمم جرافيك (الحالية أساسية وظيفية فقط)
- [ ] `flutter build appbundle --release` ناجح فعليًا
- [ ] لقطات شاشة فعلية + سياسة خصوصية قبل رفع أي شيء لـ Google Play
