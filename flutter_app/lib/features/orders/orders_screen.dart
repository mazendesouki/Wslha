import 'package:flutter/material.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../rides/ride_tracking_screen.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('طلباتي ومشاويري')),
      body: _loading
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
                        const SizedBox(height: 8),
                        // TEMPORARY — confirms this exact build is running,
                        // to rule out a stale-install caching issue.
                        const Text('build-marker: orders-fix-v2', style: TextStyle(fontSize: 9, color: AppColors.textFaint)),
                        const SizedBox(height: 16),
                        OutlinedButton(onPressed: _load, child: const Text('إعادة المحاولة')),
                      ],
                    ),
                  ),
                )
              : (_items == null || _items!.isEmpty)
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text('📦', style: TextStyle(fontSize: 48)),
                      SizedBox(height: 12),
                      Text('لا يوجد طلبات أو مشاوير سابقة بعد', style: TextStyle(color: AppColors.textFaint)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _items!.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final item = _items![i];
                      final color = _statusColor[item.status] ?? AppColors.textFaint;
                      final isRide = item.kind == 'ride';
                      return Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: isRide
                              ? () => Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => RideTrackingScreen(rideId: item.id)),
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
    );
  }

  String _formatDate(DateTime d) {
    final local = d.toLocal();
    return '${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')} — ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
