import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// وصّلها website/API host (Vercel) — separate from [supabaseUrl]; the
/// token-verified proxy routes live in src/pages/api/* on this domain,
/// not on Supabase directly.
const apiBaseUrl = 'https://wslha.co';

/// Session-token layer for the IDOR fix's Phase 2 (db/security-157's
/// scoping plan): src/lib/session.ts already issues a signed, short-lived
/// access token + rotating refresh token after a real password check, but
/// nothing in this app used it before now — every RPC call just trusted
/// whatever phone the client sent. This class starts a session alongside
/// the existing phone+password login and makes the token available to
/// every repository that has a token-verified proxy route (src/pages/api/
/// profile|driver|wallet|support/*).
///
/// Deliberately NOT a hard cutover: a user who was already logged in
/// before this update shipped has no token yet (their session predates
/// this feature) and won't get one until they log in again — every
/// migrated repository method falls back to the old direct RPC call
/// when [getJson]/[postJson] return null for lack of a token, so nothing
/// breaks mid-rollout. The underlying RPCs stay reachable with the anon
/// key until a later phase revokes that direct access once real adoption
/// is confirmed.
class ApiSession {
  ApiSession._();

  static String? _accessToken;
  static DateTime? _accessTokenExpiresAt;
  // The refresh token travels as an HttpOnly cookie in the browser this
  // system was originally built for — Dart's http client has no cookie
  // jar of its own, so it's extracted from Set-Cookie and resent manually
  // as a plain Cookie header on just the two auth endpoints that need it.
  static String? _refreshCookie;

  static const _cookiePrefsKey = 'wslha_api_refresh_cookie';

  static Future<void> _persistCookie(String? cookie) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (cookie == null) {
        await prefs.remove(_cookiePrefsKey);
      } else {
        await prefs.setString(_cookiePrefsKey, cookie);
      }
    } catch (_) {
      // Non-fatal — worst case the session doesn't survive an app restart.
    }
  }

  static Future<void> _restoreCookieIfNeeded() async {
    if (_refreshCookie != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _refreshCookie = prefs.getString(_cookiePrefsKey);
    } catch (_) {}
  }

  static String? _extractCookie(http.Response res) {
    final raw = res.headers['set-cookie'];
    if (raw == null) return null;
    final first = raw.split(';').first.trim();
    return first.isNotEmpty ? first : null;
  }

  /// Starts a new signed session via POST /api/auth/login — this IS the
  /// password check (same verify_login RPC the old direct call used), so
  /// callers should use this instead of calling verify_login separately;
  /// doing both would double-count a wrong password against
  /// verify_login's own rate limiter (db/security-156).
  ///
  /// Returns the verified account row on success. On failure, returns
  /// null and calls [onError] with one of: 'invalid_credentials',
  /// 'rate_limited' (with a ready-to-show Arabic message), or 'error'
  /// (network/unexpected failure) — the caller is responsible for the
  /// existing not_found-vs-bad_password disambiguation (a wrong number
  /// and a wrong password both come back as invalid_credentials here,
  /// same as verify_login itself never distinguished them either).
  static Future<Map<String, dynamic>?> login(
    String phone,
    String password, {
    void Function(String reason, {String? message})? onError,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$apiBaseUrl/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone, 'password': password}),
      );
      Map<String, dynamic> decoded = {};
      try {
        if (res.body.isNotEmpty) decoded = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {}

      if (res.statusCode != 200) {
        onError?.call(decoded['error'] as String? ?? 'error', message: decoded['message'] as String?);
        return null;
      }

      _accessToken = decoded['accessToken'] as String?;
      final expiresIn = (decoded['expiresIn'] as num?)?.toInt() ?? 900;
      _accessTokenExpiresAt = DateTime.now().add(Duration(seconds: expiresIn));
      final cookie = _extractCookie(res);
      if (cookie != null) {
        _refreshCookie = cookie;
        await _persistCookie(cookie);
      }
      return decoded['account'] as Map<String, dynamic>?;
    } catch (_) {
      onError?.call('error');
      return null;
    }
  }

  /// Revokes the whole session family server-side and clears local state.
  /// Safe to call even if there's no active token-based session (a user
  /// who never re-logged-in since this feature shipped) — it's a no-op
  /// against the server in that case, but still clears anything local.
  static Future<void> logout() async {
    await _restoreCookieIfNeeded();
    try {
      await http.post(
        Uri.parse('$apiBaseUrl/api/auth/logout'),
        headers: {
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
          if (_refreshCookie != null) 'Cookie': _refreshCookie!,
        },
      );
    } catch (_) {}
    _accessToken = null;
    _accessTokenExpiresAt = null;
    _refreshCookie = null;
    await _persistCookie(null);
  }

  static Future<bool> _refresh() async {
    await _restoreCookieIfNeeded();
    if (_refreshCookie == null) return false;
    try {
      final res = await http.post(
        Uri.parse('$apiBaseUrl/api/auth/refresh'),
        headers: {'Cookie': _refreshCookie!},
      );
      if (res.statusCode != 200) {
        // Dead, expired, or theft-revoked — stop retrying with it.
        _accessToken = null;
        _accessTokenExpiresAt = null;
        _refreshCookie = null;
        await _persistCookie(null);
        return false;
      }
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      _accessToken = decoded['accessToken'] as String?;
      final expiresIn = (decoded['expiresIn'] as num?)?.toInt() ?? 900;
      _accessTokenExpiresAt = DateTime.now().add(Duration(seconds: expiresIn));
      final cookie = _extractCookie(res);
      if (cookie != null) {
        _refreshCookie = cookie;
        await _persistCookie(cookie);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// A currently-valid access token, refreshing first if missing or
  /// expiring within 30s, or null if no session is available at all
  /// (never logged in through [login], or the refresh session died) —
  /// callers treat null as "fall back to the old direct RPC call".
  static Future<String?> getValidAccessToken() async {
    final expiresAt = _accessTokenExpiresAt;
    final needsRefresh = _accessToken == null ||
        expiresAt == null ||
        expiresAt.isBefore(DateTime.now().add(const Duration(seconds: 30)));
    if (needsRefresh) {
      final ok = await _refresh();
      if (!ok) return null;
    }
    return _accessToken;
  }

  /// GETs a token-protected proxy route (src/pages/api/*). Returns the
  /// decoded JSON body on success, or null if there's no valid session
  /// yet or the call failed for any reason — the caller falls back to
  /// the equivalent direct RPC call in that case, never throws.
  static Future<Map<String, dynamic>?> getJson(String path) async {
    final token = await getValidAccessToken();
    if (token == null) return null;
    try {
      final res = await http.get(Uri.parse('$apiBaseUrl$path'), headers: {'Authorization': 'Bearer $token'});
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// POSTs to a token-protected proxy route. Same null-means-fall-back
  /// contract as [getJson].
  static Future<Map<String, dynamic>?> postJson(String path, Map<String, dynamic> body) async {
    final token = await getValidAccessToken();
    if (token == null) return null;
    try {
      final res = await http.post(
        Uri.parse('$apiBaseUrl$path'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      if (res.statusCode != 200) return null;
      if (res.body.isEmpty) return <String, dynamic>{};
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
