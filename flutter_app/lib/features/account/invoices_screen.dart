import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/date_format_ar.dart';
import '../../core/i18n.dart';
import '../../core/phone_utils.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../airport/airport_screen.dart';
import '../orders/order_invoice_screen.dart';
import '../orders/orders_repository.dart' show statusAr;
import '../rides/places_service.dart' show PlaceResult;
import '../rides/ride_invoice_screen.dart';
import '../rides/rides_screen.dart';
import '../stores/cart_store.dart';
import '../stores/store_detail_screen.dart';
import '../stores/stores_models.dart';
import '../stores/stores_repository.dart';

const Map<String, Color> _statusColor = {
  'delivered': AppColors.success,
  'completed': AppColors.success,
  'rejected': AppColors.error,
  'cancelled': AppColors.error,
  'pending': AppColors.textFaint,
  'preparing': AppColors.accent,
  'on_the_way': AppColors.primary,
  'accepted': AppColors.primary,
  'arrived': AppColors.primary,
  'in_progress': AppColors.primary,
};

class _InvoiceRow {
  final String kind; // 'order' | 'ride' | 'airport'
  final String id;
  final String status;
  final String title;
  final String subtitle;
  final num total;
  final DateTime? createdAt;
  // Only set for kind == 'ride'/'airport' — the raw addresses/coordinates
  // needed to prefill a rebooking (see "احجز تاني" below).
  final PlaceResult? rebookFrom;
  final PlaceResult? rebookTo;
  // Only set for kind == 'order' — the store + past item quantities needed
  // to reopen that store's menu with the same items pre-added to the cart.
  final String? orderStoreId;
  final List<Map<String, dynamic>>? orderItems;
  const _InvoiceRow({
    required this.kind,
    required this.id,
    required this.status,
    required this.title,
    required this.subtitle,
    required this.total,
    required this.createdAt,
    this.rebookFrom,
    this.rebookTo,
    this.orderStoreId,
    this.orderItems,
  });
}

/// "فواتير" — a combined, REAL-TIME feed of every ride/order/airport-trip
/// invoice for this customer, reachable from حسابي. Unlike OrdersScreen
/// (which does a one-off fetch), this subscribes to live Supabase streams
/// so a status change (e.g. a driver accepting) or a brand-new invoice
/// shows up immediately without the user pulling to refresh.
///
/// supabase_flutter's .stream() only supports a single .eq() filter (no
/// .or()), while customer_phone is stored inconsistently in local
/// (01xxxxxxxxx) vs international (+201xxxxxxxxx) form across the app —
/// so this watches BOTH formats on BOTH tables (4 streams) and merges
/// them client-side, same dual-format tolerance every RPC in this app
/// already assumes.
class InvoicesScreen extends StatefulWidget {
  final String customerPhone;
  const InvoicesScreen({super.key, required this.customerPhone});

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  late final String _local = normalizeEgyptianPhone(widget.customerPhone);
  late final String _intl = toIntlEgyptianPhone(widget.customerPhone);

  List<Map<String, dynamic>> _ordersLocal = [];
  List<Map<String, dynamic>> _ordersIntl = [];
  List<Map<String, dynamic>> _ridesLocal = [];
  List<Map<String, dynamic>> _ridesIntl = [];

  final List<StreamSubscription> _subs = [];

  String _category = 'all'; // all | ride | airport | order
  String _period = 'all'; // all | today | week | month

