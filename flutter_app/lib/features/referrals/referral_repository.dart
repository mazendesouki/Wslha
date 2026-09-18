import '../../core/supabase_client.dart';

/// referral_code lives on accounts (db/security-69), assigned automatically
/// on account creation; redemption is a one-time-per-account, security
/// definer RPC that credits both sides' wallets.
class ReferralRepository {
  Future<String?> getMyCode(String phone) async {
    final result = await sb.rpc('get_my_referral_code', params: {'p_phone': phone});
    return result as String?;
  }

  /// true = redeemed successfully (both wallets credited), false = invalid
  /// code, self-redemption, or this account already redeemed one before.
  Future<bool> redeem(String phone, String code) async {
    final result = await sb.rpc('redeem_referral_code', params: {'p_phone': phone, 'p_code': code});
    return result == true;
  }
}
