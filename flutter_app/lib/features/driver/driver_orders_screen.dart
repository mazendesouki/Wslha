import 'package:flutter/material.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../orders/orders_repository.dart';
import '../rides/ride_tracking_screen.dart';

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

/// Same combined orders+rides feed as the customer's OrdersScreen, filtered
/// by driver_phone instead of customer_phone (fetchDriverHistory). Adds a
/// kind filter (رحلات/توصيل) and a period filter (اليوم/الأسبوع/الشهر) with
/// a totals summary card on top — driver-dashboard.astro's إحصائيات tab
/// (get_driver_trip_stats) covers rides-only lifetime breakdowns server-side;
/// this is the lighter client-side equivalent that also includes delivery
/// orders and short time windows, computed from the same already-fetched list.
class DriverOrdersScreen extends StatefulWidget {
  const DriverOrdersScreen({super.key});

  @override
  State<DriverOrdersScreen> createState() => _DriverOrdersScreenState();
}

class _DriverOrdersScreenState extends State<DriverOrdersScreen> {
  final _repo = OrdersRepository();
  List<HistoryItem>? _items;
  bool _loading = true;
  String? _error;
  String _kindFilter = 'all'; // 'all' | 'ride' | 'order'
  String _periodFilter = 'all'; // 'all' | 'today' | 'week' | 'month'

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
      final items = await _repo.fetchDriverHistory(session.phone);
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
    switch (_periodFilter) {
      case 'today':
        return date.year == now.year && date.month == now.month && date.day == now.day;
      case 'week':
        return now.difference(date).inDays < 7;
      case 'month':
        return date.year == now.year && date.month == now.month;
      default:
        return true;
    }
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
    final filtered = byKind?.where((it) => _withinPeriod(it.createdAt)).toList();

    num totalEarn = 0;
    int completedCount = 0;
    if (filtered != null) {
      for (final it in filtered) {
        if (_completedStatuses.contains(it.status)) {
          totalEarn += it.total;
          completedCount++;
        }
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('طلباتي ورحلاتي')),
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
          if (filtered != null && filtered.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _summaryStat('$completedCount', 'رحلة/طلب مكتمل'),
                    Container(width: 1, height: 32, color: Colors.white24),
                    _summaryStat('${totalEarn.toStringAsFixed(0)} ج.م', 'إجمالي المبالغ'),
                  ],
                ),
              ),
            ),
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
                                  _kindFilter == 'all'
                                      ? 'لسه مفيش طلبات أو رحلات في الفترة دي'
                                      : _kindFilter == 'ride'
                                          ? 'لسه مفيش رحلات في الفترة دي'
                                          : 'لسه مفيش توصيل في الفترة دي',
                                  style: const TextStyle(color: AppColors.textFaint),
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
                                  borderRadius: BorderRadius.circular(14),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: isRide
                                        ? () => Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) => RideTrackingScreen(rideId: item.id, isDriverView: true),
                                              ),
                                            )
                                        : null,
                                    child: Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(14),
                                        boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 2))],
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(item.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                                                const SizedBox(height: 4),
                                                Text(item.subtitle, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
                                              ],
                                            ),
                                          ),
                                          Text('${item.total} ج.م', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppColors.primary)),
                                          if (isRide) ...[
                                            const SizedBox(width: 4),
                                            const Icon(Icons.chevron_left, color: AppColors.textFaint, size: 18),
                                          ],
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
}
