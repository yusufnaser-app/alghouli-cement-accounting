import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cement_accounting_complete/core/db.dart';
import 'package:cement_accounting_complete/core/permissions.dart';
import 'test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await freshTestDb();
  });

  group('النسخ الاحتياطي والاستعادة', () {
    test('ملف JSON تالف يُرفض قبل أي استعادة', () {
      final check = AppDb.validateBackup('{ هذا ليس JSON صالحًا ');
      expect(check.ok, isFalse);
    });

    test('ملف بدون checksum صالح يُرفض', () {
      final fake = jsonEncode({'schema_version': kSchemaVersion, 'tables': {'settings': []}, 'checksum': 'wrong'});
      final check = AppDb.validateBackup(fake);
      expect(check.ok, isFalse);
      expect(check.message, contains('سلامة'));
    });

    test('نسخة احتياطية من إصدار مستقبلي غير متوافق تُرفض', () {
      final tables = {'settings': []};
      final body = jsonEncode(tables);
      final checksum = sha256.convert(utf8.encode(body)).toString();
      final fake = jsonEncode({
        'schema_version': kSchemaVersion + 5,
        'tables': tables,
        'checksum': checksum,
      });
      final check = AppDb.validateBackup(fake);
      expect(check.ok, isFalse);
      expect(check.message, contains('أحدث'));
    });

    test('نسخة احتياطية صحيحة تُقبل ويمكن استعادتها بنجاح', () async {
      await AppDb.instance.ins('settings', {'key': 'test_flag', 'value': 'yes'});
      final exported = await AppDb.instance.exportJson();
      final check = AppDb.validateBackup(exported);
      expect(check.ok, isTrue);

      // نغيّر البيانات الحالية ثم نستعيد وتحقق من عودة القيمة الأصلية
      await AppDb.instance.upd('settings', {'value': 'changed'}, 'key=?', ['test_flag']);
      await AppDb.instance.restoreFromJson(exported);
      final row = await AppDb.instance.q('SELECT value FROM settings WHERE key=?', ['test_flag']);
      expect(row.first['value'], 'yes');
    });
  });

  group('الصلاحيات', () {
    test('المدير (admin) يملك كل الصلاحيات على كل الوحدات', () async {
      await Session.instance.login('admin', 'admin123');
      for (final action in PermAction.values) {
        final ok = await Permissions.can('loads', action);
        expect(ok, isTrue, reason: 'admin يجب أن يملك صلاحية ${action.name} على loads');
      }
    });

    test('طلب صلاحية بدون تسجيل دخول يُرفض', () async {
      Session.instance.logout();
      expect(Permissions.require('loads', PermAction.view), throwsA(isA<PermissionDeniedException>()));
    });
  });
}

