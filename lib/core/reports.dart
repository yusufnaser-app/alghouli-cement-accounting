// ============================================================================
// طبقة التقارير — استعلامات مجمّعة تغذّي شاشات التقارير وقوالب PDF
// ============================================================================

import '../core/db.dart';
import '../accounting/accounting_engine.dart';

class Reports {
  static Future<List<Map<String, Object?>>> dailyLoads(DateTime day) async {
    final from = DateTime(day.year, day.month, day.day).toIso8601String();
    final to = DateTime(day.year, day.month, day.day, 23, 59, 59).toIso8601String();
    return AppDb.instance.q('''
      SELECT l.*, f.name AS factory_name, d.name AS driver_name, t.plate AS truck_plate,
             p.name AS product_name, tr.name AS trader_name
      FROM loads l
      JOIN parties f ON f.id = l.factory_id
      JOIN drivers d ON d.id = l.driver_id
      JOIN trucks t ON t.id = l.truck_id
      JOIN products p ON p.id = l.product_id
      LEFT JOIN parties tr ON tr.id = l.trader_id
      WHERE l.datetime BETWEEN ? AND ? AND l.status='posted'
      ORDER BY l.datetime DESC
    ''', [from, to]);
  }

  static Future<List<Map<String, Object?>>> monthlyLoads(int year, int month) async {
    final from = DateTime(year, month, 1).toIso8601String();
    final to = DateTime(year, month + 1, 1).subtract(const Duration(seconds: 1)).toIso8601String();
    return AppDb.instance.q('''
      SELECT l.*, f.name AS factory_name, d.name AS driver_name, t.plate AS truck_plate
      FROM loads l
      JOIN parties f ON f.id = l.factory_id
      JOIN drivers d ON d.id = l.driver_id
      JOIN trucks t ON t.id = l.truck_id
      WHERE l.datetime BETWEEN ? AND ? AND l.status='posted'
      ORDER BY l.datetime DESC
    ''', [from, to]);
  }

  static Future<List<Map<String, Object?>>> loadsByDriver(int driverId) => AppDb.instance.q('''
      SELECT l.* FROM loads l WHERE l.driver_id=? AND l.status='posted' ORDER BY l.datetime DESC
  ''', [driverId]);

  static Future<List<Map<String, Object?>>> loadsByTruck(int truckId) => AppDb.instance.q('''
      SELECT l.* FROM loads l WHERE l.truck_id=? AND l.status='posted' ORDER BY l.datetime DESC
  ''', [truckId]);

  static Future<List<Map<String, Object?>>> loadsByFactory(int factoryId) => AppDb.instance.q('''
      SELECT l.* FROM loads l WHERE l.factory_id=? AND l.status='posted' ORDER BY l.datetime DESC
  ''', [factoryId]);

  static Future<double> totalTransportInPeriod(String from, String to) async {
    final r = await AppDb.instance.q('''
      SELECT COALESCE(SUM(transport_total),0) v FROM loads WHERE datetime BETWEEN ? AND ? AND status='posted'
    ''', [from, to]);
    return (r.first['v'] as num).toDouble();
  }

  static Future<double> totalCommissionInPeriod(String from, String to) async {
    final r = await AppDb.instance.q('''
      SELECT COALESCE(SUM(net_commission),0) v FROM loads WHERE datetime BETWEEN ? AND ? AND status='posted'
    ''', [from, to]);
    return (r.first['v'] as num).toDouble();
  }

  static Future<List<Map<String, Object?>>> stock() => AppDb.instance.q('SELECT * FROM products WHERE active=1');

  static Future<List<Map<String, Object?>>> salesReport({String? from, String? to}) async {
    final where = StringBuffer("status='posted'");
    final args = <Object?>[];
    if (from != null) {
      where.write(' AND date>=?');
      args.add(from);
    }
    if (to != null) {
      where.write(' AND date<=?');
      args.add(to);
    }
    return AppDb.instance.q('SELECT * FROM sales WHERE $where ORDER BY date DESC', args);
  }

