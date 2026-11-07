import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/api_session.dart';
import '../../core/phone_utils.dart';
import '../../core/supabase_client.dart';
import '../../core/session.dart';

sealed class LoginResult {}

class LoginSuccess extends LoginResult {
  final UserSession session;
  LoginSuccess(this.session);
}

class LoginFailure extends LoginResult {
  final String reason; // 'not_found' | 'bad_password' | 'rate_limited' | 'error'
  final String? message; // ready-to-show text for 'rate_limited'
  LoginFailure(this.reason, {this.message});
}

Map<String, String> get _sbHeaders => {
      'apikey': supabaseAnonKey,
      'Authorization': 'Bearer $supabaseAnonKey',
      'Content-Type': 'application/json',
    };

/// Goes through POST /api/auth/login (src/lib/session.ts) first — that
/// endpoint IS the same verify_login check, plus it starts a signed
/// session (ApiSession) the IDOR fix's Phase 2 proxy routes need. Calling
/// verify_login separately as well on top of a definitive wrong-password
/// verdict would double-count that attempt against its own rate limiter
/// (db/security-156), so a real bad-password/not-found result is never
/// retried.
///
/// Any other failure from that endpoint — network hiccup, or the token/
/// session layer itself being broken server-side (e.g. a missing secret;
/// this exact case broke login outright for every Flutter user until
/// security-178's follow-up added this fallback) — falls back to calling
/// verify_login directly, the same path this app used before the token
/// system existed. That fallback is safe to retry since it's only reached
/// when the first attempt never produced a definitive "wrong password"
/// verdict in the first place.
///
/// /api/auth/login doesn't distinguish "number not registered" from
/// "wrong password" (neither did verify_login itself — same query either
/// way), so the not_found-vs-bad_password disambiguation via
/// lookup_account below is ported 1:1 from the old direct-RPC version.
class AuthRepository {
  Future<LoginResult> login(String phoneInput, String password) async {
    final phone = normalizeEgyptianPhone(phoneInput);
    String? failureReason;
    String? failureMessage;
    final account = await ApiSession.login(
      phone,
      password,
      onError: (reason, {message}) {
        failureReason = reason;
        failureMessage = message;
      },
    );

    if (account != null && account['phone'] != null) {
      final session = UserSession(
        name: account['name'] as String? ?? '',
        phone: account['phone'] as String,
        role: account['role'] as String? ?? 'customer',
        city: account['city'] as String?,
        loginAt: DateTime.now().toIso8601String(),
      );
      return LoginSuccess(session);
    }

    if (failureReason == 'rate_limited') {
      return LoginFailure('rate_limited', message: failureMessage);
    }

    if (failureReason == 'invalid_credentials') {
      // A real wrong-password/not-registered verdict from verify_login
      // itself (ran server-side inside /api/auth/login) — disambiguate:
      // does this phone exist at all?
      try {
        final lookup = await http.post(
          Uri.parse('$supabaseUrl/rest/v1/rpc/lookup_account'),
          headers: _sbHeaders,
          body: jsonEncode({'p_phone': phone}),
        );
        final exists = lookup.statusCode == 200 && (jsonDecode(lookup.body) as List).isNotEmpty;
        return LoginFailure(exists ? 'bad_password' : 'not_found');
      } catch (_) {
        return LoginFailure('error');
      }
    }

    // Any other failure (network hiccup reaching the proxy, or the
    // token/session layer itself being unavailable — e.g. a missing
    // server secret, security-178) must never take login down entirely.
    // Fall back to the direct verify_login RPC: the same check
    // /api/auth/login.ts itself calls, and the only path this app used
    // before the token system existed. Safe to retry here specifically
    // because this branch is reached only when the first attempt never
    // produced a definitive "wrong password" verdict, so it can't
    // double-count a real bad-password attempt against security-156's
    // rate limiter.
    return _loginViaVerifyRpc(phone, password);
  }

