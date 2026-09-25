import '../../core/supabase_client.dart';
import 'promotion_models.dart';

class PromotionRepository {
  /// The one active popup for this audience ('customer'/'driver'/
  /// 'merchant'), if any — see get_active_promotion (db/security-98).
  Future<AppPromotion?> fetchActive(String target) async {
    try {
      final row = await sb.rpc('get_active_promotion', params: {'p_target': target});
      if (row == null) return null;
      final map = row as Map<String, dynamic>;
      if (map['id'] == null) return null;
      return AppPromotion.fromRow(map);
    } catch (_) {
      return null;
    }
  }
}
