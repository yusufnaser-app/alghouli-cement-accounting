"""فحص بنيوي سريع (Structural Smoke Check)
لا يغني هذا السكربت إطلاقًا عن flutter analyze / flutter test / flutter build
الفعلية — فقط يتأكد أن الملفات الجوهرية موجودة قبل محاولة بناء حقيقي.
"""
import os, sys

root = os.path.dirname(os.path.abspath(__file__))
required = [
    'pubspec.yaml',
    'lib/main.dart',
    'lib/app.dart',
    'lib/core/db.dart',
    'lib/core/permissions.dart',
    'lib/core/audit.dart',
    'lib/core/reports.dart',
    'lib/accounting/accounting_engine.dart',
    'lib/accounting/subaccounts.dart',
    'lib/operations/load_operation_service.dart',
    'lib/messaging/message_service.dart',
    'lib/pdf/pdf_templates.dart',
    'lib/pdf/font_loader.dart',
    'lib/screens/login_screen.dart',
    'lib/screens/dashboard_screen.dart',
    'lib/screens/load_screen.dart',
    'lib/screens/parties_screen.dart',
    'lib/screens/transactions_screen.dart',
    'lib/screens/reports_screen.dart',
    'lib/screens/settings_screen.dart',
    'android/app/build.gradle',
    'android/app/src/main/AndroidManifest.xml',
    'android/key.properties.template',
    'database/schema_v3.sql',
    'test/accounting_engine_test.dart',
    'test/load_operation_test.dart',
    'test/backup_and_permissions_test.dart',
]
missing = [p for p in required if not os.path.exists(os.path.join(root, p))]
if missing:
    print('BLOCKER - missing files:\n  - ' + '\n  - '.join(missing))
    sys.exit(1)
print('Structural smoke check passed (%d files verified).' % len(required))
print('NEXT: run in a real Flutter environment: flutter pub get && flutter analyze && flutter test && flutter build appbundle --release')
