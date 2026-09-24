import 'package:flutter/material.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import 'driver_repository.dart';

/// "سجل الرحلات" — dispatch offers that expired without an answer, most
/// often because the driver's device lost internet right when the offer
/// came in while they were still toggled "متصل" (see
/// db/security-92/93-driver-missed-requests-and-cash-reminders.sql). A
/// driver can manually recover one that's still genuinely unassigned —
/// no 30s countdown, works even while currently offline, since this is a
/// deliberate manual pull rather than a live dispatch push.
class TripLogScreen extends StatefulWidget {
  final String driverPhone;
  final String driverName;
  const TripLogScreen({super.key, required this.driverPhone, required this.driverName});

  @override
  State<TripLogScreen> createState() => _TripLogScreenState();
}

class _TripLogScreenState extends State<TripLogScreen> {
  final _repo = DriverRepository();
  late Future<List<MissedRequest>> _future;
  // True once any item here was actually accepted — driver_home_screen.dart
  // uses this to know it should re-check for a newly active job.
  bool _acceptedSomething = false;

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
    // canPop: false + manually popping with _acceptedSomething inside
    // onPopInvokedWithResult makes this the result for EVERY way the
    // screen can close — the AppBar's default back button, Android's
    // system back gesture/button — not just an explicit in-app button.
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop(_acceptedSomething);
      },
      child: Scaffold(
        backgroundColor: context.mutedSurface,
        appBar: AppBar(title: Text(context.tr('trip_log_appbar_title'))),
        body: SafeArea(
          top: false,
          child: RefreshIndicator(
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
                itemBuilder: (context, i) => _MissedRequestCard(
                  repo: _repo,
                  item: items[i],
                  driverPhone: widget.driverPhone,
                  driverName: widget.driverName,
                  onAccepted: () {
                    _acceptedSomething = true;
                    _refresh();
                  },
                  onDismissed: _refresh,
                ),
              );
            },
          ),
        ),
        ),
      ),
    );
  }
}

class _MissedRequestCard extends StatefulWidget {
  final DriverRepository repo;
  final MissedRequest item;
  final String driverPhone;
  final String driverName;
  final VoidCallback onAccepted;
  final VoidCallback onDismissed;
  const _MissedRequestCard({
    required this.repo,
    required this.item,
    required this.driverPhone,
    required this.driverName,
    required this.onAccepted,
    required this.onDismissed,
  });

  @override
  State<_MissedRequestCard> createState() => _MissedRequestCardState();
}

class _MissedRequestCardState extends State<_MissedRequestCard> {
  bool _busy = false;

  String _errorMessage(BuildContext context, String reason) {
    switch (reason) {
      case 'already_taken':
        return context.tr('trip_log_error_already_taken');
      case 'vehicle_category_mismatch':
      case 'quality_tier_mismatch':
        return context.tr('trip_log_error_mismatch');
      default:
        return context.tr('trip_log_error_generic');
    }
  }

  Future<void> _accept() async {
    setState(() => _busy = true);
    final error = await widget.repo.acceptMissedRequest(widget.item.id, widget.driverPhone, widget.driverName);
    if (!mounted) return;
    setState(() => _busy = false);
    if (error == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('trip_log_accept_success'))));
      widget.onAccepted();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_errorMessage(context, error))));
      widget.onDismissed(); // stale/taken — refresh so still_available updates
    }
  }

  Future<void> _dismiss() async {
    setState(() => _busy = true);
    await widget.repo.dismissMissedRequest(widget.item.id, widget.driverPhone);
    if (!mounted) return;
    widget.onDismissed();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
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
          if (item.stillAvailable) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : _dismiss,
                    child: Text(context.tr('trip_log_dismiss_button')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _accept,
                    child: _busy
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(context.tr('trip_log_accept_button')),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
