import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// A small on-device, TTL-based cache for read-heavy, slow-changing data —
/// catalogs, rate tables, store/menu listings, admin-configured settings.
/// Goal: the second (and every later) time a screen backed by one of these
/// opens, it renders from what's already on the device instead of waiting
/// on a round trip, and the server sees one request per [maxAge] window
/// instead of one per screen open.
///
/// Deliberately NOT for anything money- or status-related (wallet balance,
/// ride/order status, dispatch offers, notifications) — those must always
/// reflect the current server state, never a cached snapshot that could
/// read as "your balance is X" when it's actually changed since. Realtime-
/// backed screens already get this for free; this cache is for the data
/// that doesn't need realtime, just doesn't need re-fetching every time
/// either.
class DataCache {
  DataCache._();
  static const _prefix = 'data_cache_';

  /// Returns the cached value for [key] if it exists and is younger than
  /// [maxAge], decoding it with [fromJson]. Returns null on a miss, a
  /// stale entry, or a decode failure (corrupt/old-shape cache entries are
  /// silently treated as a miss rather than thrown).
  static Future<T?> read<T>(
    String key,
    T Function(Map<String, dynamic>) fromJson, {
    required Duration maxAge,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefix$key');
      if (raw == null) return null;
      final envelope = jsonDecode(raw) as Map<String, dynamic>;
      final savedAt = DateTime.tryParse(envelope['savedAt'] as String? ?? '');
      if (savedAt == null || DateTime.now().toUtc().difference(savedAt) > maxAge) return null;
      return fromJson(envelope['data'] as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Same as [read], but for a cached list of items.
  static Future<List<T>?> readList<T>(
    String key,
    T Function(Map<String, dynamic>) fromJson, {
    required Duration maxAge,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefix$key');
      if (raw == null) return null;
      final envelope = jsonDecode(raw) as Map<String, dynamic>;
      final savedAt = DateTime.tryParse(envelope['savedAt'] as String? ?? '');
      if (savedAt == null || DateTime.now().toUtc().difference(savedAt) > maxAge) return null;
      final data = envelope['data'] as List;
      return data.map((e) => fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String key, Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_prefix$key',
        jsonEncode({'savedAt': DateTime.now().toUtc().toIso8601String(), 'data': data}),
      );
    } catch (_) {
      // Cache is a pure speed optimization — a failed write just means the
      // next open fetches fresh again, same as today.
    }
  }

  static Future<void> writeList(String key, List<Map<String, dynamic>> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_prefix$key',
        jsonEncode({'savedAt': DateTime.now().toUtc().toIso8601String(), 'data': data}),
      );
    } catch (_) {}
  }

  /// Fetch-through helper: serves the cached list if still fresh, otherwise
  /// calls [fetch], caches the result, and returns it. A failed [fetch]
  /// with no usable cache rethrows so the caller's existing error handling
  /// (empty state, snackbar, etc.) still runs — this never silently hides
  /// a real failure behind an empty list.
  static Future<List<T>> fetchList<T>({
    required String key,
    required Duration maxAge,
    required Future<List<T>> Function() fetch,
    required Map<String, dynamic> Function(T) toJson,
    required T Function(Map<String, dynamic>) fromJson,
  }) async {
    final cached = await readList<T>(key, fromJson, maxAge: maxAge);
    if (cached != null) return cached;
    final fresh = await fetch();
    await writeList(key, fresh.map(toJson).toList());
    return fresh;
  }

  static Future<void> invalidate(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefix$key');
    } catch (_) {}
  }
}
