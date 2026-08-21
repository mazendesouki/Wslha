import 'package:flutter/material.dart';
import '../../core/session.dart';
import '../account/account_screen.dart';
import '../orders/orders_screen.dart';
import '../rides/rides_screen.dart';
import '../settings/settings_screen.dart';
import '../wallet/wallet_screen.dart';
import 'home_tab.dart';

/// Mirrors BottomNav.astro's 6 tabs and order:
/// 🏠 الرئيسية · 💳 المحفظة · 👤 حسابي · 📦 الطلبات · 🚖 رحلات · ⚙️ الإعدادات
class HomeShell extends StatefulWidget {
  final UserSession session;
  const HomeShell({super.key, required this.session});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final _accountKey = GlobalKey<AccountScreenState>();

  void _goToTab(int i) {
    setState(() => _index = i);
    // AccountScreen lives inside the IndexedStack below, so switching back to
    // it doesn't re-run initState() — refresh its stats/addresses/reviews
    // explicitly whenever the customer taps "حسابي", e.g. right after a ride
    // or order just finished elsewhere in the app.
    if (i == 2) _accountKey.currentState?.refresh();
  }

  late final List<Widget> _tabs = [
    HomeTab(session: widget.session),
    const WalletScreen(),
    AccountScreen(key: _accountKey),
    const OrdersScreen(),
    const RidesScreen(),
    SettingsScreen(onNavigateTab: _goToTab),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: _goToTab,
        items: const [
          BottomNavigationBarItem(icon: Text('🏠', style: TextStyle(fontSize: 20)), label: 'الرئيسية'),
          BottomNavigationBarItem(icon: Text('💳', style: TextStyle(fontSize: 20)), label: 'المحفظة'),
          BottomNavigationBarItem(icon: Text('👤', style: TextStyle(fontSize: 20)), label: 'حسابي'),
          BottomNavigationBarItem(icon: Text('📦', style: TextStyle(fontSize: 20)), label: 'الطلبات'),
          BottomNavigationBarItem(icon: Text('🚖', style: TextStyle(fontSize: 20)), label: 'رحلات'),
          BottomNavigationBarItem(icon: Text('⚙️', style: TextStyle(fontSize: 20)), label: 'الإعدادات'),
        ],
      ),
    );
  }
}
