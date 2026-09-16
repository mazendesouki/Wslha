import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/pricing_settings.dart';

/// Live ticking card shown to BOTH the customer and driver once the driver
/// has marked "arrived" — same arrived_at anchor, same grace/fee config
/// (PricingSettings, db/security-63), so both sides see identical numbers
/// at the same time. Before the grace period elapses it's a plain
/// countdown; once crossed, it becomes a running estimate of the fee the
/// customer would be charged if the ride started right now — the actual
/// deduction only ever happens once, server-side, the moment the driver
/// taps "ابدأ الرحلة" (driver_update_ride_status()) — this card is purely
/// visibility into that same calculation, not a separate live charge.
class WaitingTimerCard extends StatefulWidget {
  final DateTime arrivedAt;
  final bool isCustomerView;
  const WaitingTimerCard({super.key, required this.arrivedAt, required this.isCustomerView});

  @override
  State<WaitingTimerCard> createState() => _WaitingTimerCardState();
}

class _WaitingTimerCardState extends State<WaitingTimerCard> {
  late final Timer _timer;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    setState(() => _elapsed = DateTime.now().toUtc().difference(widget.arrivedAt.toUtc()));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final graceMinutes = PricingSettings.customerLateGraceMinutes;
    final feePerMinute = PricingSettings.customerLateFeePerMinute;
    final elapsedMinutes = _elapsed.inMinutes;
    final overGrace = elapsedMinutes > graceMinutes;

    if (!overGrace) {
      var remaining = Duration(minutes: graceMinutes) - _elapsed;
      if (remaining.isNegative) remaining = Duration.zero;
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          border: Border.all(color: const Color(0xFFFDE68A), width: 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Text('⏱️', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.isCustomerView
                    ? 'السائق وصل — عندك ${_fmt(remaining)} قبل ما يبدأ خصم $feePerMinute ج.م عن كل دقيقة تأخير'
                    : 'في انتظار العميل — ${_fmt(remaining)} متبقية بدون خصم عليه',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: Color(0xFF92400E)),
              ),
            ),
          ],
        ),
      );
    }

    final overMinutes = elapsedMinutes - graceMinutes;
    final estimatedFee = overMinutes * feePerMinute;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        border: Border.all(color: const Color(0xFFFCA5A5), width: 1.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Text('⏱️', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.isCustomerView
                  ? 'اتأخرت $overMinutes د — هيتخصم منك ${estimatedFee.toStringAsFixed(0)} ج.م لو الرحلة بدأت دلوقتي'
                  : 'العميل اتأخر $overMinutes د — هيتخصم منه ${estimatedFee.toStringAsFixed(0)} ج.م لو الرحلة بدأت دلوقتي',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: Color(0xFF991B1B)),
            ),
          ),
        ],
      ),
    );
  }
}
