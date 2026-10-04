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
import '../support/support_screen.dart';
import 'merchant_repository.dart';

/// Merchant's settings — store profile (name/open-closed/tagline/delivery
/// fee/min order) plus the same app-level prefs the customer settings
/// screen offers (notifications/dark-mode/language/support/logout/version),
/// since the merchant flavor otherwise had no settings screen at all.
class MerchantSettingsScreen extends StatefulWidget {
  final UserSession session;
  final Map<String, dynamic> store;
  const MerchantSettingsScreen({super.key, required this.session, required this.store});

  @override
  State<MerchantSettingsScreen> createState() => _MerchantSettingsScreenState();
}

class _MerchantSettingsScreenState extends State<MerchantSettingsScreen> {
  static const _notifKey = 'wslha_notif';
  final _repo = MerchantRepository();
  final _nameCtrl = TextEditingController();
  final _taglineCtrl = TextEditingController();
  final _feeCtrl = TextEditingController();
  final _minOrderCtrl = TextEditingController();
  late bool _isOpen;
  bool _saving = false;
  bool _notifEnabled = true;
  String? _versionLabel;
  UpdateInfo? _updateInfo;

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = widget.store['name'] as String? ?? '';
    _taglineCtrl.text = widget.store['tagline'] as String? ?? '';
    _feeCtrl.text = '${widget.store['delivery_fee'] ?? ''}';
    _minOrderCtrl.text = '${widget.store['min_order'] ?? ''}';
    _isOpen = widget.store['is_open'] as bool? ?? true;
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _notifEnabled = prefs.getBool(_notifKey) ?? true);
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _versionLabel = '${info.version}+${info.buildNumber}');
    final update = await UpdateChecker().checkForUpdate(AppFlavor.merchant);
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

  Future<void> _saveStore() async {
    setState(() => _saving = true);
    try {
      await _repo.updateStoreInfo(
        widget.store['id'].toString(),
        name: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
        tagline: _taglineCtrl.text.trim(),
        isOpen: _isOpen,
        deliveryFee: num.tryParse(_feeCtrl.text.trim()),
        minOrder: num.tryParse(_minOrderCtrl.text.trim()),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('merchant_settings_save_success')), backgroundColor: AppColors.success),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${context.tr('merchant_settings_save_failed_prefix')} $e'), backgroundColor: AppColors.error, duration: const Duration(seconds: 6)),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _logout() async {
    await SessionStore.clear();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _taglineCtrl.dispose();
    _feeCtrl.dispose();
    _minOrderCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.mutedSurface,
      body: SafeArea(
        child: Column(
          children: [
            BrandedHeader(title: context.tr('merchant_settings_title')),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_updateInfo != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
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
                  Text(context.tr('merchant_settings_store_section'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: context.surfaceColor,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: context.borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _nameCtrl,
                          decoration: InputDecoration(labelText: context.tr('merchant_settings_store_name')),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _taglineCtrl,
                          decoration: InputDecoration(labelText: context.tr('merchant_settings_store_tagline')),
                        ),
                        const SizedBox(height: 4),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(context.tr('merchant_settings_store_open')),
                          value: _isOpen,
                          activeThumbColor: AppColors.primary,
                          onChanged: (v) => setState(() => _isOpen = v),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _feeCtrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(labelText: context.tr('merchant_settings_delivery_fee')),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _minOrderCtrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(labelText: context.tr('merchant_settings_min_order')),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _saving ? null : _saveStore,
                          child: _saving
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : Text(context.tr('merchant_settings_save')),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 32),
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
                  ListTile(
                    leading: const Text('🛟', style: TextStyle(fontSize: 20)),
                    title: Text(context.tr('settings_support')),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SupportScreen())),
                  ),
                  const Divider(height: 24),
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
            ),
          ],
        ),
      ),
    );
  }
}
