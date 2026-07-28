import 'package:flutter/material.dart';
import '../../core/session.dart';
import '../../shared/widgets/placeholder_screen.dart';
import '../rides/rides_screen.dart';
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

  late final List<Widget> _tabs = [
    HomeTab(session: widget.session),
    const WalletScreen(),
    const PlaceholderScreen(title: 'حسابي', emoji: '👤'),
    const PlaceholderScreen(title: 'الطلبات', emoji: '📦'),
    const RidesScreen(),
    const PlaceholderScreen(title: 'الإعدادات', emoji: '⚙️'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
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
