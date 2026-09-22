# دليل بناء APK/AAB خطوة بخطوة

هذا الدليل مكتوب على افتراض أنك تعمل على جهاز فيه Flutter SDK مثبّتًا فعليًا
(هذا الإصدار كُتب في بيئة بلا Flutter/Android SDK ولا إنترنت، لذلك لم يُشغَّل
أي أمر بناء فعليًا هنا — راجع QA_REPORT_AR.md).

## 1) المتطلبات
- Flutter SDK (قناة stable) — يُفضّل أحدث إصدار مستقر متوافق مع Dart >=3.4
- Android SDK (يأتي عادة مع Android Studio) + Java 17
- جهاز Android حقيقي أو محاكي للاختبار

تحقق من الجاهزية:
```bash
flutter doctor
```
يجب ألا تظهر أخطاء حرجة (✗) خصوصًا في Android toolchain.

## 2) تثبيت الاعتماديات
```bash
cd cement_accounting_v3
flutter pub get
```

## 3) إضافة الخط العربي (إلزامي لـ PDF صحيح)
راجع قسم "خطوة إلزامية" في README.md. بدون هذه الخطوة سيبني المشروع بنجاح لكن
نصوص PDF العربية ستظهر بحروف غير متصلة.

## 4) الفحص الساكن والاختبارات (يجب أن تمر قبل أي بناء Release)
```bash
flutter analyze
flutter test
```
إن ظهرت أي أخطاء compilation هنا، يجب إصلاحها قبل المتابعة — **لا تكمل بناء
release قبل أن يمر هذان الأمران بنجاح تام.**

## 5) بناء نسخة تجريبية سريعة (Debug APK)
```bash
flutter build apk --debug
```
الناتج: `build/app/outputs/flutter-apk/app-debug.apk` — صالح للتثبيت المباشر
على جهاز أو محاكي للاختبار، **غير صالح للنشر على المتجر**.

## 6) إعداد التوقيع الحقيقي (إلزامي لبناء Release/AAB)
```bash
keytool -genkey -v -keystore alghouli-release.jks -keyalg RSA -keysize 2048 \
  -validity 10000 -alias alghouli_cement
```
انسخ `android/key.properties.template` إلى `android/key.properties` واملأ:
```properties
storePassword=...
keyPassword=...
keyAlias=alghouli_cement
storeFile=/المسار/الكامل/إلى/alghouli-release.jks
```
**لا تضف `key.properties` ولا ملف `.jks` إلى Git إطلاقًا.**

## 7) بناء AAB للنشر على Google Play
```bash
flutter build appbundle --release
```
الناتج: `build/app/outputs/bundle/release/app-release.aab`

## 8) بناء APK موقّع للاختبار اليدوي (اختياري)
```bash
flutter build apk --release
```
الناتج: `build/app/outputs/flutter-apk/app-release.apk`

## 9) التحقق النهائي قبل الرفع
- [ ] `flutter analyze` بدون أخطاء
- [ ] `flutter test` كل الاختبارات ناجحة
- [ ] `applicationId` في `android/app/build.gradle` فريد ومطابق لحساب Play Console
- [ ] `versionCode`/`versionName` مرفوعان عن آخر نسخة منشورة
- [ ] تم اختبار AAB فعليًا عبر `bundletool` أو رفعه لمسار الاختبار الداخلي في Play Console
- [ ] تسجيل الدخول، تسجيل وترحيل حمولة، طباعة PDF، نسخة احتياطية/استعادة، كلها جُرّبت يدويًا على جهاز حقيقي

## 10) GitHub Actions (بناء تلقائي)
الملف `.github/workflows/android_release.yml` جاهز ويشغّل analyze+test+debug
build تلقائيًا عند كل push. لتفعيل بناء AAB موقّع تلقائيًا:
1. أضف الأسرار (Settings → Secrets → Actions):
   `ANDROID_KEYSTORE_BASE64` (محتوى ملف .jks مُرمّز base64)،
   `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.
2. أضف متغيّر repository variable باسم `ENABLE_RELEASE_SIGNING` بقيمة `true`.

## أخطاء شائعة ومعالجتها
| المشكلة | السبب المحتمل | الحل |
|---|---|---|
| فشل `flutter pub get` | إصدار Dart غير متوافق | حدّث Flutter SDK للقناة stable الأحدث |
| نص PDF العربي مكسور/منفصل الحروف | لم يُضف خط عربي حقيقي | راجع الخطوة 3 |
| فشل التوقيع عند `flutter build appbundle --release` | `key.properties` غير موجود أو مساره خاطئ | تحقق من الخطوة 6 |
| Gradle sync بطيء جدًا أول مرة | تنزيل Gradle 8.7 | انتظر أو اضبط مرآة (mirror) محلية لـ Gradle |
