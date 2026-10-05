import '../../core/supabase_client.dart';

/// "قيّم التطبيق" — db/security-111-app-reviews.sql. A general app-level
/// review (distinct from the existing ride/order ratings table), shown as
/// public testimonials on the marketing site once an admin approves it.
class AppReviewRepository {
  Future<void> submit(String phone, String name, int rating, String? comment) async {
    await sb.rpc('submit_app_review', params: {
      'p_phone': phone,
      'p_name': name,
      'p_rating': rating,
      'p_comment': comment,
    });
  }
}