  Future<LoginResult> _loginViaVerifyRpc(String phone, String password) async {
    try {
      final res = await http.post(
        Uri.parse('$supabaseUrl/rest/v1/rpc/verify_login'),
        headers: _sbHeaders,
        body: jsonEncode({'p_phone': phone, 'p_password': password}),
      );
      if (res.statusCode != 200) {
        if (res.body.contains('محاولات دخول كتير غلط')) {
          return LoginFailure('rate_limited', message: 'محاولات دخول كتير غلط — حاول تاني بعد شوية');
        }
        return LoginFailure('error');
      }
      final rows = jsonDecode(res.body) as List;
      if (rows.isEmpty) {
        final lookup = await http.post(
          Uri.parse('$supabaseUrl/rest/v1/rpc/lookup_account'),
          headers: _sbHeaders,
          body: jsonEncode({'p_phone': phone}),
        );
        final exists = lookup.statusCode == 200 && (jsonDecode(lookup.body) as List).isNotEmpty;
        return LoginFailure(exists ? 'bad_password' : 'not_found');
      }
      final account = rows.first as Map<String, dynamic>;
      final session = UserSession(
        name: account['name'] as String? ?? '',
        phone: account['phone'] as String,
        role: account['role'] as String? ?? 'customer',
        city: account['city'] as String?,
        loginAt: DateTime.now().toIso8601String(),
      );
      return LoginSuccess(session);
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
  /// Returns null on success, or a specific Arabic message identifying
  /// *which* field conflicted on failure — this is the final, authoritative
  /// insert (after register_screen.dart's own pre-check), so a failure here
  /// almost always means someone else grabbed the same phone/username/
  /// national ID/email in the few seconds between that check and this
  /// submit. PostgREST's unique_violation body names the actual column in
  /// `details`/`message` (e.g. "Key (national_id)=(...) already exists."),
  /// so map that back to a field-specific message instead of the old flat
  /// "قد يكون أحد البيانات مسجّلاً بالفعل" that never said which one.
  Future<String?> register({
    required String name,
    required String phone,
    required String password,
    String? username,
    String? email,
    String? city,
    String? nationalId,
    String? nationalIdExpiry,
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
      'national_id': nationalId,
      'national_id_expiry': nationalIdExpiry,
      'created_at': DateTime.now().toIso8601String(),
    };
    final res = await http.post(
      Uri.parse('$supabaseUrl/rest/v1/accounts'),
      headers: {..._sbHeaders, 'Prefer': 'return=minimal'},
      body: jsonEncode(payload),
    );
    if (res.statusCode == 201 || res.statusCode == 200) return null;

    String body = '';
    try {
      final decoded = jsonDecode(res.body);
      body = '${decoded['message'] ?? ''} ${decoded['details'] ?? ''}'.toLowerCase();
    } catch (_) {
      body = res.body.toLowerCase();
    }
    // National ID collisions don't reach the plain unique-index message at
    // all — guard_national_id_unique() (NATIONALIDUNIQUEMIGRATION.sql)
    // intercepts the insert first and raises this exact Arabic text instead
    // (so the same guard's error reads consistently across accounts/
    // driver_applications/merchant_applications), which the old English-
    // only substring check below never matched.
    if (body.contains('الرقم القومي') || body.contains('national_id')) {
      return 'هذا الرقم القومي مسجّل بالفعل.';
    }
    if (body.contains('phone')) return 'هذا الرقم مسجّل بالفعل — سجّل الدخول بدلاً من ذلك.';
    if (body.contains('username')) return 'اسم المستخدم محجوز، اختر اسماً آخر.';
    if (body.contains('email')) return 'هذا البريد الإلكتروني مسجّل بالفعل.';
    return 'حدث تعارض أثناء الإنشاء — قد يكون أحد البيانات مسجّلاً بالفعل. (${res.statusCode}: ${res.body.length > 200 ? res.body.substring(0, 200) : res.body})';
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
    required String email,
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
        // A direct PATCH here 401s ("permission denied for table
        // accounts") — anon has no SELECT grant on accounts (security06-
        // accountslockdown.sql), and PostgREST needs it internally to
        // evaluate a PATCH's WHERE filter even though the operation
        // itself is an UPDATE. upgrade_account_role() is a SECURITY
        // DEFINER RPC that does this safely instead — see
        // db/security-16-account-role-upgrade.sql.
        final patchRes = await http.post(
          Uri.parse('$supabaseUrl/rest/v1/rpc/upgrade_account_role'),
          headers: _sbHeaders,
          body: jsonEncode({'p_phone': acc['phone'], 'p_role': role}),
        );
        if (patchRes.statusCode != 200 || jsonDecode(patchRes.body) != true) {
          return DriverMerchantRegisterResult(error: true, phone: normalizedPhone, debugDetail: 'RPC ${patchRes.statusCode}: ${patchRes.body}');
        }
      } else {
        final createRes = await http.post(
          Uri.parse('$supabaseUrl/rest/v1/accounts'),
          headers: {..._sbHeaders, 'Prefer': 'return=minimal'},
          body: jsonEncode({
            'phone': normalizedPhone,
            'password': password,
            'name': name,
            'email': email,
            'role': role,
            'status': 'pending',
            'city': city,
            'created_at': DateTime.now().toIso8601String(),
          }),
        );
        if (createRes.statusCode != 201 && createRes.statusCode != 200) {
          return DriverMerchantRegisterResult(error: true, phone: normalizedPhone, debugDetail: 'POST ${createRes.statusCode}: ${createRes.body}');
        }
      }

      // NOT trying to pre-create a driver_applications row here anymore —
      // national_id_number, national_id_expiry, license_number,
      // license_expiry, vehicle_reg_number, vehicle_reg_expiry,
      // vehicle_model, vehicle_color, vehicle_year, vehicle_purchase_date,
      // and vehicle_ownership are ALL `not null` with no default (checked
      // directly against the live schema), so ANY insert with just
      // id/phone/full_name always fails — that was true for this code and
      // is equally true for driver.astro's own panel-0 preliminary insert,
      // which just never surfaces the failure (wrapped in .catch(()=>{})
      // without checking .ok). driver.astro's final-submit step
      // (submitApp) already creates the real row from scratch once it has
      // every required field, so there's nothing missing by skipping this
      // — the personal photo is carried over via the continuation link's
      // query param instead (see uploadDriverPhoto below).
      return DriverMerchantRegisterResult(phone: normalizedPhone);
    } catch (e) {
      return DriverMerchantRegisterResult(error: true, phone: normalizeEgyptianPhone(phone), debugDetail: e.toString());
    }
  }

  /// Uploads the driver's personal photo (captured via camera on the
  /// native registration screen) to the same `documents` bucket/path
  /// convention driver.astro's handleUpload() uses, and returns the
  /// public URL — carried to the web continuation link as a query param
  /// (?photo=) rather than written to driver_applications directly, since
  /// there's no row to attach it to yet (see registerDriverOrMerchant).
  Future<String?> uploadDriverPhoto(String phone, List<int> bytes, String fileExt) async {
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
    if (uploadRes.statusCode != 200 && uploadRes.statusCode != 201) return null;
    return '$supabaseUrl/storage/v1/object/public/documents/$path';
  }
}

class DriverMerchantRegisterResult {
  final bool error;
  final bool alreadyRegistered;
  final String phone;
  final String? debugDetail;
  DriverMerchantRegisterResult({
    this.error = false,
    this.alreadyRegistered = false,
    required this.phone,
    this.debugDetail,
  });
  bool get ok => !error && !alreadyRegistered;
}