  static Future<List<Map<String, Object?>>> purchasesReport({String? from, String? to}) async {
    final where = StringBuffer("status='posted'");
    final args = <Object?>[];
    if (from != null) {
      where.write(' AND date>=?');
      args.add(from);
    }
    if (to != null) {
      where.write(' AND date<=?');
      args.add(to);
    }
    return AppDb.instance.q('SELECT * FROM purchases WHERE $where ORDER BY date DESC', args);
  }

  static Future<List<Map<String, Object?>>> expensesReport({String? from, String? to}) async {
    final where = StringBuffer("status='posted'");
    final args = <Object?>[];
    if (from != null) {
      where.write(' AND date>=?');
      args.add(from);
    }
    if (to != null) {
      where.write(' AND date<=?');
      args.add(to);
    }
    return AppDb.instance.q('SELECT * FROM expenses WHERE $where ORDER BY date DESC', args);
  }

  /// الأرباح والخسائر: مبسّطة اعتمادًا على حسابات المبيعات/تكلفة/المصروفات
  /// في دليل الحسابات (4000 مبيعات، 5000 تكلفة، بقية 5xxx مصروفات).
  static Future<({double revenue, double cogs, double expenses, double net})> profitAndLoss({
    String? from,
    String? to,
  }) async {
    final tb = await AccountingEngine.trialBalance();
    double revenue = 0, cogs = 0, expenses = 0;
    for (final r in tb) {
      final type = r['type'] as String;
      final credit = (r['credit'] as num).toDouble();
      final debit = (r['debit'] as num).toDouble();
      if (type == 'revenue') revenue += (credit - debit);
      if (type == 'expense') {
        final code = r['code'] as String;
        if (code.startsWith('5000')) {
          cogs += (debit - credit);
        } else {
          expenses += (debit - credit);
        }
      }
    }
    final net = revenue - cogs - expenses;
    return (revenue: revenue, cogs: cogs, expenses: expenses, net: net);
  }

  static Future<Map<String, double>> dashboardBalances() async {
    final cash = await AppDb.instance.q('''
      SELECT COALESCE(SUM(a.debit-a.credit),0) v FROM (
        SELECT account_id, SUM(debit) debit, SUM(credit) credit FROM journal_lines
        JOIN accounts ON accounts.id = journal_lines.account_id WHERE accounts.code='1000' GROUP BY account_id
      ) a
    ''');
    final banks = await AppDb.instance.q('''
      SELECT COALESCE(SUM(l.debit-l.credit),0) v FROM journal_lines l
      JOIN accounts a ON a.id=l.account_id WHERE a.code='1100'
    ''');
    final exch = await AppDb.instance.q('''
      SELECT COALESCE(SUM(l.debit-l.credit),0) v FROM journal_lines l
      JOIN accounts a ON a.id=l.account_id WHERE a.code='1200'
    ''');
    final receivables = await AppDb.instance.q('''
      SELECT COALESCE(SUM(l.debit-l.credit),0) v FROM journal_lines l
      JOIN accounts a ON a.id=l.account_id WHERE a.code LIKE '1300%'
    ''');
    final salesToday = await AppDb.instance.q('''
      SELECT COALESCE(SUM(total),0) v FROM sales WHERE date(date)=date('now') AND status='posted'
    ''');
    final loadsToday = await AppDb.instance.q('''
      SELECT COALESCE(SUM(bags),0) v FROM loads WHERE date(datetime)=date('now') AND status='posted'
    ''');
    double v(List<Map<String, Object?>> r) => (r.first['v'] as num).toDouble();
    return {
      'cash': v(cash),
      'banks': v(banks),
      'exchangers': v(exch),
      'receivables': v(receivables),
      'sales_today': v(salesToday),
      'loads_today_bags': v(loadsToday),
    };
  }
}
