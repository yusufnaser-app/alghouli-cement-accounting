// ============================================================================
// طبقة قاعدة البيانات الأساسية — نظام محاسبة وإدارة تجارة وتوزيع الأسمنت
// ============================================================================
// يحتوي هذا الملف على:
//  - المخطط الكامل لقاعدة البيانات (V3)
//  - الترقية الآمنة من V2 إلى V3 (بدون فقد بيانات)
//  - دوال مساعدة عامة للاستعلام والإدراج والتحديث
//  - النسخ الاحتياطي والاستعادة مع حماية من الملفات التالفة/غير المتوافقة
// ============================================================================

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// إصدار مخطط قاعدة البيانات الحالي. أي تغيير في المخطط يجب أن يرفع هذا الرقم
/// ويضيف خطوة ترقية صريحة في [_migrate].
const int kSchemaVersion = 3;

class AppDb {
  AppDb._();
  static final AppDb instance = AppDb._();
  Database? _db;
  Database get db => _db!;
  bool get isReady => _db != null;

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    final p = join(dir.path, 'cement_accounting_v3.db');
    _db = await openDatabase(
      p,
      version: kSchemaVersion,
      onConfigure: (d) async => d.execute('PRAGMA foreign_keys = ON'),
      onCreate: (d, v) async {
        await _createV3Schema(d);
        await _seed(d);
      },
      onUpgrade: (d, oldV, newV) async => _migrate(d, oldV, newV),
    );
  }

  /// نقطة دخول مخصّصة للاختبارات: تنشئ قاعدة بيانات في الذاكرة عبر
  /// databaseFactory المُمرَّر (عادة sqflite_common_ffi في بيئة سطح المكتب/CI
  /// حيث لا يتوفر مزوّد المنصة الحقيقي). راجع test/test_helpers.dart.
  ///
  /// مهم: يُغلق أي اتصال سابق صراحة قبل فتح اتصال جديد. بدون هذا، يعيد
  /// sqflite/sqflite_common_ffi نفس الاتصال المفتوح مسبقًا لنفس المسار
  /// (':memory:' هنا) بدل إنشاء قاعدة بيانات فارغة حقيقية، ما يجعل بيانات
  /// اختبار سابق "تتسرّب" إلى الاختبار التالي بصمت.
  Future<void> initWithFactory(DatabaseFactory factory, {String path = inMemoryDatabasePath}) async {
    if (_db != null) {
      try {
        await _db!.close();
      } catch (_) {
        // تجاهل أي خطأ إغلاق (قد يكون مُغلقًا مسبقًا) — الهدف ضمان عدم بقاء اتصال قديم فقط
      }
      _db = null;
    }
    _db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: kSchemaVersion,
        onConfigure: (d) async => d.execute('PRAGMA foreign_keys = ON'),
        onCreate: (d, v) async {
          await _createV3Schema(d);
          await _seed(d);
        },
        onUpgrade: (d, oldV, newV) async => _migrate(d, oldV, newV),
      ),
    );
  }

  // --------------------------------------------------------------------
  // الترقية بين الإصدارات — يجب ألا تُحذف أي بيانات موجودة أثناء الترقية.
  // --------------------------------------------------------------------
  Future<void> _migrate(Database d, int oldV, int newV) async {
    if (oldV < 2) {
      // إصدارات قديمة جدًا: أنشئ المخطط الكامل مباشرة (قاعدة بيانات فارغة أساسًا)
      await _createV3Schema(d);
      await _seed(d);
      return;
    }
    if (oldV < 3) {
      await _upgradeV2toV3(d);
    }
  }

  /// ترقية V2 -> V3: تضيف كل الجداول والأعمدة الجديدة اللازمة لدورة الحمولة
  /// الموحّدة والصلاحيات والمستخدمين والإشعارات، مع الحفاظ على بيانات V2.
  Future<void> _upgradeV2toV3(Database d) async {
    await d.transaction((tx) async {
      // أعمدة جديدة على جدول shipments القديم (إن وُجد) لتحويله تدريجيًا
      final existing = await tx.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='shipments'");
      if (existing.isNotEmpty) {
        final cols = await tx.rawQuery('PRAGMA table_info(shipments)');
        final names = cols.map((c) => c['name'] as String).toSet();
        Future<void> addCol(String name, String type) async {
          if (!names.contains(name)) {
            await tx.execute('ALTER TABLE shipments ADD COLUMN $name $type');
          }
        }

        await addCol('trader_id', 'INTEGER');
        await addCol('transport_beneficiary_type', 'TEXT');
        await addCol('transport_beneficiary_id', 'INTEGER');
        await addCol('payment_account_id', 'INTEGER');
        await addCol('journal_id', 'INTEGER');
        await addCol('status', "TEXT DEFAULT 'draft'");
        await addCol('net_commission', 'REAL DEFAULT 0');
        await addCol('operation_no', 'TEXT');
      }

      for (final s in _v3OnlyTableStatements()) {
        await tx.execute(s);
      }

      // ترحيل حسابات دليل الحسابات: تأكد من وجود الحسابات النظامية الجديدة
      await _ensureSystemAccounts(tx);
      // ترحيل مستخدم مدير افتراضي إن لم يوجد أي مستخدم
      final users = await tx.query('users');
      if (users.isEmpty) {
        await _seedUsersAndRoles(tx);
      }
    });
  }

  Future<void> _createV3Schema(Database d) async {
    for (final s in _coreTableStatements()) {
      await d.execute(s);
    }
    for (final s in _v3OnlyTableStatements()) {
      await d.execute(s);
    }
    await d.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_loads_opno ON loads(operation_no)');
    await d.execute(
        'CREATE INDEX IF NOT EXISTS idx_journal_lines_account ON journal_lines(account_id)');
    await d.execute(
        'CREATE INDEX IF NOT EXISTS idx_loads_status ON loads(status)');
  }

  /// الجداول الأساسية الموروثة من V2 (مع تحسينات) — تُنشأ فقط عند إنشاء قاعدة
  /// بيانات جديدة بالكامل؛ الترقية من V2 الحقيقية تستخدم الجدول الموجود فعليًا.
  List<String> _coreTableStatements() => [
        '''CREATE TABLE IF NOT EXISTS settings(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            key TEXT UNIQUE NOT NULL,
            value TEXT NOT NULL)''',
        '''CREATE TABLE IF NOT EXISTS accounts(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            code TEXT UNIQUE NOT NULL,
            name TEXT NOT NULL,
            type TEXT NOT NULL CHECK(type IN ('asset','liability','equity','revenue','expense')),
            parent_id INTEGER,
            is_system INTEGER DEFAULT 0,
            active INTEGER DEFAULT 1,
            created TEXT NOT NULL)''',
        '''CREATE TABLE IF NOT EXISTS journals(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            no TEXT UNIQUE NOT NULL,
            date TEXT NOT NULL,
            source_type TEXT NOT NULL,
            source_id INTEGER,
            description TEXT,
            reversed_of INTEGER,
            reversed_by INTEGER,
            posted INTEGER DEFAULT 1,
            created_by INTEGER,
            created TEXT NOT NULL)''',
        '''CREATE TABLE IF NOT EXISTS journal_lines(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            journal_id INTEGER NOT NULL REFERENCES journals(id),
            account_id INTEGER NOT NULL REFERENCES accounts(id),
            debit REAL DEFAULT 0,
            credit REAL DEFAULT 0,
            description TEXT)''',
        '''CREATE TABLE IF NOT EXISTS parties(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL CHECK(type IN ('factory','trader','customer','supplier')),
            name TEXT NOT NULL,
            phone TEXT,
            address TEXT,
            account_id INTEGER REFERENCES accounts(id),
            opening REAL DEFAULT 0,
            active INTEGER DEFAULT 1,
            note TEXT,
            created TEXT NOT NULL)''',
        '''CREATE TABLE IF NOT EXISTS drivers(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            phone TEXT,
            driver_no TEXT,
            driver_kind TEXT NOT NULL DEFAULT 'independent'
              CHECK(driver_kind IN ('institution','trader_driver','truck_owner','independent')),
            linked_trader_id INTEGER REFERENCES parties(id),
            account_id INTEGER REFERENCES accounts(id),
            opening REAL DEFAULT 0,
            active INTEGER DEFAULT 1,
            note TEXT,
            created TEXT NOT NULL)''',
        '''CREATE TABLE IF NOT EXISTS trucks(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            plate TEXT UNIQUE NOT NULL,
            owner_kind TEXT NOT NULL DEFAULT 'driver'
              CHECK(owner_kind IN ('institution','driver','trader')),
            owner_driver_id INTEGER REFERENCES drivers(id),
            owner_trader_id INTEGER REFERENCES parties(id),
            default_driver_id INTEGER REFERENCES drivers(id),
            account_id INTEGER REFERENCES accounts(id),
            capacity_tons REAL DEFAULT 0,
            active INTEGER DEFAULT 1,
            note TEXT,
            created TEXT NOT NULL)''',
        '''CREATE TABLE IF NOT EXISTS routes(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            default_transport_rate REAL DEFAULT 0,
            active INTEGER DEFAULT 1,
            note TEXT,
            created TEXT NOT NULL)''',
        '''CREATE TABLE IF NOT EXISTS money_accounts(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            kind TEXT NOT NULL CHECK(kind IN ('cash','bank','exchanger')),
            name TEXT NOT NULL,
            account_id INTEGER REFERENCES accounts(id),
            currency TEXT DEFAULT 'YER',
            phone TEXT,
            active INTEGER DEFAULT 1,
            note TEXT,
            created TEXT NOT NULL)''',
        '''CREATE TABLE IF NOT EXISTS products(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            unit TEXT DEFAULT 'كيس',
            bags_per_ton REAL DEFAULT 20,
            sale_price REAL DEFAULT 0,
            stock_bags REAL DEFAULT 0,
            stock_tons REAL DEFAULT 0,
            avg_unit_cost REAL DEFAULT 0,
            active INTEGER DEFAULT 1,
            note TEXT,
            created TEXT NOT NULL)''',
        '''CREATE TABLE IF NOT EXISTS stock_moves(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL,
            product_id INTEGER NOT NULL REFERENCES products(id),
            bags REAL NOT NULL,
            tons REAL NOT NULL,
            unit_cost REAL DEFAULT 0,
            direction TEXT NOT NULL CHECK(direction IN ('in','out')),
            move_type TEXT NOT NULL,
            source_type TEXT,
            source_id INTEGER,
            note TEXT,
            created TEXT NOT NULL)''',
        '''CREATE TABLE IF NOT EXISTS sales(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            no TEXT UNIQUE NOT NULL,
            date TEXT NOT NULL,
            customer_id INTEGER REFERENCES parties(id),
            product_id INTEGER REFERENCES products(id),
            bags REAL DEFAULT 0,
            price REAL DEFAULT 0,
            total REAL DEFAULT 0,
            paid REAL DEFAULT 0,
            remaining REAL DEFAULT 0,
            money_account_id INTEGER REFERENCES money_accounts(id),
            status TEXT DEFAULT 'draft' CHECK(status IN ('draft','posted','cancelled','reversed')),
            journal_id INTEGER,
            note TEXT,
            created_by INTEGER,
            created TEXT NOT NULL)''',
        '''CREATE TABLE IF NOT EXISTS purchases(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            no TEXT UNIQUE NOT NULL,
            date TEXT NOT NULL,
            supplier_id INTEGER REFERENCES parties(id),
            product_id INTEGER REFERENCES products(id),
            bags REAL DEFAULT 0,
            price REAL DEFAULT 0,
            total REAL DEFAULT 0,
            paid REAL DEFAULT 0,
            remaining REAL DEFAULT 0,
            money_account_id INTEGER REFERENCES money_accounts(id),
            status TEXT DEFAULT 'draft' CHECK(status IN ('draft','posted','cancelled','reversed')),
            journal_id INTEGER,
            note TEXT,
            created_by INTEGER,
            created TEXT NOT NULL)''',
        '''CREATE TABLE IF NOT EXISTS expenses(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            no TEXT UNIQUE NOT NULL,
            date TEXT NOT NULL,
            category TEXT NOT NULL,
            expense_account_id INTEGER REFERENCES accounts(id),
            amount REAL DEFAULT 0,
            money_account_id INTEGER REFERENCES money_accounts(id),
            status TEXT DEFAULT 'draft' CHECK(status IN ('draft','posted','cancelled','reversed')),
            journal_id INTEGER,
            note TEXT,
            created_by INTEGER,
            created TEXT NOT NULL)''',
        '''CREATE TABLE IF NOT EXISTS vouchers(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            no TEXT UNIQUE NOT NULL,
            kind TEXT NOT NULL CHECK(kind IN ('receipt','payment','transfer')),
            date TEXT NOT NULL,
            party_type TEXT,
            party_id INTEGER,
            money_account_id INTEGER REFERENCES money_accounts(id),
            counter_money_account_id INTEGER REFERENCES money_accounts(id),
            amount REAL DEFAULT 0,
            currency TEXT DEFAULT 'YER',
            description TEXT,
            status TEXT DEFAULT 'draft' CHECK(status IN ('draft','posted','cancelled','reversed')),
            journal_id INTEGER,
            created_by INTEGER,
            created TEXT NOT NULL)''',
      ];

  /// جداول جديدة كليًا في V3: المستخدمون/الصلاحيات، عملية الحمولة الموحّدة،
  /// الإشعارات، سجل التدقيق المفصّل.
  List<String> _v3OnlyTableStatements() => [
        '''CREATE TABLE IF NOT EXISTS users(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,
            password_salt TEXT NOT NULL,
            full_name TEXT,
            role TEXT NOT NULL,
            active INTEGER DEFAULT 1,
            last_login TEXT,
            created TEXT NOT NULL)''',
        '''CREATE TABLE IF NOT EXISTS role_permissions(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            role TEXT NOT NULL,
            module TEXT NOT NULL,
            can_view INTEGER DEFAULT 0,
            can_add INTEGER DEFAULT 0,
            can_edit INTEGER DEFAULT 0,
            can_post INTEGER DEFAULT 0,
            can_cancel INTEGER DEFAULT 0,
            can_reverse INTEGER DEFAULT 0,
            can_print INTEGER DEFAULT 0,
            can_export INTEGER DEFAULT 0,
            can_send INTEGER DEFAULT 0,
            can_settings INTEGER DEFAULT 0,
            UNIQUE(role, module))''',
        '''CREATE TABLE IF NOT EXISTS loads(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            operation_no TEXT UNIQUE NOT NULL,
            datetime TEXT NOT NULL,
            factory_id INTEGER NOT NULL REFERENCES parties(id),
            trader_id INTEGER REFERENCES parties(id),
            driver_id INTEGER NOT NULL REFERENCES drivers(id),
            truck_id INTEGER NOT NULL REFERENCES trucks(id),
            route_id INTEGER REFERENCES routes(id),
            product_id INTEGER NOT NULL REFERENCES products(id),
            bags REAL NOT NULL DEFAULT 0,
            weight_tons REAL NOT NULL DEFAULT 0,
            bulk_total REAL DEFAULT 0,
            purchase_price_bag REAL DEFAULT 0,
            purchase_total REAL DEFAULT 0,
            transport_fare_bag REAL DEFAULT 0,
            transport_total REAL DEFAULT 0,
            commission_bag REAL DEFAULT 0,
            commission_total REAL DEFAULT 0,
            incentive_bag REAL DEFAULT 0,
            incentive_total REAL DEFAULT 0,
            net_commission REAL DEFAULT 0,
            transport_beneficiary_type TEXT NOT NULL DEFAULT 'driver'
              CHECK(transport_beneficiary_type IN ('driver','truck_owner','trader','driver_and_owner','other')),
            transport_beneficiary_id INTEGER,
            transport_beneficiary_other_name TEXT,
            payment_account_id INTEGER REFERENCES money_accounts(id),
            status TEXT NOT NULL DEFAULT 'draft'
              CHECK(status IN ('draft','posted','cancelled','reversed')),
            journal_id INTEGER REFERENCES journals(id),
            reversal_journal_id INTEGER,
            notes TEXT,
            created_by INTEGER REFERENCES users(id),
            posted_by INTEGER REFERENCES users(id),
            posted_at TEXT,
            created TEXT NOT NULL)''',
        '''CREATE TABLE IF NOT EXISTS notifications(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            load_id INTEGER REFERENCES loads(id),
            channel TEXT NOT NULL CHECK(channel IN ('whatsapp','sms')),
            recipient_phone TEXT,
            message TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','sent','failed')),
            error TEXT,
            created TEXT NOT NULL,
            updated TEXT NOT NULL)''',
        '''CREATE TABLE IF NOT EXISTS audit_log(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER,
            username TEXT,
            action TEXT NOT NULL,
            entity TEXT NOT NULL,
            entity_id INTEGER,
            before_json TEXT,
            after_json TEXT,
            created TEXT NOT NULL)''',
        '''CREATE TABLE IF NOT EXISTS sync_queue(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            entity TEXT NOT NULL,
            entity_id INTEGER NOT NULL,
            action TEXT NOT NULL,
            payload TEXT NOT NULL,
            created TEXT NOT NULL,
            synced INTEGER DEFAULT 0)''',
      ];

  // --------------------------------------------------------------------
  // البذر الأولي (قاعدة بيانات جديدة)
  // --------------------------------------------------------------------
  Future<void> _seed(Database d) async {
    final now = DateTime.now().toIso8601String();
    final defaults = <String, String>{
      'company_name': 'مؤسسة الغولي لتجارة وتسويق الأسمنت',
      'company_short_name': 'الغولي للأسمنت',
      'company_phone': '',
      'company_address': '',
      'currency': 'YER',
      'decimal_places': '0',
      'bags_per_ton_default': '20',
      'doc_prefix_load': 'LD',
      'doc_prefix_sale': 'SI',
      'doc_prefix_purchase': 'PI',
      'doc_prefix_expense': 'EX',
      'doc_prefix_voucher_receipt': 'RC',
      'doc_prefix_voucher_payment': 'PV',
      'commission_expense_account_code': '5200',
      'incentive_expense_account_code': '5210',
      'transport_expense_account_code': '5100',
      'whatsapp_template_load': 'تم تقييد الحمولة بنجاح\n'
          'المصنع: {{factory}}\n'
          'السائق: {{driver}}\n'
          'القاطرة: {{truck}}\n'
          'الكمية: {{bulk}}\n'
          'عدد الأكياس: {{bags}}\n'
          'الطن: {{tons}}\n'
          'أجرة النقل: {{transport}}\n'
          'رقم العملية: {{operation_no}}\n'
          'التاريخ: {{date}}\n\n'
          'تم تسجيل مستحق النقل في حسابك.',
      'sms_template_load': 'تم تقييد حمولتك رقم {{operation_no}} بتاريخ {{date}}. '
          'أجرة النقل: {{transport}}. تم تسجيلها في حسابك - {{factory}}',
    };
    for (final e in defaults.entries) {
      await d.insert('settings', {'key': e.key, 'value': e.value});
    }
    await _ensureSystemAccounts(d);
    await d.insert('products', {
      'name': 'أسمنت 50 كجم',
      'unit': 'كيس',
      'bags_per_ton': 20,
      'created': now,
    });
    await d.insert('money_accounts', {
      'kind': 'cash',
      'name': 'الصندوق الرئيسي',
      'account_id': await _accountIdByCode(d, '1000'),
      'created': now,
    });
    await _seedUsersAndRoles(d);
  }

  Future<void> _ensureSystemAccounts(DatabaseExecutor d) async {
    final now = DateTime.now().toIso8601String();
    // (code, name, type)
    const chart = <List<String>>[
      ['1000', 'الصندوق', 'asset'],
      ['1100', 'البنوك', 'asset'],
      ['1200', 'شركات الصرافة', 'asset'],
      ['1300', 'العملاء', 'asset'],
      ['1310', 'التجار (مدينون)', 'asset'],
      ['1400', 'المخزون', 'asset'],
      ['1500', 'العهد والسلف', 'asset'],
      ['2000', 'المصانع والموردون', 'liability'],
      ['2100', 'السائقون - مستحقات', 'liability'],
      ['2110', 'ملاك القاطرات - مستحقات', 'liability'],
      ['2200', 'النقل المستحق', 'liability'],
      ['2300', 'العمولات المستحقة', 'liability'],
      ['2400', 'الحوافز المستحقة', 'liability'],
      ['3000', 'رأس المال', 'equity'],
      ['3100', 'الأرباح المرحّلة', 'equity'],
      ['4000', 'المبيعات', 'revenue'],
      ['5000', 'تكلفة البضاعة المباعة', 'expense'],
      ['5100', 'مصروف النقل', 'expense'],
      ['5200', 'مصروف العمولات', 'expense'],
      ['5210', 'مصروف الحوافز', 'expense'],
      ['5300', 'مصروفات عمومية وإدارية', 'expense'],
      ['5400', 'مشتريات الأسمنت (السائب/الأكياس)', 'expense'],
    ];
    for (final row in chart) {
      final existing = await d.query('accounts', where: 'code=?', whereArgs: [row[0]]);
      if (existing.isEmpty) {
        await d.insert('accounts', {
          'code': row[0],
          'name': row[1],
          'type': row[2],
          'is_system': 1,
          'created': now,
        });
      }
    }
  }

  Future<void> _seedUsersAndRoles(DatabaseExecutor d) async {
    final now = DateTime.now().toIso8601String();
    // أدوار النظام والصلاحيات الافتراضية لكل دور. المدير له كل الصلاحيات.
    const roles = ['admin', 'accountant', 'factory_staff', 'sales', 'transport', 'reports'];
    const modules = [
      'dashboard', 'loads', 'sales', 'purchases', 'expenses', 'vouchers',
      'parties', 'drivers', 'trucks', 'products', 'accounts', 'reports',
      'settings', 'backup', 'users',
    ];
    // مصفوفة صلاحيات افتراضية معقولة لكل دور (يمكن تعديلها لاحقًا من الإعدادات)
    Map<String, bool> allTrue() => {
          'view': true, 'add': true, 'edit': true, 'post': true, 'cancel': true,
          'reverse': true, 'print': true, 'export': true, 'send': true, 'settings': true,
        };
    Map<String, bool> viewOnly() => {
          'view': true, 'add': false, 'edit': false, 'post': false, 'cancel': false,
          'reverse': false, 'print': true, 'export': true, 'send': false, 'settings': false,
        };
    for (final module in modules) {
      Map<String, bool> perms;
      switch (module) {
        case 'reports':
          perms = viewOnly();
          break;
        default:
          perms = {
            'view': true, 'add': true, 'edit': true, 'post': false, 'cancel': false,
            'reverse': false, 'print': true, 'export': false, 'send': false, 'settings': false,
          };
      }
      for (final role in roles) {
        Map<String, bool> p = role == 'admin' ? allTrue() : Map.of(perms);
        if (role == 'accountant' && ['loads', 'sales', 'purchases', 'expenses', 'vouchers'].contains(module)) {
          p = allTrue();
        }
        if (role == 'factory_staff' && module == 'loads') {
          p = {...perms, 'add': true, 'post': true};
        }
        if (role == 'sales' && module == 'sales') {
          p = {...perms, 'add': true, 'post': true};
        }
        if (role == 'transport' && (module == 'loads' || module == 'drivers' || module == 'trucks')) {
          p = {...perms, 'add': true, 'send': true};
        }
        if (role == 'reports') {
          p = module == 'reports' ? allTrue() : viewOnly();
        }
        await d.insert('role_permissions', {
          'role': role,
          'module': module,
          'can_view': p['view']! ? 1 : 0,
          'can_add': p['add']! ? 1 : 0,
          'can_edit': p['edit']! ? 1 : 0,
          'can_post': p['post']! ? 1 : 0,
          'can_cancel': p['cancel']! ? 1 : 0,
          'can_reverse': p['reverse']! ? 1 : 0,
          'can_print': p['print']! ? 1 : 0,
          'can_export': p['export']! ? 1 : 0,
          'can_send': p['send']! ? 1 : 0,
          'can_settings': p['settings']! ? 1 : 0,
        });
      }
    }
    // مستخدم مدير افتراضي — يجب تغيير كلمة المرور فورًا من الإعدادات.
    final salt = _generateSalt();
    await d.insert('users', {
      'username': 'admin',
      'password_hash': _hashPassword('admin123', salt),
      'password_salt': salt,
      'full_name': 'مدير النظام',
      'role': 'admin',
      'created': now,
    });
  }

  Future<int> _accountIdByCode(DatabaseExecutor d, String code) async {
    final r = await d.query('accounts', where: 'code=?', whereArgs: [code]);
    return r.first['id'] as int;
  }

  // --------------------------------------------------------------------
  // أدوات مساعدة عامة
  // --------------------------------------------------------------------
  Future<List<Map<String, Object?>>> q(String sql, [List<Object?> args = const []]) =>
      db.rawQuery(sql, args);
  Future<int> ins(String table, Map<String, Object?> values) => db.insert(table, values);
  Future<int> upd(String table, Map<String, Object?> values, String where, List<Object?> args) =>
      db.update(table, values, where: where, whereArgs: args);

  static String _generateSalt() {
    final r = DateTime.now().microsecondsSinceEpoch.toString();
    return sha1.convert(utf8.encode(r)).toString().substring(0, 16);
  }

  static String _hashPassword(String password, String salt) =>
      sha256.convert(utf8.encode('$salt::$password')).toString();

  static bool verifyPassword(String password, String salt, String hash) =>
      _hashPassword(password, salt) == hash;

  static String hashPassword(String password, String salt) => _hashPassword(password, salt);
  static String newSalt() => _generateSalt();

  // --------------------------------------------------------------------
  // النسخ الاحتياطي / الاستعادة
  // مع حماية من: ملف تالف (JSON غير صالح)، إصدار قاعدة بيانات غير متوافق،
  // وتوقيع (checksum) يتحقق من سلامة الملف قبل أي استعادة فعلية.
  // --------------------------------------------------------------------
  static const _allTables = [
    'settings', 'accounts', 'journals', 'journal_lines', 'parties', 'drivers',
    'trucks', 'routes', 'money_accounts', 'products', 'stock_moves', 'sales',
    'purchases', 'expenses', 'vouchers', 'users', 'role_permissions', 'loads',
    'notifications', 'audit_log', 'sync_queue',
  ];

  Future<String> exportJson() async {
    final out = <String, dynamic>{};
    for (final t in _allTables) {
      out[t] = await db.query(t);
    }
    final payload = {
      'schema_version': kSchemaVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'tables': out,
    };
    final body = jsonEncode(payload['tables']);
    final checksum = sha256.convert(utf8.encode(body)).toString();
    payload['checksum'] = checksum;
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Future<String> backupToFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final backupsDir = Directory(join(dir.path, 'backups'));
    if (!backupsDir.existsSync()) backupsDir.createSync(recursive: true);
    final f = File(join(
        backupsDir.path, 'cement_backup_${DateTime.now().millisecondsSinceEpoch}.json'));
    await f.writeAsString(await exportJson());
    return f.path;
  }

  /// نتيجة التحقق من ملف نسخة احتياطية قبل الاستعادة الفعلية.
  /// [ok]=false تعني أن الملف تالف أو غير متوافق ويجب رفض الاستعادة.
  static ({bool ok, String message, int? schemaVersion}) validateBackup(String jsonStr) {
    Map<String, dynamic> m;
    try {
      m = jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      return (ok: false, message: 'الملف تالف أو ليس بصيغة JSON صحيحة', schemaVersion: null);
    }
    final tables = m['tables'];
    final checksum = m['checksum'];
    final schemaVersion = m['schema_version'];
    if (tables is! Map || checksum is! String || schemaVersion is! int) {
      return (ok: false, message: 'بنية ملف النسخة الاحتياطية غير معروفة', schemaVersion: null);
    }
    final body = jsonEncode(tables);
    final actual = sha256.convert(utf8.encode(body)).toString();
    if (actual != checksum) {
      return (ok: false, message: 'فشل التحقق من سلامة الملف (checksum غير مطابق) — قد يكون الملف تالفًا', schemaVersion: schemaVersion);
    }
    if (schemaVersion > kSchemaVersion) {
      return (
        ok: false,
        message: 'هذه النسخة الاحتياطية من إصدار أحدث ($schemaVersion) من التطبيق الحالي ($kSchemaVersion) — يرجى تحديث التطبيق أولًا',
        schemaVersion: schemaVersion,
      );
    }
    return (ok: true, message: 'الملف صالح', schemaVersion: schemaVersion);
  }

  /// استعادة فعلية — يجب استدعاء [validateBackup] أولًا والتأكد من ok=true.
  Future<void> restoreFromJson(String jsonStr) async {
    final check = validateBackup(jsonStr);
    if (!check.ok) throw Exception(check.message);
    final m = jsonDecode(jsonStr) as Map<String, dynamic>;
    final tables = m['tables'] as Map<String, dynamic>;
    await db.transaction((tx) async {
      // المرحلة 1: حذف كل الجداول بترتيب عكسي (الأبناء أولًا) لتفادي انتهاك
      // قيود Foreign Key أثناء الحذف المؤقت — مثال: money_accounts تشير إلى
      // accounts، فيجب حذف money_accounts قبل accounts وليس بعده.
      for (final t in _allTables.reversed) {
        if (tables[t] == null) continue;
        await tx.delete(t);
      }
      // المرحلة 2: إعادة الإدراج بالترتيب الطبيعي (الآباء قبل الأبناء) بعد
      // أن أصبحت كل الجداول فارغة، فلا تعارض بين مرحلتي الحذف والإدراج.
      for (final t in _allTables) {
        if (tables[t] == null) continue;
        for (final r in (tables[t] as List)) {
          await tx.insert(t, Map<String, Object?>.from(r as Map));
        }
      }
    });
  }
}
