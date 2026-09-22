import 'package:flutter/material.dart';
import 'core/permissions.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/load_screen.dart';
import 'screens/parties_screen.dart';
import 'screens/transactions_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/settings_screen.dart';

class CementApp extends StatefulWidget {
  const CementApp({super.key});
  @override
  State<CementApp> createState() => _CementAppState();
}

class _CementAppState extends State<CementApp> {
  ThemeMode _mode = ThemeMode.system;

  void setThemeMode(ThemeMode m) => setState(() => _mode = m);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'مؤسسة الغولي لتجارة وتسويق الأسمنت',
      themeMode: _mode,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF8D6E37), // بني أسمنتي دافئ يعكس هوية النشاط
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF8D6E37),
        brightness: Brightness.dark,
      ),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      home: const _RootGate(),
      builder: (context, widget) => Directionality(textDirection: TextDirection.rtl, child: widget!),
    );
  }
}

class _RootGate extends StatefulWidget {
  const _RootGate();
  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  bool _loggedIn = false;

  @override
  Widget build(BuildContext context) {
    if (!_loggedIn || !Session.instance.isLoggedIn) {
      return LoginScreen(onLoggedIn: () => setState(() => _loggedIn = true));
    }
    return const HomeShell();
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _titles = ['الرئيسية', 'الحمولة', 'العمليات المالية', 'الأطراف', 'التقارير', 'الإعدادات'];

  static const _pages = [
    DashboardScreen(),
    LoadListScreen(),
    OperationsHubScreen(),
    PartiesHubScreen(),
    ReportsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final user = Session.instance.user;
    return Scaffold(
      appBar: _index == 0
          ? AppBar(
              title: Text(_titles[_index]),
              actions: [
                PopupMenuButton<String>(
                  icon: const CircleAvatar(child: Icon(Icons.person)),
                  onSelected: (v) {
                    if (v == 'logout') {
                      Session.instance.logout();
                      setState(() {});
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const _RootGate()),
                        (route) => false,
                      );
                    }
                  },
                  itemBuilder: (c) => [
                    PopupMenuItem(enabled: false, child: Text('${user?.fullName} (${user?.role})')),
                    const PopupMenuDivider(),
                    const PopupMenuItem(value: 'logout', child: Text('تسجيل الخروج')),
                  ],
                ),
              ],
            )
          : null,
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'الرئيسية'),
          NavigationDestination(icon: Icon(Icons.local_shipping), label: 'الحمولة'),
          NavigationDestination(icon: Icon(Icons.swap_horiz), label: 'المالية'),
          NavigationDestination(icon: Icon(Icons.groups), label: 'الأطراف'),
          NavigationDestination(icon: Icon(Icons.assessment), label: 'التقارير'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'الإعدادات'),
        ],
      ),
    );
  }
}
