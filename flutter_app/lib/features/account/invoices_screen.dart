import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/date_format_ar.dart';
import '../../core/phone_utils.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../orders/order_invoice_screen.dart';
import '../orders/orders_repository.dart' show statusAr;
import '../rides/ride_invoice_screen.dart';

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
  const _InvoiceRow({
    required this.kind,
    required this.id,
    required this.status,
    required this.title,
    required this.subtitle,
    required this.total,
    required this.createdAt,
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
      rows.add(_InvoiceRow(
        kind: 'order',
        id: '${o['id']}',
        status: o['status'] as String? ?? 'pending',
        title: '📦 طلب من ${o['store_name'] ?? 'المتجر'}',
        subtitle: statusAr[o['status']] ?? '${o['status']}',
        total: (o['total'] as num?) ?? 0,
        createdAt: DateTime.tryParse(o['created_at'] as String? ?? ''),
      ));
    }
    for (final r in ridesById.values) {
      final rideType = (r['ride_type'] as String?) ?? 'local';
      final isAirport = rideType == 'airport';
      rows.add(_InvoiceRow(
        kind: isAirport ? 'airport' : 'ride',
        id: '${r['id']}',
        status: r['status'] as String? ?? 'pending',
        title: isAirport ? '✈️ توصيل مطار — ${r['to_area'] ?? ''}' : '🚖 ${r['from_area'] ?? ''} ← ${r['to_area'] ?? ''}',
        subtitle: statusAr[r['status']] ?? '${r['status']}',
        total: (r['fare'] as num?) ?? 0,
        createdAt: DateTime.tryParse(r['created_at'] as String? ?? ''),
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

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF9),
      appBar: AppBar(title: const Text('🧾 فواتيري')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _chip('all', 'الكل', _category, (v) => setState(() => _category = v)),
                  _chip('ride', '🚖 رحلات', _category, (v) => setState(() => _category = v)),
                  _chip('airport', '✈️ مطار', _category, (v) => setState(() => _category = v)),
                  _chip('order', '📦 توصيل', _category, (v) => setState(() => _category = v)),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _periodChip('all', '⏳ كل الوقت'),
                  _periodChip('today', '📅 اليوم'),
                  _periodChip('week', '🗓️ الأسبوع'),
                  _periodChip('month', '📆 الشهر'),
                ],
              ),
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? const Center(child: Text('مفيش فواتير في الفترة دي', style: TextStyle(color: AppColors.textFaint)))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _invoiceTile(rows[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String value, String label, String current, ValueChanged<String> onChanged) {
    final selected = current == value;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onChanged(value)),
    );
  }

  Widget _periodChip(String value, String label) => _chip(value, label, _period, (v) => setState(() => _period = v));

  Widget _invoiceTile(_InvoiceRow row) {
    final color = _statusColor[row.status] ?? AppColors.textFaint;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openInvoice(row),
        child: Padding(
          padding: const EdgeInsets.all(14),
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
    );
  }
}
