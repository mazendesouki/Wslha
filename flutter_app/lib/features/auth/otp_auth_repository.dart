import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../core/phone_utils.dart';
import '../../core/session.dart';
import '../../core/supabase_client.dart';

Map<String, String> get _sbHeaders => {
      'apikey': supabaseAnonKey,
      'Authorization': 'Bearer $supabaseAnonKey',
      'Content-Type': 'application/json',
    };

class OtpSendFailure implements Exception {
  final String reason; // 'not_found' | 'no_email' | 'error'
  OtpSendFailure(this.reason);
}

/// Phase 1 of the real-auth migration (db/security-88) originally used
/// Supabase Auth's own phone-OTP flow (SMS via Twilio Verify). The Twilio
/// account ran into a billing problem (an old, unrelated Marketplace
/// add-on subscription drained its balance and Twilio suspended it), so
/// SMS delivery can't be relied on right now — this repository was
/// switched to reuse the same email-code infrastructure built for the
/// admin panel's 2FA (db/security-90) instead:
///   - the "swift-processor" edge function (request-password-reset logic)
///     emails a 6-digit code to the account's registered address via Resend
///   - verify_otp_code() checks it (unused + unexpired + latest), same
///     logic reset_password() already used, but with no side effect
/// This only works for accounts that already exist with a registered
/// email — true for every customer account, since email is required at
/// registration (see register_screen.dart). Login-only: a phone with no
/// matching account is reported as 'not_found', same as the password
/// login flow, since there's no email yet to create one via.
class OtpAuthRepository {
  Future<void> sendCode(String phoneInput) async {
    final local = normalizeEgyptianPhone(phoneInput);
    final lookup = await http.post(
      Uri.parse('$supabaseUrl/rest/v1/rpc/lookup_account'),
      headers: _sbHeaders,
      body: jsonEncode({'p_phone': local}),
    );
    final rows = lookup.statusCode == 200 ? jsonDecode(lookup.body) as List : [];
    if (rows.isEmpty) throw OtpSendFailure('not_found');

    final res = await http.post(
      Uri.parse('$supabaseUrl/functions/v1/swift-processor'),
      headers: _sbHeaders,
      body: jsonEncode({'phone': local}),
    );
    if (res.statusCode != 200) {
      throw OtpSendFailure(res.body.contains('no_email') ? 'no_email' : 'error');
    }
  }

  /// Verifies the code, then loads the (already-existing) account row via
  /// the same narrow RPC every other screen uses, and returns it as a
  /// UserSession — same shape the password-login flow produces.
  Future<UserSession> verifyCode(String phoneInput, String code) async {
    final local = normalizeEgyptianPhone(phoneInput);
    final verifyRes = await http.post(
      Uri.parse('$supabaseUrl/rest/v1/rpc/verify_otp_code'),
      headers: _sbHeaders,
      body: jsonEncode({'p_phone': local, 'p_code': code.trim()}),
    );
    final ok = verifyRes.statusCode == 200 && jsonDecode(verifyRes.body) == true;
    if (!ok) throw Exception('bad_code');

    final lookup = await http.post(
      Uri.parse('$supabaseUrl/rest/v1/rpc/lookup_account'),
      headers: _sbHeaders,
      body: jsonEncode({'p_phone': local}),
    );
    final rows = lookup.statusCode == 200 ? jsonDecode(lookup.body) as List : [];
    if (rows.isEmpty) throw Exception('account_not_found');
    final row = rows.first as Map<String, dynamic>;

    return UserSession(
      name: row['name'] as String? ?? '',
      phone: row['phone'] as String,
      role: row['role'] as String? ?? 'customer',
      city: row['city'] as String?,
      loginAt: DateTime.now().toIso8601String(),
    );
  }
}
