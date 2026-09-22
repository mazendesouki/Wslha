import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../core/phone_utils.dart';
import '../../core/supabase_client.dart';
import 'otp_auth_repository.dart';

Map<String, String> get _sbHeaders => {
      'apikey': supabaseAnonKey,
      'Authorization': 'Bearer $supabaseAnonKey',
      'Content-Type': 'application/json',
    };

/// "نسيت كلمة المرور؟" — same swift-processor (email code) + reset_password
/// RPC pair the web app's login.astro forgot-password step already uses
/// (db/security-03). Always email-based, so unaffected by the Twilio SMS
/// billing issue.
class PasswordResetRepository {
  Future<void> sendResetCode(String phoneInput) async {
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

  Future<bool> resetPassword(String phoneInput, String code, String newPassword) async {
    final local = normalizeEgyptianPhone(phoneInput);
    final res = await http.post(
      Uri.parse('$supabaseUrl/rest/v1/rpc/reset_password'),
      headers: _sbHeaders,
      body: jsonEncode({'p_phone': local, 'p_code': code.trim(), 'p_new_password': newPassword}),
    );
    return res.statusCode == 200 && jsonDecode(res.body) == true;
  }
}
