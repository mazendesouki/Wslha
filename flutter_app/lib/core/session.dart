import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Mirrors the shape written to localStorage['wslha_user'] by the web app
/// (login.astro/register.astro) so both clients agree on what a "session"
/// looks like, even though this app stores it via shared_preferences
/// instead of the browser's localStorage.
class UserSession {
  final String name;
  final String phone;
  final String role; // customer | driver | merchant | admin
  final String? city;
  final String loginAt;

  const UserSession({
    required this.name,
    required this.phone,
    required this.role,
    this.city,
    required this.loginAt,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'phone': phone,
        'role': role,
        'city': city,
        'loginAt': loginAt,
      };

  factory UserSession.fromJson(Map<String, dynamic> j) => UserSession(
        name: j['name'] as String? ?? '',
        phone: j['phone'] as String? ?? '',
        role: j['role'] as String? ?? 'customer',
        city: j['city'] as String?,
        loginAt: j['loginAt'] as String? ?? DateTime.now().toIso8601String(),
      );
}

class SessionStore {
  static const _key = 'wslha_user';
  static const _rememberKey = 'wslha_remember_me';

  /// [remember] false means "stay logged in for this app run only" — the
  /// session is still written (the app always re-reads via SessionStore on
  /// every navigation to '/home', so it has to be there for the *current*
  /// run to work at all) but load() below consumes/deletes it the moment
  /// it's read, so the *next* cold start finds nothing and shows LoginScreen
  /// again instead of auto-continuing.
  static Future<void> save(UserSession session, {bool remember = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(session.toJson()));
    await prefs.setBool(_rememberKey, remember);
  }

  static Future<UserSession?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    if (prefs.getBool(_rememberKey) == false) {
      await prefs.remove(_key);
      await prefs.remove(_rememberKey);
    }
    try {
      return UserSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
