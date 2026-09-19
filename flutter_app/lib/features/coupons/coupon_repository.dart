import '../../core/supabase_client.dart';

class CouponCheck {
  final bool valid;
  final double discountAmount;
  final String message;
  const CouponCheck({required this.valid, required this.discountAmount, required this.message});
}

/// coupons/coupon_redemptions carry no direct grants (db/security-75) —
/// same reasoning as accounts/wallets: a readable coupons table would let
/// anyone dump every promo code. Every check/use goes through validate_coupon
/// (preview only) / redeem_coupon (records the use + credits the wallet).
class CouponRepository {
  Future<CouponCheck> validate({
    required String code,
    required String phone,
    required double amount,
    required String serviceType, // 'ride' | 'delivery'
  }) async {
    final rows = await sb.rpc('validate_coupon', params: {
      'p_code': code,
      'p_phone': phone,
      'p_amount': amount,
      'p_service_type': serviceType,
    });
    final row = (rows as List).cast<Map<String, dynamic>>().first;
    return CouponCheck(
      valid: row['valid'] as bool,
      discountAmount: (row['discount_amount'] as num?)?.toDouble() ?? 0,
      message: row['message'] as String? ?? '',
    );
  }

  /// Called once the ride/order the coupon applies to actually exists —
  /// records the redemption and immediately credits the discount to the
  /// customer's wallet (see security-75's doc comment for why a wallet
  /// credit, not a fare reduction, is the safe way to apply this).
  Future<double> redeem({
    required String code,
    required String phone,
    required double amount,
    required String serviceType,
    required String referenceId,
  }) async {
    final result = await sb.rpc('redeem_coupon', params: {
      'p_code': code,
      'p_phone': phone,
      'p_amount': amount,
      'p_service_type': serviceType,
      'p_reference_id': referenceId,
    });
    return (result as num?)?.toDouble() ?? 0;
  }
}
