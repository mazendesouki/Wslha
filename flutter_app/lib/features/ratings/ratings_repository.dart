import '../../core/supabase_client.dart';

/// Emoji scale replacing plain stars — same 1-5 value underneath (the
/// `ratings.rating`/`store_rating`/`driver_rating` columns are unchanged),
/// just presented as a mood instead of a star count.
const List<String> ratingEmojis = ['😞', '🙁', '😐', '🙂', '😍'];
const List<String> ratingLabels = ['سيء جدًا', 'سيء', 'عادي', 'جيد', 'ممتاز'];

const List<String> positiveDriverTags = ['🚗 سواق مهذب', '⏱️ وصل بسرعة', '🧼 عربية نضيفة', '🗺️ عارف الطريق كويس'];
const List<String> negativeDriverTags = ['🐢 تأخر في الوصول', '😕 تعامل غير لائق', '🚗 العربية مش نضيفة', '🗺️ مش عارف الطريق'];
const List<String> positiveCustomerTags = ['⏱️ كان جاهز في الموعد', '📍 وصف واضح للمكان', '😊 تعامل محترم'];
const List<String> negativeCustomerTags = ['⏳ اتأخر كتير في الاستعداد', '📍 مكان غير واضح', '😕 تعامل غير لائق'];
const List<String> positiveStoreTags = ['🍽️ جودة ممتازة', '⏱️ تجهيز سريع', '📦 تغليف جيد'];
const List<String> negativeStoreTags = ['🐢 تجهيز بطيء', '😕 جودة أقل من المتوقع', '📦 تغليف سيء'];

class RatingSummary {
  final double avg;
  final int count;
  RatingSummary(this.avg, this.count);

  bool get isTrusted => count >= 5 && avg >= 4.5;
  bool get isNew => count == 0;
}

/// Driver level tiers — purely a function of how many customer ratings
/// they've accumulated, per the profile screen's "المستوى على حسب عدد
/// التقييم" requirement (deliberately not tied to the average score, so a
/// driver's level only ever grows, never drops from a single bad rating).
class DriverLevel {
  final String emoji;
  final String label;
  final int minCount;
  const DriverLevel(this.emoji, this.label, this.minCount);
}

const List<DriverLevel> driverLevels = [
  DriverLevel('🌱', 'سائق جديد', 0),
  DriverLevel('🥉', 'سائق برونزي', 50),
  DriverLevel('🥈', 'سائق فضي', 100),
  DriverLevel('🥇', 'سائق ذهبي', 150),
  DriverLevel('💎', 'سائق ماسي', 200),
];

DriverLevel levelForRatingCount(int count) {
  var current = driverLevels.first;
  for (final lvl in driverLevels) {
    if (count >= lvl.minCount) current = lvl;
  }
  return current;
}

/// Ratings needed to reach the next tier, or null if already at the top.
DriverLevel? nextLevelFor(int count) {
  for (final lvl in driverLevels) {
    if (count < lvl.minCount) return lvl;
  }
  return null;
}

/// Same `ratings` table + `update_store_rating` RPC the web app
/// (rides.astro / driver-dashboard.astro / track.astro) already reads and
/// writes directly via the anon key — this mirrors those exact REST calls
/// instead of adding new RPCs, since the table is already anon-readable/
/// writable in production (confirmed by the web code doing so).
class RatingsRepository {
  Future<void> rateDriver({
    required String rideId,
    required String driverPhone,
    required String customerPhone,
    required int rating,
    List<String>? tags,
    String? comment,
  }) async {
    await sb.from('ratings').insert({
      'driver_phone': driverPhone,
      'customer_phone': customerPhone,
      'rating': rating,
      'comment': comment,
      'service_type': 'ride',
      'ride_id': rideId,
      'rated_by': 'customer',
      if (tags != null && tags.isNotEmpty) 'tags': tags,
    });
  }

  Future<void> rateCustomer({
    required String driverPhone,
    required String customerPhone,
    required int rating,
    required String serviceType, // 'ride' | 'order'
    required String referenceId,
    List<String>? tags,
    String? comment,
  }) async {
    await sb.from('ratings').insert({
      'driver_phone': driverPhone,
      'customer_phone': customerPhone,
      'rating': rating,
      'comment': comment,
      'service_type': serviceType,
      'ride_id': referenceId,
      'rated_by': 'driver',
      if (tags != null && tags.isNotEmpty) 'tags': tags,
    });
  }

  Future<void> rateOrder({
    required String orderCode,
    required String storeId,
    String? driverPhone,
    required int storeRating,
    int? driverRating,
    List<String>? tags,
    String? comment,
  }) async {
    await sb.from('ratings').insert({
      'order_code': orderCode,
      'store_id': storeId,
      'driver_phone': driverPhone,
      'store_rating': storeRating,
      'driver_rating': driverRating,
      'comment': comment,
      if (tags != null && tags.isNotEmpty) 'tags': tags,
    });
    try {
      await sb.rpc('update_store_rating', params: {'p_store_id': storeId, 'p_new_rating': storeRating});
    } catch (_) {
      // Same best-effort handling as track.astro — the raw rating row above
      // is already saved either way, this only keeps stores.rating's cached
      // average in sync.
    }
  }

