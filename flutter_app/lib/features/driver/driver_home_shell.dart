import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../settings/settings_screen.dart';
import '../wallet/wallet_screen.dart';
import 'driver_home_screen.dart';
import 'driver_orders_screen.dart';
import 'driver_profile_screen.dart';
import 'driver_repository.dart';

/// Matches the customer HomeShell's pattern (IndexedStack + bottom nav) —
/// driver-dashboard.astro's own tab bar (رحلات/حساب/سجل) inspired the tab
/// set. The حسابي tab uses DriverProfileScreen (driver-specific, with
/// ratings/level/vehicle info) instead of the generic AccountScreen that
/// customer/merchant still use; WalletScreen/SettingsScreen stay shared.
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

  static const _statusCacheKey = 'wslha_driver_status_cache';

  Future<void> _loadStatus() async {
    // An already-approved driver's status essentially never changes, so
    // making them stare at a blank spinner on every single cold start —
    // purely waiting on a network round-trip to re-confirm something
    // already known — reads as the app "freezing" for a few seconds.
    // Show the last-known status immediately, then quietly re-verify.
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_statusCacheKey);
    if (cached != null && mounted) {
      setState(() {
        _status = cached;
        _loadingStatus = false;
      });
    }
    try {
      final status = await _repo.fetchApprovalStatus(widget.session.phone);
      if (!mounted) return;
      if (status != null) {
        await prefs.setString(_statusCacheKey, status);
      } else {
        await prefs.remove(_statusCacheKey);
      }
      setState(() {
        _status = status;
        _loadingStatus = false;
      });
    } catch (_) {
      // A flaky connection on cold start used to leave this screen spinning
      // forever (setState never ran) — fall back to whatever's already
      // known (cached status, or null on a genuine first launch) instead.
      if (mounted) setState(() => _loadingStatus = false);
    }
  }

  void _goToTab(int i) => setState(() => _index = i);

  late final List<Widget> _tabs = [
    DriverHomeScreen(session: widget.session),
    const WalletScreen(),
    DriverProfileScreen(session: widget.session),
    DriverOrdersScreen(onNavigateTab: _goToTab),
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
