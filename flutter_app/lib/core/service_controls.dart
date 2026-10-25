import 'supabase_client.dart';

/// db/security-127's service_controls — the real on/off/scheduled switch
/// for a major service (rides, delivery, marketplace, registration,
/// wallet deposit, coupons), already enforced server-side (the actual
/// booking/order/registration RPC or INSERT trigger rejects it outright
/// when off). Unlike FeatureFlags (loaded once at app start), this is
/// checked fresh right before the user would actually try to use the
/// service — it's a UX improvement over the backend rejection the
/// request would get anyway, not the enforcement itself, so a stale
/// cached value defeats the purpose; always ask live.
class ServiceControls {
  ServiceControls._();

  /// Fails open (true) on any network hiccup — same convention as
  /// FeatureFlags — so a flaky connection never blocks a feature that's
  /// actually on. The real enforcement happens server-side regardless.
  static Future<bool> isActive(String key) async {
    try {
      final result = await sb.rpc('is_service_active', params: {'p_key': key});
      return result != false;
    } catch (_) {
      return true;
    }
  }
}
