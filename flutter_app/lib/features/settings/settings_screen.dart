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
import '../../shared/widgets/branded_header.dart';
import '../notifications/notifications_screen.dart';
import '../safety/emergency_contacts_screen.dart';
import '../support/support_screen.dart';
import 'app_review_repository.dart';

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
  // "الإشعارات الأذكى" — نفس المفاتيح بالظبط المستخدمة في
  // core/notifications.dart's AppNotifications._enabled().
  static const _ordersKey = 'wslha_notif_orders';
  static const _ridesKey = 'wslha_notif_rides';
  static const _quietEnabledKey = 'wslha_quiet_enabled';
  static const _quietStartKey = 'wslha_quiet_start';
  static const _quietEndKey = 'wslha_quiet_end';
  final _reviewRepo = AppReviewRepository();
  UserSession? _session;
  bool _notifEnabled = true;
  bool _ordersNotifEnabled = true;
  bool _ridesNotifEnabled = true;
  bool _quietEnabled = false;
  TimeOfDay _quietStart = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _quietEnd = const TimeOfDay(hour: 8, minute: 0);
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
      _ordersNotifEnabled = prefs.getBool(_ordersKey) ?? true;
      _ridesNotifEnabled = prefs.getBool(_ridesKey) ?? true;
      _quietEnabled = prefs.getBool(_quietEnabledKey) ?? false;
      _quietStart = _parseTimeOfDay(prefs.getString(_quietStartKey)) ?? _quietStart;
      _quietEnd = _parseTimeOfDay(prefs.getString(_quietEndKey)) ?? _quietEnd;
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

  Future<void> _toggleOrdersNotif(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_ordersKey, value);
    setState(() => _ordersNotifEnabled = value);
  }

  Future<void> _toggleRidesNotif(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_ridesKey, value);
    setState(() => _ridesNotifEnabled = value);
  }

  Future<void> _toggleQuiet(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_quietEnabledKey, value);
    setState(() => _quietEnabled = value);
  }

  TimeOfDay? _parseTimeOfDay(String? raw) {
    if (raw == null) return null;
    final parts = raw.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  String _formatTimeOfDay(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickQuietStart() async {
    final picked = await showTimePicker(context: context, initialTime: _quietStart);
    if (picked == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_quietStartKey, _formatTimeOfDay(picked));
    setState(() => _quietStart = picked);
  }

  Future<void> _pickQuietEnd() async {
    final picked = await showTimePicker(context: context, initialTime: _quietEnd);
    if (picked == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_quietEndKey, _formatTimeOfDay(picked));
    setState(() => _quietEnd = picked);
  }

  Future<void> _logout() async {
    await SessionStore.clear();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
  }

  Future<void> _openRateAppSheet() async {
    final session = _session;
    if (session == null) return;
    int rating = 5;
    final commentController = TextEditingController();
    bool busy = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(top: false, child: Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: StatefulBuilder(
          builder: (ctx, setSheetState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(context.tr('rate_app_sheet_title'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(context.tr('rate_app_sheet_subtitle'), style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final star = i + 1;
                  return IconButton(
                    iconSize: 32,
                    onPressed: () => setSheetState(() => rating = star),
                    icon: Icon(star <= rating ? Icons.star : Icons.star_border, color: AppColors.accent),
                  );
                }),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: commentController,
                maxLines: 3,
                decoration: InputDecoration(labelText: context.tr('rate_app_comment_label')),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: busy
                    ? null
                    : () async {
                        setSheetState(() => busy = true);
                        try {
                          await _reviewRepo.submit(session.phone, session.name, rating, commentController.text.trim());
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(context.tr('rate_app_success')), backgroundColor: AppColors.success),
                            );
                          }
                        } catch (e) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text('${context.tr('rate_app_failed_prefix')} $e'), backgroundColor: AppColors.error, duration: const Duration(seconds: 6)),
                            );
                            setSheetState(() => busy = false);
                          }
                        }
                      },
                child: busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(context.tr('rate_app_submit')),
              ),
            ],
          ),
        ),
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.mutedSurface,
      body: SafeArea(
        child: Column(
          children: [
            BrandedHeader(title: context.tr('settings_title')),
            Expanded(
              child: ListView(
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
          if (_notifEnabled) ...[
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 16),
              child: SwitchListTile(
                dense: true,
                secondary: const Text('📦', style: TextStyle(fontSize: 16)),
                title: Text(context.tr('settings_notif_orders'), style: const TextStyle(fontSize: 13)),
                value: _ordersNotifEnabled,
                activeThumbColor: AppColors.primary,
                onChanged: _toggleOrdersNotif,
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 16),
              child: SwitchListTile(
                dense: true,
                secondary: const Text('🚗', style: TextStyle(fontSize: 16)),
                title: Text(context.tr('settings_notif_rides'), style: const TextStyle(fontSize: 13)),
                value: _ridesNotifEnabled,
                activeThumbColor: AppColors.primary,
                onChanged: _toggleRidesNotif,
              ),
            ),
            SwitchListTile(
              secondary: const Text('🌙', style: TextStyle(fontSize: 20)),
              title: Text(context.tr('settings_quiet_hours')),
              subtitle: Text(context.tr('settings_quiet_hours_subtitle'), style: const TextStyle(fontSize: 11)),
              value: _quietEnabled,
              activeThumbColor: AppColors.primary,
              onChanged: _toggleQuiet,
            ),
            if (_quietEnabled)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 16, bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _pickQuietStart,
                        child: Text('${context.tr('settings_quiet_from')} ${_formatTimeOfDay(_quietStart)}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _pickQuietEnd,
                        child: Text('${context.tr('settings_quiet_to')} ${_formatTimeOfDay(_quietEnd)}'),
                      ),
                    ),
                  ],
                ),
              ),
          ],
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
          if (_session != null)
            _SettingsTile(
              icon: '⭐',
              title: context.tr('settings_rate_app'),
              onTap: _openRateAppSheet,
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
      )
            ),
          ],
        ),
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
