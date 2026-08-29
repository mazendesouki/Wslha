import '../../core/supabase_client.dart';

/// Same stores/orders tables merchant-dashboard.astro reads/writes.
class MerchantRepository {
  Future<Map<String, dynamic>?> getStoreForOwner(String ownerPhone) async {
    final rows = await sb.from('stores').select().eq('owner_phone', ownerPhone).limit(1);
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first);
  }

  Future<List<Map<String, dynamic>>> getOrders(String storeId) async {
    final rows = await sb
        .from('orders')
        .select()
        .eq('store_id', storeId)
        .order('created_at', ascending: false)
        .limit(100);
    return List<Map<String, dynamic>>.from(rows);
  }

  Stream<List<Map<String, dynamic>>> watchOrders(String storeId) {
    return sb.from('orders').stream(primaryKey: ['id']).eq('store_id', storeId).order('created_at', ascending: false);
  }

  // merchant_accept_order/merchant_reject_order (security-48) verify the
  // caller's phone actually owns this order's store server-side — a raw
  // table UPDATE would let anyone accept/reject any store's orders.
  Future<void> acceptOrder(String orderId, String merchantPhone, {int? prepMinutes}) async {
    await sb.rpc('merchant_accept_order', params: {
      'p_order_id': orderId,
      'p_merchant_phone': merchantPhone,
      if (prepMinutes != null) 'p_prep_minutes': prepMinutes,
    });
  }

  Future<void> rejectOrder(String orderId, String merchantPhone) async {
    await sb.rpc('merchant_reject_order', params: {
      'p_order_id': orderId,
      'p_merchant_phone': merchantPhone,
    });
  }
}
