import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../../core/phone_utils.dart';
import '../../core/supabase_client.dart';
import '../../core/session.dart';

/// Matches the 'wtx-<epoch>-<random hex>' id convention already used
/// elsewhere in this codebase for text-primary-key tables with no
/// server-side default (e.g. wallet_transactions inserts).
String _generateId(String prefix) {
  final rand = Random();
  final hex = List.generate(6, (_) => rand.nextInt(16).toRadixString(16)).join();
  return '$prefix-${DateTime.now().millisecondsSinceEpoch}-$hex';
}

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

  /// Ported from driver.astro's doRegister()/merchant-apply.astro's
  /// registerMerchantAndProceed() — same lookup_account → create-or-
  /// upgrade-role flow. Unlike those pages, this does NOT log the user
  /// into the app on success: the rest of the KYC (documents, vehicle/
  /// store info, admin review) still only exists on the web, and this
  /// app has no gate anywhere that checks driver_applications.status
  /// before letting a 'driver'-role session go online — so auto-login
  /// here would let a brand-new, unreviewed account straight into the
  /// live driver dashboard. The caller sends the user to finish on the
  /// website instead.
  Future<DriverMerchantRegisterResult> registerDriverOrMerchant({
    required String role, // 'driver' | 'merchant'
    required String name,
    required String phone,
    required String password,
    required String city,
  }) async {
    final normalizedPhone = normalizeEgyptianPhone(phone);
    try {
      final lookupRes = await http.post(
        Uri.parse('$supabaseUrl/rest/v1/rpc/lookup_account'),
        headers: _sbHeaders,
        body: jsonEncode({'p_phone': normalizedPhone}),
      );
      final existing = lookupRes.statusCode == 200 ? jsonDecode(lookupRes.body) as List : [];

      if (existing.isNotEmpty) {
        final acc = existing.first as Map<String, dynamic>;
        if (acc['role'] == role) {
          return DriverMerchantRegisterResult(alreadyRegistered: true, phone: normalizedPhone);
        }
        final patchRes = await http.patch(
          Uri.parse('$supabaseUrl/rest/v1/accounts?phone=eq.${Uri.encodeComponent(acc['phone'] as String)}'),
          headers: {..._sbHeaders, 'Prefer': 'return=minimal'},
          body: jsonEncode({'role': role, 'status': 'pending'}),
        );
        if (patchRes.statusCode != 204 && patchRes.statusCode != 200) {
          return DriverMerchantRegisterResult(error: true, phone: normalizedPhone);
        }
      } else {
        final createRes = await http.post(
          Uri.parse('$supabaseUrl/rest/v1/accounts'),
          headers: {..._sbHeaders, 'Prefer': 'return=minimal'},
          body: jsonEncode({
            'phone': normalizedPhone,
            'password': password,
            'name': name,
            'role': role,
            'status': 'pending',
            'city': city,
            'created_at': DateTime.now().toIso8601String(),
          }),
        );
        if (createRes.statusCode != 201 && createRes.statusCode != 200) {
          return DriverMerchantRegisterResult(error: true, phone: normalizedPhone);
        }
      }

      if (role == 'driver') {
        // Preliminary driver_applications row — same as driver.astro's
        // panel-0 submit, so the web KYC steps have something to PATCH
        // into rather than starting from nothing.
        final existingApp = await http.get(
          Uri.parse('$supabaseUrl/rest/v1/driver_applications?phone=eq.${Uri.encodeComponent(normalizedPhone)}&select=id&limit=1'),
          headers: _sbHeaders,
        );
        final hasApp = existingApp.statusCode == 200 && (jsonDecode(existingApp.body) as List).isNotEmpty;
        if (!hasApp) {
          // driver_applications.id is `text primary key` with NO default —
          // the web always generates one client-side (crypto.randomUUID())
          // before inserting. Omitting it here made every native
          // registration's preliminary-row insert fail its NOT NULL
          // constraint silently (this POST's result was never checked),
          // so uploadDriverPhoto()'s later PATCH matched zero rows and the
          // web resume step never found a photo to skip re-uploading.
          final insertRes = await http.post(
            Uri.parse('$supabaseUrl/rest/v1/driver_applications'),
            headers: {..._sbHeaders, 'Prefer': 'return=minimal'},
            body: jsonEncode({
              'id': _generateId('da'),
              'phone': normalizedPhone,
              'full_name': name,
              'status': 'pending',
              'created_at': DateTime.now().toIso8601String(),
            }),
          );
          if (insertRes.statusCode != 201 && insertRes.statusCode != 200) {
            return DriverMerchantRegisterResult(error: true, phone: normalizedPhone);
          }
        }
      }

      return DriverMerchantRegisterResult(phone: normalizedPhone);
    } catch (_) {
      return DriverMerchantRegisterResult(error: true, phone: normalizeEgyptianPhone(phone));
    }
  }

  /// Uploads the driver's personal photo (captured via camera on the
  /// native registration screen) to the same `documents` bucket/path
  /// convention driver.astro's handleUpload() uses, then patches it onto
  /// the preliminary driver_applications row.
  Future<bool> uploadDriverPhoto(String phone, List<int> bytes, String fileExt) async {
    final path = 'driver-apps/$phone/driver-photo-${DateTime.now().millisecondsSinceEpoch}.$fileExt';
    final uploadRes = await http.post(
      Uri.parse('$supabaseUrl/storage/v1/object/documents/$path'),
      headers: {
        'apikey': supabaseAnonKey,
        'Authorization': 'Bearer $supabaseAnonKey',
        'Content-Type': 'image/$fileExt',
      },
      body: bytes,
    );
    if (uploadRes.statusCode != 200 && uploadRes.statusCode != 201) return false;

    final url = '$supabaseUrl/storage/v1/object/public/documents/$path';
    final patchRes = await http.patch(
      Uri.parse('$supabaseUrl/rest/v1/driver_applications?phone=eq.${Uri.encodeComponent(phone)}'),
      headers: {..._sbHeaders, 'Prefer': 'return=minimal'},
      body: jsonEncode({'driver_photo_url': url}),
    );
    return patchRes.statusCode == 204 || patchRes.statusCode == 200;
  }
}

class DriverMerchantRegisterResult {
  final bool error;
  final bool alreadyRegistered;
  final String phone;
  DriverMerchantRegisterResult({this.error = false, this.alreadyRegistered = false, required this.phone});
  bool get ok => !error && !alreadyRegistered;
}
