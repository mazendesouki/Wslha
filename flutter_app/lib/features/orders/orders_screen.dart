import 'package:flutter/material.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../rides/ride_tracking_screen.dart';
import 'order_invoice_screen.dart';
import 'orders_repository.dart';

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

const _completedStatuses = {'delivered', 'completed'};
const _cancelledStatuses = {'cancelled', 'rejected'};

/// Same combined orders+rides feed as the driver's DriverOrdersScreen, just
/// filtered by customer_phone (fetchHistory) instead of driver_phone —
/// mirrors the same kind/period filters, status breakdown (مكتملة/ملغاة/
/// قيد التنفيذ) and type breakdown (توصيل/داخلي/خارجي/مطار), so both
/// apps read as the same product.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final _repo = OrdersRepository();
  List<HistoryItem>? _items;
  bool _loading = true;
  String? _error;
  String _kindFilter = 'all'; // 'all' | 'ride' | 'order'
  String _periodFilter = 'all'; // 'all' | 'today' | 'week' | 'month'
  String _statusFilter = 'all'; // 'all' | 'completed' | 'cancelled' | 'active'
  String _typeFilter = 'all'; // 'all' | 'order' | 'local' | 'external' | 'airport'

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final session = await SessionStore.load();
    if (session == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final items = await _repo.fetchHistory(session.phone);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  bool _withinPeriod(DateTime? date) {
    if (_periodFilter == 'all') return true;
    if (date == null) return false;
    final now = DateTime.now();
    // created_at comes back from Supabase as UTC — comparing its raw
    // year/month/day against DateTime.now() (local) misclassifies "اليوم"
    // near midnight (an order from 1am Cairo time is still "yesterday"
    // in UTC), silently dropping today's real items from the filter.
    final local = date.toLocal();
    switch (_periodFilter) {
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

  String _itemStatusBucket(HistoryItem it) {
    if (_completedStatuses.contains(it.status)) return 'completed';
    if (_cancelledStatuses.contains(it.status)) return 'cancelled';
    return 'active';
  }

  String _itemTypeBucket(HistoryItem it) {
    if (it.kind == 'order') return 'order';
    return it.rideType ?? 'local';
  }

  void _toggleStatusFilter(String value) {
    setState(() => _statusFilter = _statusFilter == value ? 'all' : value);
  }

  void _toggleTypeFilter(String value) {
    setState(() => _typeFilter = _typeFilter == value ? 'all' : value);
  }

  Widget _chip(String value, String label, String groupValue, ValueChanged<String> onSelect) {
    final selected = value == groupValue;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: selected ? Colors.white : AppColors.textFaint)),
        selected: selected,
        selectedColor: AppColors.primary,
        backgroundColor: Colors.white,
        onSelected: (_) => onSelect(value),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final byKind = _items == null
        ? null
        : (_kindFilter == 'all' ? _items! : _items!.where((it) => it.kind == _kindFilter).toList());
    // Stats (status/type tiles) are computed on this — kind+period only, so
    // the counts stay stable while a status/type tile is selected.
    final statsBase = byKind?.where((it) => _withinPeriod(it.createdAt)).toList();
    // The visible list additionally honors the status/type tile selection.
    final filtered = statsBase
        ?.where((it) => _statusFilter == 'all' || _itemStatusBucket(it) == _statusFilter)
        .where((it) => _typeFilter == 'all' || _itemTypeBucket(it) == _typeFilter)
        .toList();

    // Overall + status breakdown
    num totalSpent = 0;
    int completedCount = 0;
    int cancelledCount = 0;
    num cancelledTotal = 0;
    int activeCount = 0;
    num activeTotal = 0;
    // Type breakdown
    int deliveryCount = 0;
    int localCount = 0;
    int externalCount = 0;
    int airportCount = 0;

    if (statsBase != null) {
      for (final it in statsBase) {
        if (_completedStatuses.contains(it.status)) {
          totalSpent += it.total;
          completedCount++;
        } else if (_cancelledStatuses.contains(it.status)) {
          cancelledCount++;
          cancelledTotal += it.total;
        } else {
          activeCount++;
          activeTotal += it.total;
        }

        if (it.kind == 'order') {
          deliveryCount++;
        } else {
          switch (it.rideType) {
            case 'external':
              externalCount++;
            case 'airport':
              airportCount++;
            default:
              localCount++;
          }
        }
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF9),
      appBar: AppBar(title: const Text('طلباتي ومشاويري')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _chip('all', '📋 الكل', _kindFilter, (v) => setState(() => _kindFilter = v)),
                  _chip('ride', '🚗 رحلات', _kindFilter, (v) => setState(() => _kindFilter = v)),
                  _chip('order', '🛵 توصيل', _kindFilter, (v) => setState(() => _kindFilter = v)),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _chip('today', '📅 اليوم', _periodFilter, (v) => setState(() => _periodFilter = v)),
                  _chip('week', '🗓️ الأسبوع', _periodFilter, (v) => setState(() => _periodFilter = v)),
                  _chip('month', '📆 الشهر', _periodFilter, (v) => setState(() => _periodFilter = v)),
                  _chip('all', '⏳ كل الوقت', _periodFilter, (v) => setState(() => _periodFilter = v)),
                ],
              ),
            ),
          ),
          if (statsBase != null && statsBase.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, Color(0xFF0E4D3D)],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _summaryStat('$completedCount', 'رحلة/طلب مكتمل'),
                    Container(width: 1, height: 32, color: Colors.white24),
                    _summaryStat('${totalSpent.toStringAsFixed(0)} ج.م', 'إجمالي المبالغ'),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Row(
                children: [
                  Expanded(
                    child: _statusTile('✅', 'مكتملة', completedCount, totalSpent, AppColors.success,
                        selected: _statusFilter == 'completed', onTap: () => _toggleStatusFilter('completed')),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _statusTile('❌', 'ملغاة', cancelledCount, cancelledTotal, AppColors.error,
                        selected: _statusFilter == 'cancelled', onTap: () => _toggleStatusFilter('cancelled')),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _statusTile('⏳', 'قيد التنفيذ', activeCount, activeTotal, AppColors.accent,
                        selected: _statusFilter == 'active', onTap: () => _toggleStatusFilter('active')),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _typeTile('🛵', 'توصيل', deliveryCount, selected: _typeFilter == 'order', onTap: () => _toggleTypeFilter('order')),
                    const SizedBox(width: 8),
                    _typeTile('🚗', 'داخلي', localCount, selected: _typeFilter == 'local', onTap: () => _toggleTypeFilter('local')),
                    const SizedBox(width: 8),
                    _typeTile('🛣️', 'خارجي', externalCount, selected: _typeFilter == 'external', onTap: () => _toggleTypeFilter('external')),
                    const SizedBox(width: 8),
                    _typeTile('✈️', 'مطار', airportCount, selected: _typeFilter == 'airport', onTap: () => _toggleTypeFilter('airport')),
                  ],
                ),
              ),
            ),
          ],
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('⚠️', style: TextStyle(fontSize: 40)),
                              const SizedBox(height: 12),
                              Text(_error!, style: const TextStyle(fontSize: 11, color: AppColors.error), textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              OutlinedButton(onPressed: _load, child: const Text('إعادة المحاولة')),
                            ],
                          ),
                        ),
                      )
                    : (filtered == null || filtered.isEmpty)
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('📦', style: TextStyle(fontSize: 48)),
                                const SizedBox(height: 12),
                                Text(
                                  _statusFilter != 'all' || _typeFilter != 'all'
                                      ? 'مفيش نتائج للتصنيف المحدد — جرّب تشيل الفلتر'
                                      : _kindFilter == 'all'
                                          ? 'لا يوجد طلبات أو مشاوير سابقة بعد'
                                          : _kindFilter == 'ride'
                                              ? 'لسه مفيش رحلات في الفترة دي'
                                              : 'لسه مفيش توصيل في الفترة دي',
                                  style: const TextStyle(color: AppColors.textFaint),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              itemCount: filtered.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 10),
                              itemBuilder: (context, i) {
                                final item = filtered[i];
                                final color = _statusColor[item.status] ?? AppColors.textFaint;
                                final isRide = item.kind == 'ride';
                                return Material(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => isRide
                                            ? RideTrackingScreen(rideId: item.id)
                                            : OrderInvoiceScreen(orderId: item.id),
                                      ),
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 2))],
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 42,
                                            height: 42,
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              color: (isRide ? AppColors.primary : AppColors.accent).withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(13),
                                            ),
                                            child: Text(isRide ? '🚖' : '📦', style: const TextStyle(fontSize: 19)),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(item.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                                                    const SizedBox(width: 5),
                                                    Text(item.subtitle, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
                                                  ],
                                                ),
                                                if (item.createdAt != null) ...[
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    _formatDate(item.createdAt!),
                                                    style: const TextStyle(fontSize: 10, color: AppColors.textFaint),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          Text('${item.total} ج.م', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppColors.primary)),
                                          const SizedBox(width: 4),
                                          const Icon(Icons.chevron_left, color: AppColors.textFaint, size: 18),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _summaryStat(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _statusTile(String emoji, String label, int count, num total, Color color,
      {bool selected = false, VoidCallback? onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.12) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: selected ? 0.9 : 0.25), width: selected ? 1.6 : 1),
          ),
          child: Column(
            children: [
              Text('$emoji $count', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: color)),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textFaint, fontWeight: FontWeight.w700)),
              Text('${total.toStringAsFixed(0)} ج.م', style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeTile(String emoji, String label, int count, {bool selected = false, VoidCallback? onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary.withValues(alpha: 0.1) : Colors.white,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: selected ? AppColors.primary : const Color(0xFFE5E7EB), width: selected ? 1.6 : 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Text(
                '$label ($count)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: selected ? AppColors.primary : AppColors.textFaint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    final local = d.toLocal();
    return '${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')} — ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
