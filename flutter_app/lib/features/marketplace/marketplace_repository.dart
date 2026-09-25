import '../../core/supabase_client.dart';
import 'marketplace_models.dart';

/// سوق المستعمل — same `marketplace_items`/`marketplace_orders` tables and
/// `request_marketplace_delivery` RPC the web app uses (src/utils/
/// marketplaceApi.ts). Reading marketplace_items directly is safe (same
/// trust model as `stores`/`products` — public listings, no PII beyond a
/// contact phone the seller chose to publish).
class MarketplaceRepository {
  Future<List<MarketItem>> fetchItems({String? category, String? search}) async {
    var query = sb.from('marketplace_items').select().eq('status', 'active');
    if (category != null && category != 'all') query = query.eq('category', category);
    final rows = await query.order('created_at', ascending: false).limit(200);
    var items = (rows as List).map((r) => MarketItem.fromRow(r as Map<String, dynamic>)).toList();
    if (search != null && search.trim().isNotEmpty) {
      final q = search.trim().toLowerCase();
      items = items.where((i) => i.title.toLowerCase().contains(q) || (i.description ?? '').toLowerCase().contains(q)).toList();
    }
    return items;
  }

  Future<MarketItem?> fetchItem(String id) async {
    final rows = await sb.from('marketplace_items').select().eq('id', id).limit(1);
    if ((rows as List).isEmpty) return null;
    return MarketItem.fromRow(rows.first as Map<String, dynamic>);
  }

  /// Best-effort, non-critical — silently ignore failures (views isn't
  /// security-sensitive), same as the web's incrementViews().
  Future<void> incrementViews(String id, int currentViews) async {
    try {
      await sb.from('marketplace_items').update({'views': currentViews + 1}).eq('id', id);
    } catch (_) {}
  }

  Future<bool> requestDelivery({
    required String itemId,
    required String buyerPhone,
    required String buyerName,
    required String buyerAddress,
    String? shipmentType,
  }) async {
    try {
      await sb.rpc('request_marketplace_delivery', params: {
        'p_item_id': itemId,
        'p_buyer_phone': buyerPhone,
        'p_buyer_name': buyerName,
        'p_buyer_address': buyerAddress,
        'p_shipment_type': shipmentType,
      });
      return true;
    } catch (_) {
      return false;
    }
  }
}
