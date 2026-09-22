-- ============================================================
-- مخطط قاعدة البيانات النهائي (V3) — مُستخرج آليًا من lib/core/db.dart
-- هذا الملف مرجعي للتوثيق فقط؛ المصدر الفعلي المُنفَّذ وقت التشغيل
-- هو الكود في lib/core/db.dart (بما يضمن عدم انحراف الوثيقة عن الكود).
-- ============================================================

CREATE TABLE IF NOT EXISTS settings(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            key TEXT UNIQUE NOT NULL,
            value TEXT NOT NULL);

CREATE TABLE IF NOT EXISTS accounts(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            code TEXT UNIQUE NOT NULL,
            name TEXT NOT NULL,
            type TEXT NOT NULL CHECK(type IN ('asset','liability','equity','revenue','expense')),
            parent_id INTEGER,
            is_system INTEGER DEFAULT 0,
            active INTEGER DEFAULT 1,
            created TEXT NOT NULL);

CREATE TABLE IF NOT EXISTS journals(
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
            created TEXT NOT NULL);

CREATE TABLE IF NOT EXISTS journal_lines(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            journal_id INTEGER NOT NULL REFERENCES journals(id),
            account_id INTEGER NOT NULL REFERENCES accounts(id),
            debit REAL DEFAULT 0,
            credit REAL DEFAULT 0,
            description TEXT);

CREATE TABLE IF NOT EXISTS parties(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL CHECK(type IN ('factory','trader','customer','supplier')),
            name TEXT NOT NULL,
            phone TEXT,
            address TEXT,
            account_id INTEGER REFERENCES accounts(id),
            opening REAL DEFAULT 0,
            active INTEGER DEFAULT 1,
            note TEXT,
            created TEXT NOT NULL);

CREATE TABLE IF NOT EXISTS drivers(
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
            created TEXT NOT NULL);

CREATE TABLE IF NOT EXISTS trucks(
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
            created TEXT NOT NULL);

CREATE TABLE IF NOT EXISTS routes(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            default_transport_rate REAL DEFAULT 0,
            active INTEGER DEFAULT 1,
            note TEXT,
            created TEXT NOT NULL);

CREATE TABLE IF NOT EXISTS money_accounts(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            kind TEXT NOT NULL CHECK(kind IN ('cash','bank','exchanger')),
            name TEXT NOT NULL,
            account_id INTEGER REFERENCES accounts(id),
            currency TEXT DEFAULT 'YER',
            phone TEXT,
            active INTEGER DEFAULT 1,
            note TEXT,
            created TEXT NOT NULL);

CREATE TABLE IF NOT EXISTS products(
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
            created TEXT NOT NULL);

CREATE TABLE IF NOT EXISTS stock_moves(
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
            created TEXT NOT NULL);

CREATE TABLE IF NOT EXISTS sales(
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
            created TEXT NOT NULL);

CREATE TABLE IF NOT EXISTS purchases(
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
            created TEXT NOT NULL);

CREATE TABLE IF NOT EXISTS expenses(
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
            created TEXT NOT NULL);

CREATE TABLE IF NOT EXISTS vouchers(
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
            created TEXT NOT NULL);

CREATE TABLE IF NOT EXISTS users(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,
            password_salt TEXT NOT NULL,
            full_name TEXT,
            role TEXT NOT NULL,
            active INTEGER DEFAULT 1,
            last_login TEXT,
            created TEXT NOT NULL);

CREATE TABLE IF NOT EXISTS role_permissions(
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
            UNIQUE(role, module));

CREATE TABLE IF NOT EXISTS loads(
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
            created TEXT NOT NULL);

CREATE TABLE IF NOT EXISTS notifications(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            load_id INTEGER REFERENCES loads(id),
            channel TEXT NOT NULL CHECK(channel IN ('whatsapp','sms')),
            recipient_phone TEXT,
            message TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','sent','failed')),
            error TEXT,
            created TEXT NOT NULL,
            updated TEXT NOT NULL);

CREATE TABLE IF NOT EXISTS audit_log(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER,
            username TEXT,
            action TEXT NOT NULL,
            entity TEXT NOT NULL,
            entity_id INTEGER,
            before_json TEXT,
            after_json TEXT,
            created TEXT NOT NULL);

CREATE TABLE IF NOT EXISTS sync_queue(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            entity TEXT NOT NULL,
            entity_id INTEGER NOT NULL,
            action TEXT NOT NULL,
            payload TEXT NOT NULL,
            created TEXT NOT NULL,
            synced INTEGER DEFAULT 0);

CREATE UNIQUE INDEX IF NOT EXISTS idx_loads_opno ON loads(operation_no);

CREATE INDEX IF NOT EXISTS idx_journal_lines_account ON journal_lines(account_id);

CREATE INDEX IF NOT EXISTS idx_loads_status ON loads(status);

