// ============================================================================
// أداة مساعدة مشتركة للاختبارات: تهيئة قاعدة بيانات في الذاكرة قبل كل اختبار
// ============================================================================
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:cement_accounting_complete/core/db.dart';
import 'package:cement_accounting_complete/core/permissions.dart';

Future<void> freshTestDb() async {
  sqfliteFfiInit();
  await AppDb.instance.initWithFactory(databaseFactoryFfi);
}

/// يسجّل دخول المستخدم admin الافتراضي المزروع تلقائيًا عند إنشاء قاعدة
/// بيانات جديدة، حتى تعمل فحوصات الصلاحيات داخل الاختبارات.
Future<void> loginAsAdmin() async {
  await Session.instance.login('admin', 'admin123');
}
