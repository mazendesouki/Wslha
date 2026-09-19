import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/i18n.dart';
import '../../core/notifications.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../shared/widgets/logout_button.dart';
import 'merchant_repository.dart';

const Map<String, String> _statusKeys = {
  'pending': 'merchant_home_status_pending',
  'preparing': 'merchant_home_status_preparing',
  'on_the_way': 'merchant_home_status_on_the_way',
  'delivered': 'merchant_home_status_delivered',
  'rejected': 'merchant_home_status_rejected',
};

const List<int> _prepMinuteChoices = [10, 15, 20, 30, 45];

/// Kitchen-display-style order board — cards are colored by how urgent they
/// are (age since arrival for new orders, remaining prep time for accepted
/// ones) instead of a flat list, and a genuinely-new pending order triggers
/// a strong local vibration/sound while the app is open (on top of the
/// existing FCM push for when it's backgrounded/closed — see
/// db/security-18-order-notify-merchant.sql).
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
  Timer? _ticker;
  final Set<String> _knownPendingIds = {};
  bool _firstSnapshot = true;

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
    // Re-renders every 15s purely to age the elapsed-time/countdown badges
    // forward — the StreamBuilder below only fires on real data changes,
    // which won't happen just because a minute passed on an unchanged order.
    _ticker = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _onOrdersUpdate(List<Map<String, dynamic>> orders) {
    final pendingIds = orders.where((o) => o['status'] == 'pending').map((o) => o['id'].toString()).toSet();
    if (_firstSnapshot) {
      // Don't chime for orders that already existed before this screen
      // opened — only for ones that land while it's actively watched.
      _firstSnapshot = false;
      _knownPendingIds.addAll(pendingIds);
      return;
    }
    final freshlyArrived = pendingIds.difference(_knownPendingIds);
    _knownPendingIds
      ..clear()
      ..addAll(pendingIds);
    if (freshlyArrived.isNotEmpty) {
      AppNotifications.instance.show(
        context.tr('merchant_home_new_order_notif_title'),
        context.tr('merchant_home_new_order_notif_body'),
        channelId: 'wslha_orders',
      );
    }
  }

  Future<void> _acceptWithPrepTime(String orderId) async {
    final minutes = await showModalBottomSheet<int>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.tr('merchant_home_prep_time_title'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _prepMinuteChoices
                  .map((m) => ActionChip(
                        label: Text('$m ${context.tr('merchant_home_prep_minutes_suffix')}'),
                        onPressed: () => Navigator.of(sheetContext).pop(m),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
    // Dismissed without picking a chip (tap outside, swipe down, back
    // button) still accepts the order — just without a prep-time ETA —
    // instead of silently doing nothing, which looked like a dead button.
    try {
      await _repo.acceptOrder(orderId, widget.session.phone, prepMinutes: minutes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${context.tr('merchant_home_accept_failed_prefix')} $e'), backgroundColor: AppColors.error, duration: const Duration(seconds: 6)),
      );
    }
  }

  Future<void> _reject(String orderId) async {
    try {
      await _repo.rejectOrder(orderId, widget.session.phone);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${context.tr('merchant_home_reject_failed_prefix')} $e'), backgroundColor: AppColors.error, duration: const Duration(seconds: 6)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_store == null) {
      return Scaffold(
        appBar: AppBar(title: Text(context.tr('merchant_home_title')), actions: const [LogoutButton()]),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(context.tr('merchant_home_no_store'), textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final storeId = _store!['id'].toString();

    return Scaffold(
      appBar: AppBar(
        title: Text(_store!['name'] as String? ?? context.tr('merchant_home_title')),
        actions: const [LogoutButton()],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _repo.watchOrders(storeId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final orders = snapshot.data!;
          WidgetsBinding.instance.addPostFrameCallback((_) => _onOrdersUpdate(orders));

          final pending = orders.where((o) => o['status'] == 'pending').toList();
          final active = orders.where((o) => ['preparing', 'on_the_way'].contains(o['status'])).toList();
          final history = orders.where((o) => ['delivered', 'rejected'].contains(o['status'])).toList();

          if (orders.isEmpty) {
            return Center(child: Text(context.tr('merchant_home_no_orders'), style: const TextStyle(color: AppColors.textFaint)));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (pending.isNotEmpty) ..._section(context.tr('merchant_home_section_new'), pending, showActions: true),
              if (active.isNotEmpty) ..._section(context.tr('merchant_home_section_active'), active),
              if (history.isNotEmpty) ..._section(context.tr('merchant_home_section_history'), history, muted: true),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _section(String title, List<Map<String, dynamic>> orders, {bool showActions = false, bool muted = false}) {
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 8),
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
      ),
      ...orders.map((o) => _OrderCard(
            order: o,
            showActions: showActions,
            muted: muted,
            onAccept: () => _acceptWithPrepTime(o['id'].toString()),
            onReject: () => _reject(o['id'].toString()),
          )),
    ];
  }
}

/// Urgency tier drives the card's whole color scheme — green (fine) →
/// amber (getting close) → red (needs attention now), same three-tier
/// language a kitchen-display system uses.
enum _Urgency { calm, warning, critical }

class _OrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final bool showActions;
  final bool muted;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _OrderCard({
    required this.order,
    required this.showActions,
    required this.onAccept,
    required this.onReject,
    this.muted = false,
  });

  DateTime? _parse(String? iso) => iso == null ? null : DateTime.tryParse(iso);

  @override
  Widget build(BuildContext context) {
    final status = order['status'] as String?;
    Duration? elapsed;
    Duration? remaining;
    _Urgency urgency = _Urgency.calm;
    String? badge;

    if (status == 'pending') {
      final createdAt = _parse(order['created_at'] as String?);
      if (createdAt != null) {
        elapsed = DateTime.now().difference(createdAt);
        if (elapsed >= const Duration(minutes: 5)) {
          urgency = _Urgency.critical;
        } else if (elapsed >= const Duration(minutes: 2)) {
          urgency = _Urgency.warning;
        }
        badge = elapsed.inMinutes < 1
            ? context.tr('merchant_home_order_arrived_now')
            : '${context.tr('merchant_home_order_since_prefix')} ${elapsed.inMinutes} ${context.tr('merchant_home_order_since_suffix')}';
      }
    } else if (status == 'preparing') {
      final acceptedAt = _parse(order['accepted_at'] as String?);
      final prepMinutes = (order['prep_minutes'] as num?)?.toInt();
      if (acceptedAt != null && prepMinutes != null) {
        final deadline = acceptedAt.add(Duration(minutes: prepMinutes));
        remaining = deadline.difference(DateTime.now());
        if (remaining.isNegative) {
          urgency = _Urgency.critical;
          badge = '${context.tr('merchant_home_order_overdue_prefix')} ${remaining.abs().inMinutes} ${context.tr('merchant_home_order_overdue_suffix')}';
        } else if (remaining.inMinutes <= 3) {
          urgency = _Urgency.warning;
          badge = '${context.tr('merchant_home_order_remaining_prefix')} ${remaining.inMinutes} ${context.tr('merchant_home_order_remaining_suffix')}';
        } else {
          badge = '${context.tr('merchant_home_order_remaining_prefix')} ${remaining.inMinutes} ${context.tr('merchant_home_order_remaining_suffix')}';
        }
      }
    }

    final palette = muted
        ? _Palette(bg: context.surfaceColor, border: const Color(0xFFE5E7EB), accent: AppColors.textFaint)
        : switch (urgency) {
            _Urgency.calm => const _Palette(bg: Color(0xFFF0FDF4), border: Color(0xFFBBF7D0), accent: AppColors.success),
            _Urgency.warning => const _Palette(bg: Color(0xFFFFFBEB), border: Color(0xFFFDE68A), accent: Color(0xFFB45309)),
            _Urgency.critical => const _Palette(bg: Color(0xFFFEF2F2), border: Color(0xFFFECACA), accent: AppColors.error),
          };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(order['customer_name'] as String? ?? context.tr('merchant_home_order_fallback_name'), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: palette.accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(999)),
                  child: Text(badge, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: palette.accent)),
                )
              else
                Text(
                  status != null && _statusKeys.containsKey(status) ? context.tr(_statusKeys[status]!) : (status ?? ''),
                  style: const TextStyle(fontSize: 12, color: AppColors.textFaint),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(order['items_summary'] as String? ?? '', style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          Text('${order['total'] ?? ''} ${context.tr('merchant_home_currency')}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primary)),
          if (showActions) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: onReject, child: Text(context.tr('merchant_home_reject')))),
                const SizedBox(width: 8),
                Expanded(child: ElevatedButton(onPressed: onAccept, child: Text(context.tr('merchant_home_accept')))),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Palette {
  final Color bg;
  final Color border;
  final Color accent;
  const _Palette({required this.bg, required this.border, required this.accent});
}
