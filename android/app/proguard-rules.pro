# قواعد ProGuard/R8 لبناء الإصدار (release)
# الهدف: تصغير الحجم وتشفير الأسماء دون كسر المكتبات التي تعتمد على reflection

# Flutter embedding
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# sqflite
-keep class com.tekartik.sqflite.** { *; }

# pdf / printing plugin (يستخدمان قنوات Platform Channel قياسية، لا حاجة لقواعد خاصة عادة)
-dontwarn com.itextpdf.**

# نماذج قد تُقرأ عبر reflection من ملفات JSON (النسخ الاحتياطي)
-keepattributes *Annotation*
-keepattributes Signature
