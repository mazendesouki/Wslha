import 'supabase_client.dart';

/// Every optional feature added this session gets an admin-controllable
/// on/off switch (db/security-72) — no new backend plumbing needed, since
/// admin.astro's settings panel already writes any app_settings key
/// through the generic admin_set_setting RPC. All default true (current
/// behavior unchanged) unless an admin explicitly turns one off.
class FeatureFlags {
  FeatureFlags._();

  static bool sosEnabled = true;
  static bool favoritesEnabled = true;
  static bool referralEnabled = true;
  static bool chatEnabled = true;
  static bool noShowEnabled = true;
  static bool multistopEnabled = true;
  static bool dailyGoalEnabled = true;
  static bool rideShareEnabled = true;
  static bool supportChatEnabled = true;
  static bool aiBotEnabled = true;
  static bool couponsEnabled = true;
  static bool scheduledRidesEnabled = true;
  static bool darkModeEnabled = true;
  static bool languageSwitchEnabled = true;

  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    await refresh();
  }

  static Future<void> refresh() async {
    try {
      final rows = await sb.from('app_settings').select('key,value').inFilter('key', [
        'feature_sos_enabled',
        'feature_favorites_enabled',
        'feature_referral_enabled',
        'feature_chat_enabled',
        'feature_no_show_enabled',
        'feature_multistop_enabled',
        'feature_daily_goal_enabled',
        'feature_ride_share_enabled',
        'feature_support_chat_enabled',
        'feature_ai_bot_enabled',
        'feature_coupons_enabled',
        'feature_scheduled_rides_enabled',
        'feature_dark_mode_enabled',
        'feature_language_switch_enabled',
      ]);

      bool? flag(String key) {
        final row = (rows as List).cast<Map<String, dynamic>>().where((r) => r['key'] == key).toList();
        if (row.isEmpty) return null;
        return '${row.first['value']}' == 'true';
      }

      sosEnabled = flag('feature_sos_enabled') ?? sosEnabled;
      favoritesEnabled = flag('feature_favorites_enabled') ?? favoritesEnabled;
      referralEnabled = flag('feature_referral_enabled') ?? referralEnabled;
      chatEnabled = flag('feature_chat_enabled') ?? chatEnabled;
      noShowEnabled = flag('feature_no_show_enabled') ?? noShowEnabled;
      multistopEnabled = flag('feature_multistop_enabled') ?? multistopEnabled;
      dailyGoalEnabled = flag('feature_daily_goal_enabled') ?? dailyGoalEnabled;
      rideShareEnabled = flag('feature_ride_share_enabled') ?? rideShareEnabled;
      supportChatEnabled = flag('feature_support_chat_enabled') ?? supportChatEnabled;
      aiBotEnabled = flag('feature_ai_bot_enabled') ?? aiBotEnabled;
      couponsEnabled = flag('feature_coupons_enabled') ?? couponsEnabled;
      scheduledRidesEnabled = flag('feature_scheduled_rides_enabled') ?? scheduledRidesEnabled;
      darkModeEnabled = flag('feature_dark_mode_enabled') ?? darkModeEnabled;
      languageSwitchEnabled = flag('feature_language_switch_enabled') ?? languageSwitchEnabled;
      _loaded = true;
    } catch (_) {
      // Network hiccup — keep whatever was already loaded (defaults true).
    }
  }
}
