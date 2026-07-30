import 'package:flutter/material.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = await SessionStore.load();
    if (session == null) {
      setState(() => _loading = false);
      return;
    }
    final items = await _repo.fetchHistory(session.phone);
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('طلباتي ومشاويري')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
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
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
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
                          ],
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
