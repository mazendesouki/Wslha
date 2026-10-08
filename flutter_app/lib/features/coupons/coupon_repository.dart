import '../../core/supabase_client.dart';

class CouponCheck {
  final bool valid;
  final double discountAmount;
  final String message;
  const CouponCheck({required this.valid, required this.discountAmount, required this.message});
}

/// coupons/coupon_redemptions carry no direct grants (db/security-75) —
/// same reasoning as accounts/wallets: a readable coupons table would let
/// anyone dump every promo code. The only client-side call is the preview
/// below (validate_coupon — read-only, no wallet side effect). Redemption
/// itself is NOT triggered from here anymore: the applied code is stored
/// on the ride row at booking time (RideRepository.createRide's
/// couponCode) and a server-side trigger credits the wallet only once the
/// ride actually reaches status='completed' (db/security-120) — booking
/// then cancelling can't farm free cashback this way.
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
}