  Future<bool> hasRatedRide(String rideId) async {
    final rows = await sb.from('ratings').select('id').eq('ride_id', rideId).eq('rated_by', 'customer').limit(1);
    return rows.isNotEmpty;
  }

  Future<bool> hasRatedOrder(String orderCode) async {
    final rows = await sb.from('ratings').select('id').eq('order_code', orderCode).limit(1);
    return rows.isNotEmpty;
  }

  Future<bool> hasDriverRated(String serviceType, String referenceId) async {
    final rows = await sb
        .from('ratings')
        .select('id')
        .eq('ride_id', referenceId)
        .eq('rated_by', 'driver')
        .limit(1);
    return rows.isNotEmpty;
  }

  /// Reviews the customer themselves wrote about drivers (rated_by='customer',
  /// the same rows rateDriver() inserts) — for "سجل تقييماتي" on the
  /// customer's own account screen. Order/store ratings aren't included:
  /// rateOrder() doesn't store customer_phone on the row, so there's no way
  /// to tie those back to a specific customer yet.
  Future<List<Map<String, dynamic>>> customerGivenReviews(String customerPhone, {int limit = 30}) async {
    final rows = await sb
        .from('ratings')
        .select('id,rating,comment,tags,created_at,driver_phone')
        .eq('customer_phone', customerPhone)
        .eq('rated_by', 'customer')
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<RatingSummary> driverTrustBadge(String driverPhone) async {
    final rows = await sb.from('ratings').select('rating').eq('driver_phone', driverPhone).eq('rated_by', 'customer');
    return _summarize(rows, 'rating');
  }

  /// Individual customer reviews for the driver's own profile screen (not
  /// just the avg/count driverTrustBadge gives) — same columns
  /// driver-dashboard.astro's ratings-list reads (driver-dashboard.astro:2136),
  /// including driver_reply which exists on the live table but isn't tracked
  /// in db/*.sql (see security-24-ratings-plus.sql's header comment).
  Future<List<Map<String, dynamic>>> driverReviews(String driverPhone, {int limit = 20}) async {
    final rows = await sb
        .from('ratings')
        .select('id,rating,comment,service_type,tags,created_at,driver_reply')
        .eq('driver_phone', driverPhone)
        .eq('rated_by', 'customer')
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Individual reviews (rating + text comment/tags) a driver left ABOUT
  /// this customer after a ride — "التقييمات/الملاحظات اللي وصلتني من
  /// السائق" on the customer's own account screen. Distinct from
  /// customerGivenReviews() above, which is the reverse direction (reviews
  /// the customer wrote about drivers).
  Future<List<Map<String, dynamic>>> driverGivenReviews(String customerPhone, {int limit = 30}) async {
    final rows = await sb
        .from('ratings')
        .select('id,rating,comment,tags,created_at,driver_phone,service_type')
        .eq('customer_phone', customerPhone)
        .eq('rated_by', 'driver')
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// The "customer reliability" card a driver sees before accepting — same
  /// data driver-dashboard.astro's loadCustomerReputation() already shows,
  /// just surfaced earlier (in the offer card) instead of after accepting.
  Future<RatingSummary> customerReliability(String customerPhone) async {
    final rows = await sb.from('ratings').select('rating').eq('customer_phone', customerPhone).eq('rated_by', 'driver');
    return _summarize(rows, 'rating');
  }

  Future<RatingSummary> storeTrustBadge(String storeId) async {
    final rows = await sb.from('ratings').select('store_rating').eq('store_id', storeId).not('store_rating', 'is', null);
    return _summarize(rows, 'store_rating');
  }

  RatingSummary _summarize(List<dynamic> rows, String key) {
    final nums = rows.map((r) => (r[key] as num?)?.toDouble()).whereType<double>().toList();
    if (nums.isEmpty) return RatingSummary(0, 0);
    return RatingSummary(nums.reduce((a, b) => a + b) / nums.length, nums.length);
  }

  /// "أفضل الأصناف تقييمًا" — no per-item rating exists (customers only
  /// rate the whole order), so this is an honest proxy: which item names
  /// show up most often in orders whose overall store rating was 4-5.
  Future<List<MapEntry<String, int>>> storeTopItems(String storeId, {int limit = 3}) async {
    final goodCodes = await sb.from('ratings').select('order_code').eq('store_id', storeId).gte('store_rating', 4).limit(300);
    final codes = goodCodes.map((r) => r['order_code'] as String?).whereType<String>().toSet();
    if (codes.isEmpty) return [];

    final orders = await sb.from('orders').select('code,items').eq('store_id', storeId).inFilter('code', codes.toList());
    final counts = <String, int>{};
    for (final o in orders) {
      final items = o['items'];
      if (items is! List) continue;
      for (final it in items) {
        if (it is! Map) continue;
        final name = it['name'] as String?;
        final qty = (it['qty'] as num?)?.toInt() ?? 1;
        if (name == null || name.isEmpty) continue;
        counts[name] = (counts[name] ?? 0) + qty;
      }
    }
    final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(limit).toList();
  }
}
