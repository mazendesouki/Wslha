import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/phone_utils.dart';
import '../../core/supabase_client.dart';
import '../../core/session.dart';

sealed class LoginResult {}

class LoginSuccess extends LoginResult {
  final UserSession session;
  LoginSuccess(this.session);
}

class LoginFailure extends LoginResult {
  final String reason; // 'not_found' | 'bad_password' | 'error'
  LoginFailure(this.reason);
}

Map<String, String> get _sbHeaders => {
      'apikey': supabaseAnonKey,
      'Authorization': 'Bearer $supabaseAnonKey',
      'Content-Type': 'application/json',
    };

/// Ported 1:1 from src/utils/accounts.ts's verifyLogin() — same RPCs, same
/// two-step "no row → disambiguate via lookup_account" fallback so a wrong
/// password and an unregistered number get different error messages.
class AuthRepository {
  Future<LoginResult> login(String phoneInput, String password) async {
    final phone = normalizeEgyptianPhone(phoneInput);
    try {
      final res = await http.post(
        Uri.parse('$supabaseUrl/rest/v1/rpc/verify_login'),
        headers: _sbHeaders,
        body: jsonEncode({'p_phone': phone, 'p_password': password}),
      );
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        final raw = decoded is List ? (decoded.isNotEmpty ? decoded.first : null) : decoded;
        if (raw != null && raw['phone'] != null) {
          final session = UserSession(
            name: raw['name'] as String? ?? '',
            phone: raw['phone'] as String,
            role: raw['role'] as String? ?? 'customer',
            city: raw['city'] as String?,
            loginAt: DateTime.now().toIso8601String(),
          );
          return LoginSuccess(session);
        }
        // No row → disambiguate: does this phone exist at all?
        final lookup = await http.post(
          Uri.parse('$supabaseUrl/rest/v1/rpc/lookup_account'),
          headers: _sbHeaders,
          body: jsonEncode({'p_phone': phone}),
        );
        final exists = lookup.statusCode == 200 && (jsonDecode(lookup.body) as List).isNotEmpty;
        return LoginFailure(exists ? 'bad_password' : 'not_found');
      }
      return LoginFailure('error');
    } catch (_) {
      return LoginFailure('error');
    }
  }

  /// Ported from accounts.ts's fieldExists() — same narrow RPCs, since the
  /// anon key can't SELECT the accounts table directly.
  Future<bool> fieldExists(String field, String value) async {
    if (value.isEmpty) return false;
    final v = field == 'phone'
        ? normalizeEgyptianPhone(value)
        : field == 'national_id'
            ? value.trim()
            : value.trim().toLowerCase();
    final isNationalId = field == 'national_id';
    final res = await http.post(
      Uri.parse(isNationalId
          ? '$supabaseUrl/rest/v1/rpc/check_national_id_availability'
          : '$supabaseUrl/rest/v1/rpc/check_field_availability'),
      headers: _sbHeaders,
      body: jsonEncode(isNationalId ? {'p_value': v} : {'p_field': field, 'p_value': v}),
    );
    if (res.statusCode != 200) return false;
    return jsonDecode(res.body) == true;
  }

  /// Ported from accounts.ts's sbInsert() — direct POST /accounts insert,
  /// same payload shape (password sent plaintext, hashed by a DB trigger
  /// server-side, exactly like the web app already does).
  Future<bool> register({
    required String name,
    required String phone,
    required String password,
    String? username,
    String? email,
    String? city,
  }) async {
    final normalizedPhone = normalizeEgyptianPhone(phone);
    final payload = {
      'phone': normalizedPhone,
      'password': password,
      'name': name,
      'username': username?.toLowerCase(),
      'email': email?.toLowerCase(),
      'role': 'customer',
      'city': city,
      'created_at': DateTime.now().toIso8601String(),
    };
    final res = await http.post(
      Uri.parse('$supabaseUrl/rest/v1/accounts'),
      headers: {..._sbHeaders, 'Prefer': 'return=minimal'},
      body: jsonEncode(payload),
    );
    return res.statusCode == 201 || res.statusCode == 200;
  }
}
