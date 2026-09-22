import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/phone_utils.dart';
import '../../core/session.dart';
import '../../core/supabase_client.dart';

/// Phase 1 of the real-auth migration (see db/security-88) — Supabase Auth's
/// own phone-OTP flow (Twilio Verify), kept alongside the existing
/// password-based AuthRepository rather than replacing it yet. A verified
/// OTP puts a cryptographically-signed phone claim in the user's JWT
/// (auth.jwt()->>'phone'), which link_or_create_account() reads server-side
/// — never a client-supplied parameter, so it can't be spoofed the way
/// every other phone-taking RPC in this app still can be.
class OtpAuthRepository {
  Future<void> sendCode(String phoneInput) async {
    final intl = toIntlEgyptianPhone(phoneInput);
    await sb.auth.signInWithOtp(phone: intl);
  }

  /// Verifies the code, then links (or creates) the matching `accounts`
  /// row and returns it as a UserSession — same shape the old
  /// password-login flow produces, so the rest of the app (SessionStore,
  /// every screen that reads UserSession) needs no changes for this to
  /// work end to end.
  Future<UserSession> verifyCode(String phoneInput, String code, {String? name}) async {
    final intl = toIntlEgyptianPhone(phoneInput);
    final res = await sb.auth.verifyOTP(phone: intl, token: code.trim(), type: OtpType.sms);
    if (res.session == null) {
      throw Exception('تعذّر التحقق — تأكد من الكود وحاول تاني');
    }
    final row = await sb.rpc('link_or_create_account', params: {'p_name': name}) as Map<String, dynamic>;
    return UserSession(
      name: row['name'] as String? ?? '',
      phone: row['phone'] as String,
      role: row['role'] as String? ?? 'customer',
      city: row['city'] as String?,
      loginAt: DateTime.now().toIso8601String(),
    );
  }
}
