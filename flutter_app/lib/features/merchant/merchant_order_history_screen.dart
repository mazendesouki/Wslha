import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import 'merchant_repository.dart';

const Map<String, String> _historyStatusKeys = {
  'delivered': 'merchant_home_status_delivered',
  'rejected': 'merchant_home_status_rejected',
};

/// "سجل الطلبات" — every past order (delivered or rejected), separate from
/// the live new/active board on MerchantHomeScreen so that board stays
/// focused on what the merchant needs to act on right now.
class MerchantOrderHistoryScreen extends StatefulWidget {
  final String storeId;
  const MerchantOrderHistoryScreen({super.key, required this.storeId});

  @override
  State<MerchantOrderHistoryScreen> createState() => _MerchantOrderHistoryScreenState();
}

class _MerchantOrderHistoryScreenState extends State<MerchantOrderHistoryScreen> {
  final _repo = MerchantRepository();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.getOrderHistory(widget.storeId);
  }

  void _refresh() => setState(() => _future = _repo.getOrderHistory(widget.storeId));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('merchant_history_appbar_title'))),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final orders = snapshot.data!;
              if (orders.isEmpty) {
                return ListView(
                  children: [
                    const SizedBox(height: 120),
                    Center(child: Text(context.tr('merchant_history_empty'), style: const TextStyle(color: AppColors.textFaint))),
                  ],
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(14),
                itemCount: orders.length,
                itemBuilder: (context, i) => _HistoryCard(order: orders[i]),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final Map<String, dynamic> order;
  const _HistoryCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final status = order['status'] as String?;
    final createdAt = DateTime.tryParse(order['created_at'] as String? ?? '')?.toLocal();
    final isRejected = status == 'rejected';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  order['customer_name'] as String? ?? context.tr('merchant_home_order_fallback_name'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                status != null && _historyStatusKeys.containsKey(status) ? context.tr(_historyStatusKeys[status]!) : (status ?? ''),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: isRejected ? AppColors.error : AppColors.success),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (order['code'] != null)
            Text(
              '${context.tr('merchant_order_number_prefix')} #${order['code']}',
              style: const TextStyle(fontSize: 11.5, color: AppColors.textFaint, fontWeight: FontWeight.w700),
            ),
          if (order['store_name'] != null)
            Text(order['store_name'] as String, style: const TextStyle(fontSize: 11.5, color: AppColors.textFaint, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(order['items_summary'] as String? ?? '', style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${order['total'] ?? ''} ${context.tr('merchant_home_currency')}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryDark)),
              if (createdAt != null)
                Text(
                  '${createdAt.day}/${createdAt.month} — ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
