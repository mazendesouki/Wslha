import 'package:flutter/material.dart';
import '../../core/session.dart';
import '../account/account_screen.dart';
import '../settings/settings_screen.dart';
import '../wallet/wallet_screen.dart';
import 'driver_home_screen.dart';
import 'driver_orders_screen.dart';

/// Matches the customer HomeShell's pattern (IndexedStack + bottom nav) —
/// driver-dashboard.astro's own tab bar (رحلات/حساب/سجل) inspired the tab
/// set, reusing the already-built AccountScreen/WalletScreen/SettingsScreen
/// since none of those are customer-specific.
class DriverHomeShell extends StatefulWidget {
  final UserSession session;
  const DriverHomeShell({super.key, required this.session});

  @override
  State<DriverHomeShell> createState() => _DriverHomeShellState();
}

class _DriverHomeShellState extends State<DriverHomeShell> {
  int _index = 0;

  void _goToTab(int i) => setState(() => _index = i);

  late final List<Widget> _tabs = [
    DriverHomeScreen(session: widget.session),
    const WalletScreen(),
    const AccountScreen(),
    const DriverOrdersScreen(),
    SettingsScreen(onNavigateTab: _goToTab),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Text('🚗', style: TextStyle(fontSize: 20)), label: 'الرئيسية'),
          BottomNavigationBarItem(icon: Text('💳', style: TextStyle(fontSize: 20)), label: 'المحفظة'),
          BottomNavigationBarItem(icon: Text('👤', style: TextStyle(fontSize: 20)), label: 'حسابي'),
          BottomNavigationBarItem(icon: Text('📦', style: TextStyle(fontSize: 20)), label: 'الطلبات'),
          BottomNavigationBarItem(icon: Text('⚙️', style: TextStyle(fontSize: 20)), label: 'الإعدادات'),
        ],
      ),
    );
  }
}
