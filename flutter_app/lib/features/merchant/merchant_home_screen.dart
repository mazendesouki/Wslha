import 'package:flutter/material.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../shared/widgets/logout_button.dart';
import 'merchant_repository.dart';

const Map<String, String> _statusAr = {
  'pending': 'بانتظار موافقتك',
  'preparing': 'قيد التجهيز',
  'on_the_way': 'في الطريق',
  'delivered': 'تم التسليم',
  'rejected': 'مرفوض',
};

class MerchantHomeScreen extends StatefulWidget {
  final UserSession session;
  const MerchantHomeScreen({super.key, required this.session});

  @override
  State<MerchantHomeScreen> createState() => _MerchantHomeScreenState();
}

class _MerchantHomeScreenState extends State<MerchantHomeScreen> {
  final _repo = MerchantRepository();
  Map<String, dynamic>? _store;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _repo.getStoreForOwner(widget.session.phone).then((store) {
      if (!mounted) return;
      setState(() {
        _store = store;
        _loading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_store == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('وصّلها تاجر'), actions: const [LogoutButton()]),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('لا يوجد متجر مرتبط بحسابك بعد.', textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final storeId = _store!['id'].toString();

    return Scaffold(
      appBar: AppBar(
        title: Text(_store!['name'] as String? ?? 'وصّلها تاجر'),
        actions: const [LogoutButton()],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _repo.watchOrders(storeId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final orders = snapshot.data!;
          final pending = orders.where((o) => o['status'] == 'pending').toList();
          final active = orders.where((o) => ['preparing', 'on_the_way'].contains(o['status'])).toList();
          final history = orders.where((o) => ['delivered', 'rejected'].contains(o['status'])).toList();

          if (orders.isEmpty) {
            return const Center(child: Text('لا توجد طلبات بعد', style: TextStyle(color: AppColors.textFaint)));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (pending.isNotEmpty) ..._section('طلبات جديدة', pending, showActions: true),
              if (active.isNotEmpty) ..._section('قيد التنفيذ', active),
              if (history.isNotEmpty) ..._section('السجل', history),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _section(String title, List<Map<String, dynamic>> orders, {bool showActions = false}) {
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 8),
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
      ),
      ...orders.map((o) => _OrderCard(
            order: o,
            showActions: showActions,
            onAccept: () => _repo.acceptOrder(o['id'].toString()),
            onReject: () => _repo.rejectOrder(o['id'].toString()),
          )),
    ];
  }
}

class _OrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final bool showActions;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _OrderCard({required this.order, required this.showActions, required this.onAccept, required this.onReject});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(order['customer_name'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(_statusAr[order['status']] ?? order['status'] as String? ?? '', style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
            ],
          ),
          const SizedBox(height: 4),
          Text(order['items_summary'] as String? ?? '', style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          Text('${order['total'] ?? ''} ج.م', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primary)),
          if (showActions) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: onReject, child: const Text('رفض'))),
                const SizedBox(width: 8),
                Expanded(child: ElevatedButton(onPressed: onAccept, child: const Text('قبول'))),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
