import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/session.dart';
import '../../core/theme.dart';

/// Mirrors settings.astro: links to Profile/Wallet/Orders, a local
/// notifications toggle (localStorage['wslha_notif'] there → shared_prefs
/// here), and logout. No password/account-deletion on either side — auth
/// is phone-only, no password field exists anywhere in this app.
class SettingsScreen extends StatefulWidget {
  final void Function(int tabIndex)? onNavigateTab;
  const SettingsScreen({super.key, this.onNavigateTab});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _notifKey = 'wslha_notif';
  UserSession? _session;
  bool _notifEnabled = true;
  String? _versionLabel;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = await SessionStore.load();
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _session = session;
      _notifEnabled = prefs.getBool(_notifKey) ?? true;
    });
    // Was a hardcoded "1.0.0" string that never once matched the real
    // installed build across this whole session's version bumps — read the
    // actual version+build straight from the installed package instead, so
    // this label never goes stale again.
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _versionLabel = '${info.version}+${info.buildNumber}');
  }

  Future<void> _toggleNotif(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notifKey, value);
    setState(() => _notifEnabled = value);
  }

  Future<void> _logout() async {
    await SessionStore.clear();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        children: [
          if (_session != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Row(
                children: [
                  const CircleAvatar(radius: 22, backgroundColor: AppColors.primaryLight, child: Text('👤')),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_session!.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                      Text(_session!.phone, style: const TextStyle(fontSize: 12, color: AppColors.textFaint), textDirection: TextDirection.ltr),
                    ],
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          _SettingsTile(
            icon: '👤',
            title: 'حسابي',
            onTap: () => widget.onNavigateTab?.call(2),
          ),
          _SettingsTile(
            icon: '💳',
            title: 'المحفظة',
            onTap: () => widget.onNavigateTab?.call(1),
          ),
          _SettingsTile(
            icon: '📦',
            title: 'طلباتي ومشاويري',
            onTap: () => widget.onNavigateTab?.call(3),
          ),
          const Divider(height: 24),
          SwitchListTile(
            secondary: const Text('🔔', style: TextStyle(fontSize: 20)),
            title: const Text('الإشعارات'),
            value: _notifEnabled,
            activeThumbColor: AppColors.primary,
            onChanged: _toggleNotif,
          ),
          const ListTile(
            leading: Text('🌐', style: TextStyle(fontSize: 20)),
            title: Text('اللغة'),
            trailing: Text('العربية', style: TextStyle(color: AppColors.textFaint)),
          ),
          const Divider(height: 24),
          if (_session != null)
            ListTile(
              leading: const Icon(Icons.logout, color: AppColors.error),
              title: const Text('تسجيل الخروج', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700)),
              onTap: _logout,
            ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'وصّلها — الإصدار ${_versionLabel ?? '...'}',
              style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final String icon;
  final String title;
  final VoidCallback? onTap;
  const _SettingsTile({required this.icon, required this.title, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Text(icon, style: const TextStyle(fontSize: 20)),
      title: Text(title),
      trailing: const Icon(Icons.chevron_left),
      onTap: onTap,
    );
  }
}
