import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/feature_flags.dart';
import '../../core/flavor.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/update_checker.dart';
import '../notifications/notifications_screen.dart';
import '../safety/emergency_contacts_screen.dart';
import '../support/support_screen.dart';

/// Mirrors settings.astro: links to Profile/Wallet/Orders, a local
/// notifications toggle (localStorage['wslha_notif'] there → shared_prefs
/// here), and logout. No password/account-deletion on either side — auth
/// is phone-only, no password field exists anywhere in this app.
class SettingsScreen extends StatefulWidget {
  final void Function(int tabIndex)? onNavigateTab;
  final AppFlavor flavor;
  const SettingsScreen({super.key, this.onNavigateTab, required this.flavor});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _notifKey = 'wslha_notif';
  UserSession? _session;
  bool _notifEnabled = true;
  String? _versionLabel;
  UpdateInfo? _updateInfo;

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

    final update = await UpdateChecker().checkForUpdate(widget.flavor);
    if (!mounted) return;
    setState(() => _updateInfo = update);
  }

  Future<void> _openUpdateLink() async {
    final url = _updateInfo?.apkUrl;
    if (url == null) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
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
      appBar: AppBar(title: Text(context.tr('settings_title'))),
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
          if (_updateInfo != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: Row(
                  children: [
                    const Text('🎉', style: TextStyle(fontSize: 24)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(context.tr('settings_new_version_title'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                          Text(context.tr('settings_new_version_body').replaceAll('VERSION', _updateInfo!.versionName), style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _openUpdateLink,
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
                      child: Text(context.tr('settings_update_now')),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          _SettingsTile(
            icon: '👤',
            title: context.tr('settings_tile_account'),
            onTap: () => widget.onNavigateTab?.call(2),
          ),
          _SettingsTile(
            icon: '💳',
            title: context.tr('settings_tile_wallet'),
            onTap: () => widget.onNavigateTab?.call(1),
          ),
          _SettingsTile(
            icon: '📦',
            title: context.tr('settings_tile_orders'),
            onTap: () => widget.onNavigateTab?.call(3),
          ),
          if (FeatureFlags.sosEnabled)
            _SettingsTile(
              icon: '🆘',
              title: context.tr('settings_emergency_contacts'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EmergencyContactsScreen())),
            ),
          const Divider(height: 24),
          SwitchListTile(
            secondary: const Text('🔔', style: TextStyle(fontSize: 20)),
            title: Text(context.tr('settings_notifications')),
            value: _notifEnabled,
            activeThumbColor: AppColors.primary,
            onChanged: _toggleNotif,
          ),
          if (FeatureFlags.darkModeEnabled)
            ValueListenableBuilder<ThemeMode>(
              valueListenable: ThemeController.mode,
              builder: (context, mode, _) => ListTile(
                leading: const Text('🌙', style: TextStyle(fontSize: 20)),
                title: Text(context.tr('settings_dark_mode')),
                trailing: DropdownButton<ThemeMode>(
                  value: mode,
                  underline: const SizedBox.shrink(),
                  items: [
                    DropdownMenuItem(value: ThemeMode.system, child: Text(context.tr('settings_dark_mode_system'))),
                    DropdownMenuItem(value: ThemeMode.light, child: Text(context.tr('settings_dark_mode_light'))),
                    DropdownMenuItem(value: ThemeMode.dark, child: Text(context.tr('settings_dark_mode_dark'))),
                  ],
                  onChanged: (v) {
                    if (v != null) ThemeController.set(v);
                  },
                ),
              ),
            ),
          _SettingsTile(
            icon: '🗂️',
            title: context.tr('settings_notifications_log'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
          ),
          if (FeatureFlags.languageSwitchEnabled)
            ValueListenableBuilder<Locale>(
              valueListenable: LocaleController.locale,
              builder: (context, locale, _) => ListTile(
                leading: const Text('🌐', style: TextStyle(fontSize: 20)),
                title: Text(context.tr('settings_language')),
                trailing: DropdownButton<Locale>(
                  value: locale,
                  underline: const SizedBox.shrink(),
                  items: [
                    DropdownMenuItem(value: const Locale('ar'), child: Text(context.tr('settings_language_ar'))),
                    DropdownMenuItem(value: const Locale('en'), child: Text(context.tr('settings_language_en'))),
                  ],
                  onChanged: (v) {
                    if (v != null) LocaleController.set(v);
                  },
                ),
              ),
            ),
          _SettingsTile(
            icon: '🛟',
            title: context.tr('settings_support'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SupportScreen())),
          ),
          const Divider(height: 24),
          if (_session != null)
            ListTile(
              leading: const Icon(Icons.logout, color: AppColors.error),
              title: Text(context.tr('settings_logout'), style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w700)),
              onTap: _logout,
            ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              context.tr('settings_app_version_label').replaceAll('VERSION', _versionLabel ?? '...'),
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
