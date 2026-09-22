import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/reports.dart';
import '../core/db.dart';

final money = NumberFormat('#,##0.##', 'en');

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<_DashboardData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DashboardData> _load() async {
    final balances = await Reports.dashboardBalances();
    final stock = await Reports.stock();
    final monthlyLoads = await Reports.monthlyLoads(DateTime.now().year, DateTime.now().month);
    final monthlySalesRow = await AppDb.instance
        .q("SELECT COALESCE(SUM(total),0) v FROM sales WHERE status='posted' AND strftime('%Y-%m',date)=strftime('%Y-%m','now')");
    final purchasesRow = await AppDb.instance
        .q("SELECT COALESCE(SUM(total),0) v FROM purchases WHERE status='posted' AND strftime('%Y-%m',date)=strftime('%Y-%m','now')");
    final expensesRow = await AppDb.instance
        .q("SELECT COALESCE(SUM(amount),0) v FROM expenses WHERE status='posted' AND strftime('%Y-%m',date)=strftime('%Y-%m','now')");
    final pnl = await Reports.profitAndLoss();
    return _DashboardData(
      balances: balances,
      stockBags: stock.fold<double>(0, (s, p) => s + (p['stock_bags'] as num).toDouble()),
      monthlyLoadBags: monthlyLoads.fold<double>(0, (s, l) => s + (l['bags'] as num).toDouble()),
      monthlySales: (monthlySalesRow.first['v'] as num).toDouble(),
      monthlyPurchases: (purchasesRow.first['v'] as num).toDouble(),
      monthlyExpenses: (expensesRow.first['v'] as num).toDouble(),
      profit: pnl.net,
    );
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<_DashboardData>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final d = snap.data!;
          final cards = <_Kpi>[
            _Kpi('النقدية', d.balances['cash'] ?? 0, Icons.payments),
            _Kpi('البنوك', d.balances['banks'] ?? 0, Icons.account_balance),
            _Kpi('الصرافين', d.balances['exchangers'] ?? 0, Icons.currency_exchange),
            _Kpi('أرصدة العملاء (ذمم)', d.balances['receivables'] ?? 0, Icons.people),
            _Kpi('المخزون (أكياس)', d.stockBags, Icons.inventory),
            _Kpi('المبيعات اليوم', d.balances['sales_today'] ?? 0, Icons.point_of_sale),
            _Kpi('المبيعات الشهرية', d.monthlySales, Icons.trending_up),
            _Kpi('المشتريات الشهرية', d.monthlyPurchases, Icons.shopping_cart),
            _Kpi('المصروفات الشهرية', d.monthlyExpenses, Icons.money_off),
            _Kpi('الأرباح (تقديري)', d.profit, Icons.savings),
            _Kpi('الحمولة اليوم (أكياس)', d.balances['loads_today_bags'] ?? 0, Icons.local_shipping),
            _Kpi('الحمولة الشهرية (أكياس)', d.monthlyLoadBags, Icons.local_shipping_outlined),
          ];
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const Text('مؤسسة الغولي لتجارة وتسويق الأسمنت',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                childAspectRatio: 1.5,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                children: cards.map((c) => _KpiCard(c)).toList(),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DashboardData {
  final Map<String, double> balances;
  final double stockBags, monthlyLoadBags, monthlySales, monthlyPurchases, monthlyExpenses, profit;
  _DashboardData({
    required this.balances,
    required this.stockBags,
    required this.monthlyLoadBags,
    required this.monthlySales,
    required this.monthlyPurchases,
    required this.monthlyExpenses,
    required this.profit,
  });
}

class _Kpi {
  final String label;
  final double value;
  final IconData icon;
  _Kpi(this.label, this.value, this.icon);
}

class _KpiCard extends StatelessWidget {
  final _Kpi kpi;
  const _KpiCard(this.kpi);
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(kpi.icon, color: Theme.of(context).colorScheme.primary),
            const Spacer(),
            Text(kpi.label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            Text(money.format(kpi.value), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
