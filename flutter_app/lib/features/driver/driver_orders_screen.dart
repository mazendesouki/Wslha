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

/// Same combined orders+rides feed as the customer's OrdersScreen, filtered
/// by driver_phone instead of customer_phone (fetchDriverHistory).
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
  String _filter = 'all'; // 'all' | 'ride' | 'order'

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

  Widget _filterChip(String value, String label) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: selected ? Colors.white : AppColors.textFaint)),
        selected: selected,
        selectedColor: AppColors.primary,
        backgroundColor: Colors.white,
        onSelected: (_) => setState(() => _filter = value),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _items == null
        ? null
        : (_filter == 'all' ? _items! : _items!.where((it) => it.kind == _filter).toList());

    return Scaffold(
      appBar: AppBar(title: const Text('طلباتي ورحلاتي')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                _filterChip('all', '📋 الكل'),
                _filterChip('ride', '🚗 رحلات'),
                _filterChip('order', '🛵 توصيل'),
              ],
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
                                  _filter == 'all'
                                      ? 'لسه مفيش طلبات أو رحلات مكتملة'
                                      : _filter == 'ride'
                                          ? 'لسه مفيش رحلات مكتملة'
                                          : 'لسه مفيش توصيل مكتمل',
                                  style: const TextStyle(color: AppColors.textFaint),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.all(16),
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
}
