import 'package:flutter/material.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../account/account_screen.dart';
import '../settings/settings_screen.dart';
import '../wallet/wallet_screen.dart';
import 'driver_home_screen.dart';
import 'driver_orders_screen.dart';
import 'driver_repository.dart';

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
  final _repo = DriverRepository();
  bool _loadingStatus = true;
  String? _status;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final status = await _repo.fetchApprovalStatus(widget.session.phone);
    if (!mounted) return;
    setState(() {
      _status = status;
      _loadingStatus = false;
    });
  }

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
    if (_loadingStatus) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // The real enforcement is server-side (accept_dispatch_offer rejects
    // any accept from a non-approved driver regardless) — this is just so
    // an unapproved driver sees a clear reason instead of a normal-looking
    // app where every "قبول" silently fails.
    if (_status != 'approved') {
      return _PendingApprovalScreen(status: _status, onRefresh: () {
        setState(() => _loadingStatus = true);
        _loadStatus();
      });
    }
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

class _PendingApprovalScreen extends StatelessWidget {
  final String? status; // null (no application yet) | 'pending' | 'rejected'
  final VoidCallback onRefresh;
  const _PendingApprovalScreen({required this.status, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final rejected = status == 'rejected';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(rejected ? '❌' : '⏳', style: const TextStyle(fontSize: 48)),
                const SizedBox(height: 16),
                Text(
                  rejected ? 'تم رفض طلب انضمامك' : 'حسابك قيد المراجعة',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  rejected
                      ? 'تواصل مع الدعم لمعرفة السبب أو لإعادة التقديم.'
                      : 'لسه ما اتراجعش طلبك من الإدارة — مش هتقدر تستقبل رحلات لحد ما يتم الاعتماد.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textFaint),
                ),
                const SizedBox(height: 24),
                ElevatedButton(onPressed: onRefresh, child: const Text('🔄 تحديث الحالة')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
