import 'package:flutter/material.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import 'driver_repository.dart';

/// "سجل الرحلات" — dispatch offers that expired without an answer, most
/// often because the driver's device lost internet right when the offer
/// came in while they were still toggled "متصل" (see
/// db/security-92-driver-missed-requests-and-cash-reminders.sql). A
/// read-only history, unlike negotiation_screen.dart's live open-offers
/// stream — these are already over, there's nothing left to act on except
/// see what was missed.
class TripLogScreen extends StatefulWidget {
  final String driverPhone;
  const TripLogScreen({super.key, required this.driverPhone});

  @override
  State<TripLogScreen> createState() => _TripLogScreenState();
}

class _TripLogScreenState extends State<TripLogScreen> {
  final _repo = DriverRepository();
  late Future<List<MissedRequest>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.fetchMissedRequests(widget.driverPhone);
  }

  Future<void> _refresh() async {
    setState(() => _future = _repo.fetchMissedRequests(widget.driverPhone));
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.mutedSurface,
      appBar: AppBar(title: Text(context.tr('trip_log_appbar_title'))),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<MissedRequest>>(
          future: _future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final items = snapshot.data!;
            if (items.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 60),
                  Text(
                    context.tr('trip_log_empty'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textFaint, fontWeight: FontWeight.w700),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _MissedRequestCard(item: items[i]),
            );
          },
        ),
      ),
    );
  }
}

class _MissedRequestCard extends StatelessWidget {
  final MissedRequest item;
  const _MissedRequestCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final isRide = item.targetType == 'ride';
    final time = item.offeredAt.toLocal();
    final timeLabel = '${time.day}/${time.month} — ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(12)),
            alignment: Alignment.center,
            child: Text(isRide ? '🚖' : '📦', style: const TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isRide
                      ? '${item.fromArea ?? '—'} ← ${item.toArea ?? '—'}'
                      : (item.storeName ?? context.tr('trip_log_order_fallback_title')),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(timeLabel, style: const TextStyle(fontSize: 11, color: AppColors.textFaint, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          if (isRide && item.fare != null)
            Text('${item.fare!.toStringAsFixed(0)} ج.م', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryDark))
          else if (!isRide && item.orderTotal != null)
            Text('${item.orderTotal!.toStringAsFixed(0)} ج.م', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryDark)),
        ],
      ),
    );
  }
}
