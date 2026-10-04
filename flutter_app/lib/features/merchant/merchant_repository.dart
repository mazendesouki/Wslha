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

  /// Past orders only (delivered/rejected) for the dedicated history
  /// screen — same table/columns as getOrders, just a wider limit since
  /// this is a deliberate "browse the past" view rather than the live
  /// kitchen board.
  Future<List<Map<String, dynamic>>> getOrderHistory(String storeId, {int limit = 200}) async {
    final rows = await sb
        .from('orders')
        .select()
        .eq('store_id', storeId)
        .inFilter('status', ['delivered', 'rejected'])
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows);
  }

  // merchant_accept_order/merchant_reject_order (security-48) verify the
  // caller's phone actually owns this order's store server-side — a raw
  // table UPDATE would let anyone accept/reject any store's orders.
  Future<void> acceptOrder(String orderId, String merchantPhone, {int? prepMinutes}) async {
    await sb.rpc('merchant_accept_order', params: {
      'p_order_id': orderId,
      'p_merchant_phone': merchantPhone,
      'p_prep_minutes': ?prepMinutes,
    });
  }

  Future<void> rejectOrder(String orderId, String merchantPhone) async {
    await sb.rpc('merchant_reject_order', params: {
      'p_order_id': orderId,
      'p_merchant_phone': merchantPhone,
    });
  }

  /// Store-profile self-edit — `stores` is open for direct update except
  /// `owner_phone` (locked server-side, see db/security-47-lockdown-
  /// accounts-stores.sql), same "hard-to-guess id = trust" model the rest
  /// of this app's open tables use. Scoped to the merchant's own store id,
  /// which the caller already only ever has for their own store.
  Future<void> updateStoreInfo(
    String storeId, {
    String? name,
    String? tagline,
    bool? isOpen,
    num? deliveryFee,
    num? minOrder,
  }) async {
    final patch = <String, dynamic>{
      if (name != null) 'name': name,
      if (tagline != null) 'tagline': tagline,
      if (isOpen != null) 'is_open': isOpen,
      if (deliveryFee != null) 'delivery_fee': deliveryFee,
      if (minOrder != null) 'min_order': minOrder,
    };
    if (patch.isEmpty) return;
    await sb.from('stores').update(patch).eq('id', storeId);
  }
}
