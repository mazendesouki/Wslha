// wallet_screen.dart's loyalty-points card + redeem sheet (db/security-
// 110-loyalty-points.sql). Kept as its own file per the established
// parallel-batch pattern (see i18n.dart's merge comment).
const Map<String, Map<String, String>> batchQStrings = {
  'wallet_loyalty_title': {'ar': '⭐ نقاط الولاء', 'en': '⭐ Loyalty points'},
  'wallet_loyalty_points_unit': {'ar': 'نقطة', 'en': 'points'},
  'wallet_loyalty_redeem_button': {'ar': 'استبدال', 'en': 'Redeem'},
  'wallet_loyalty_available_prefix': {'ar': 'متاح:', 'en': 'Available:'},
  'wallet_redeem_sheet_title': {'ar': '⭐ استبدال نقط الولاء', 'en': '⭐ Redeem loyalty points'},
  'wallet_redeem_points_label': {'ar': 'عدد النقط', 'en': 'Number of points'},
  'wallet_redeem_button': {'ar': 'استبدل برصيد المحفظة', 'en': 'Redeem for wallet credit'},
  'wallet_redeem_invalid_error': {'ar': 'عدد النقط غير صحيح', 'en': 'Invalid points amount'},
  'wallet_redeem_success_prefix': {'ar': '✅ تم تحويل', 'en': '✅ Credited'},
  'wallet_redeem_success_suffix': {'ar': 'ج.م لمحفظتك', 'en': 'EGP to your wallet'},
};