  @override
  void initState() {
    super.initState();
    _subs.add(sb.from('orders').stream(primaryKey: ['id']).eq('customer_phone', _local).listen((rows) {
      if (mounted) setState(() => _ordersLocal = rows);
    }));
    _subs.add(sb.from('orders').stream(primaryKey: ['id']).eq('customer_phone', _intl).listen((rows) {
      if (mounted) setState(() => _ordersIntl = rows);
    }));
    _subs.add(sb.from('rides').stream(primaryKey: ['id']).eq('customer_phone', _local).listen((rows) {
      if (mounted) setState(() => _ridesLocal = rows);
    }));
    _subs.add(sb.from('rides').stream(primaryKey: ['id']).eq('customer_phone', _intl).listen((rows) {
      if (mounted) setState(() => _ridesIntl = rows);
    }));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  bool _withinPeriod(DateTime? date) {
    if (_period == 'all') return true;
    if (date == null) return false;
    final now = DateTime.now();
    final local = date.toLocal();
    switch (_period) {
      case 'today':
        return local.year == now.year && local.month == now.month && local.day == now.day;
      case 'week':
        return now.difference(local).inDays < 7;
      case 'month':
        return local.year == now.year && local.month == now.month;
      default:
        return true;
    }
  }

  List<_InvoiceRow> get _rows {
    final byId = <String, Map<String, dynamic>>{};
    for (final o in [..._ordersLocal, ..._ordersIntl]) {
      byId['order-${o['id']}'] = o;
    }
    final ridesById = <String, Map<String, dynamic>>{};
    for (final r in [..._ridesLocal, ..._ridesIntl]) {
      ridesById['ride-${r['id']}'] = r;
    }

    final rows = <_InvoiceRow>[];
    for (final o in byId.values) {
      final rawItems = o['items'];
      rows.add(_InvoiceRow(
        kind: 'order',
        id: '${o['id']}',
        status: o['status'] as String? ?? 'pending',
        title: '${context.tr('invoices_order_prefix')} ${o['store_name'] ?? context.tr('invoices_default_store')}',
        subtitle: statusAr[o['status']] ?? '${o['status']}',
        total: (o['total'] as num?) ?? 0,
        createdAt: DateTime.tryParse(o['created_at'] as String? ?? ''),
        orderStoreId: o['store_id'] as String?,
        orderItems: rawItems is List ? rawItems.whereType<Map<String, dynamic>>().toList() : null,
      ));
    }
    for (final r in ridesById.values) {
      final rideType = (r['ride_type'] as String?) ?? 'local';
      final isAirport = rideType == 'airport';
      final fromLat = (r['from_lat'] as num?)?.toDouble();
      final fromLng = (r['from_lng'] as num?)?.toDouble();
      final toLat = (r['to_lat'] as num?)?.toDouble();
      final toLng = (r['to_lng'] as num?)?.toDouble();
      rows.add(_InvoiceRow(
        kind: isAirport ? 'airport' : 'ride',
        id: '${r['id']}',
        status: r['status'] as String? ?? 'pending',
        title: isAirport ? '${context.tr('invoices_airport_prefix')} ${r['to_area'] ?? ''}' : '🚖 ${r['from_area'] ?? ''} ← ${r['to_area'] ?? ''}',
        subtitle: statusAr[r['status']] ?? '${r['status']}',
        total: (r['fare'] as num?) ?? 0,
        createdAt: DateTime.tryParse(r['created_at'] as String? ?? ''),
        rebookFrom: fromLat != null && fromLng != null ? PlaceResult(r['from_area'] as String? ?? '', fromLat, fromLng) : null,
        rebookTo: toLat != null && toLng != null ? PlaceResult(r['to_area'] as String? ?? '', toLat, toLng) : null,
      ));
    }

    rows.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
    return rows.where((r) => (_category == 'all' || r.kind == _category) && _withinPeriod(r.createdAt)).toList();
  }

  void _openInvoice(_InvoiceRow row) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => row.kind == 'order' ? OrderInvoiceScreen(orderId: row.id) : RideInvoiceScreen(rideId: row.id),
    ));
  }

  /// "احجز تاني" — reopens the booking screen with this past trip's
  /// addresses prefilled, so the customer doesn't have to retype them.
  /// Distance/fare are always recomputed fresh on the booking screen
  /// itself (never copied from the old invoice), so any pricing or traffic
  /// change since the original trip is reflected correctly.
  void _rebook(_InvoiceRow row) {
    if (row.kind == 'order') {
      _reorderDelivery(row);
      return;
    }
    if (row.rebookFrom == null || row.rebookTo == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => row.kind == 'airport'
          ? AirportScreen(initialFrom: row.rebookFrom, initialAirport: row.rebookTo)
          : RidesScreen(initialFrom: row.rebookFrom, initialTo: row.rebookTo),
    ));
  }

  /// "اطلب تاني" for a delivery order — reopens the same store with the
  /// past order's items pre-added to the cart at their old quantities.
  /// Prices/availability always come from a fresh fetchStore()/fetchProducts()
  /// call (never copied from the old invoice), so a discontinued item is
  /// simply skipped and a changed price shows the current one. Matches
  /// items by product id, not name, since a store could rename a product.
  Future<void> _reorderDelivery(_InvoiceRow row) async {
    final storeId = row.orderStoreId;
    final items = row.orderItems;
    if (storeId == null || items == null || items.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final repo = StoresRepository();
    StoreRow? store;
    List<ProductRow> products = [];
    try {
      store = await repo.fetchStore(storeId);
      if (store != null) {
        products = (await repo.fetchProducts(storeId)).where((p) => p.isAvailable).toList();
      }
    } catch (_) {
      store = null;
    }

    if (!mounted) return;
    Navigator.of(context).pop(); // dismiss the loading dialog

    if (store == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('invoices_reorder_store_unavailable'))),
      );
      return;
    }

    final cart = CartStore.instance;
    if (cart.storeId != null && cart.storeId != store.id) cart.clear();
    var missing = 0;
    for (final it in items) {
      final productId = it['id'] as String?;
      final qty = (it['qty'] as num?)?.toInt() ?? 1;
      ProductRow? product;
      for (final p in products) {
        if (p.id == productId) {
          product = p;
          break;
        }
      }
      if (product == null) {
        missing++;
        continue;
      }
      cart.setQty(store, product, qty);
    }

    if (!mounted) return;
    if (missing > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${context.tr('invoices_reorder_some_unavailable_prefix')} $missing ${context.tr('invoices_reorder_some_unavailable_suffix')}')),
      );
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => StoreDetailScreen(store: store!)));
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Scaffold(
      backgroundColor: context.mutedSurface,
      appBar: AppBar(title: Text(context.tr('invoices_title'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip('all', context.tr('invoices_filter_all'), _category, (v) => setState(() => _category = v)),
                _chip('ride', context.tr('invoices_filter_rides'), _category, (v) => setState(() => _category = v)),
                _chip('airport', context.tr('invoices_filter_airport'), _category, (v) => setState(() => _category = v)),
                _chip('order', context.tr('invoices_filter_delivery'), _category, (v) => setState(() => _category = v)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _periodChip('all', context.tr('invoices_period_all')),
                _periodChip('today', context.tr('invoices_period_today')),
                _periodChip('week', context.tr('invoices_period_week')),
                _periodChip('month', context.tr('invoices_period_month')),
              ],
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? Center(child: Text(context.tr('invoices_empty'), style: const TextStyle(color: AppColors.textFaint)))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _invoiceTile(rows[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String value, String label, String current, ValueChanged<String> onChanged) {
    final selected = current == value;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: selected ? Colors.white : AppColors.textFaint)),
      selected: selected,
      selectedColor: AppColors.primary,
      backgroundColor: context.surfaceColor,
      side: BorderSide(color: selected ? AppColors.primary : context.borderColor),
      onSelected: (_) => onChanged(value),
    );
  }

  Widget _periodChip(String value, String label) => _chip(value, label, _period, (v) => setState(() => _period = v));

  Widget _invoiceTile(_InvoiceRow row) {
    final color = _statusColor[row.status] ?? AppColors.textFaint;
    final canRebook = (row.rebookFrom != null && row.rebookTo != null) ||
        (row.orderStoreId != null && row.orderItems != null && row.orderItems!.isNotEmpty);
    return Material(
      color: context.surfaceColor,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _openInvoice(row),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: canRebook ? const BorderRadius.vertical(top: Radius.circular(14)) : BorderRadius.circular(14),
                border: Border.all(color: context.borderColor),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(row.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
                              child: Text(row.subtitle, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color)),
                            ),
                            const SizedBox(width: 8),
                            if (row.createdAt != null)
                              Text(arDateTime(row.createdAt!), style: const TextStyle(fontSize: 10, color: AppColors.textFaint)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${row.total} ج.م', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: AppColors.success)),
                  const Icon(Icons.chevron_left, color: AppColors.textFaint),
                ],
              ),
            ),
          ),
          if (canRebook)
            InkWell(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
              onTap: () => _rebook(row),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                  border: Border(
                    left: BorderSide(color: context.borderColor),
                    right: BorderSide(color: context.borderColor),
                    bottom: BorderSide(color: context.borderColor),
                    top: BorderSide(color: context.borderColor),
                  ),
                  color: AppColors.primary.withValues(alpha: 0.06),
                ),
                child: Text(
                  '🔁 ${row.kind == 'order' ? context.tr('invoices_reorder') : context.tr('invoices_rebook')}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primary),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
