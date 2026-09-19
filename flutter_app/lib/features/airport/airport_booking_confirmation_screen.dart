import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/date_format_ar.dart';
import '../../core/i18n.dart';
import '../../core/notifications.dart';
import '../../core/theme.dart';
import '../rides/ride_tracking_screen.dart';
import 'airport_fare.dart' as fare;

/// Shown right after a successful airport booking instead of a bare
/// "check the الطلبات tab" SnackBar — the customer previously had no way
/// to see everything they just entered in one place, a real payment
/// breakdown, or a live countdown to the flight/pickup. All the display
/// data is passed straight from AirportScreen's own state (the exact
/// values just submitted) rather than re-parsing them back out of the
/// `notes` text column.
class AirportBookingConfirmationScreen extends StatefulWidget {
  final String rideId;
  final String direction; // departure | arrival
  final String tripType; // international | domestic
  final DateTime flightTime;
  final int driveMinutes;
  final String fromName;
  final String airportName;
  final String address;
  final String vehicleLabel;
  final String qualityLabel;
  final int passengers;
  final int companions;
  final int bags;
  final String airline;
  final String flightNo;
  final String terminal;
  final String flightCountry;
  final int baseFare;
  final int extraBagsFee;
  final int companionsFee;
  final int waitPickupFee;
  final int waitAirportFee;
  final int total;

  const AirportBookingConfirmationScreen({
    super.key,
    required this.rideId,
    required this.direction,
    required this.tripType,
    required this.flightTime,
    required this.driveMinutes,
    required this.fromName,
    required this.airportName,
    required this.address,
    required this.vehicleLabel,
    required this.qualityLabel,
    required this.passengers,
    required this.companions,
    required this.bags,
    required this.airline,
    required this.flightNo,
    required this.terminal,
    required this.flightCountry,
    required this.baseFare,
    required this.extraBagsFee,
    required this.companionsFee,
    required this.waitPickupFee,
    required this.waitAirportFee,
    required this.total,
  });

  @override
  State<AirportBookingConfirmationScreen> createState() => _AirportBookingConfirmationScreenState();
}

class _AirportBookingConfirmationScreenState extends State<AirportBookingConfirmationScreen> {
  Timer? _ticker;
  late final List<fare.TimelineStep> _steps;

  @override
  void initState() {
    super.initState();
    _steps = fare.buildTimeline(
      direction: widget.direction,
      tripType: widget.tripType,
      flightTime: widget.flightTime,
      driveMinutes: widget.driveMinutes,
    );
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _scheduleReminders();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _scheduleReminders() {
    final pickupStep = _steps.first;
    final idBase = widget.rideId.hashCode;
    AppNotifications.instance.scheduleAt(
      idBase,
      widget.direction == 'departure' ? context.tr('airport_confirm_notif_driver_enroute_pickup') : context.tr('airport_confirm_notif_driver_enroute_airport'),
      '${context.tr('airport_confirm_notif_body_prefix')}${pickupStep.label}${context.tr('airport_confirm_notif_body_suffix')}',
      pickupStep.time.subtract(const Duration(minutes: 15)),
    );
    AppNotifications.instance.scheduleAt(
      idBase + 1,
      context.tr('airport_confirm_notif_flight_soon_title'),
      widget.direction == 'departure' ? context.tr('airport_confirm_notif_flight_soon_departure') : context.tr('airport_confirm_notif_flight_soon_arrival'),
      widget.flightTime.subtract(const Duration(minutes: 45)),
    );
  }

  String _fmtDuration(Duration d) {
    if (d.isNegative) return context.tr('airport_confirm_time_arrived');
    final days = d.inDays;
    final hours = d.inHours % 24;
    final minutes = d.inMinutes % 60;
    if (days > 0) return '$days${context.tr('airport_confirm_days_and_hours')}$hours${context.tr('airport_confirm_hours_unit')}';
    if (hours > 0) return '$hours${context.tr('airport_confirm_hours_and_minutes')}$minutes دقيقة';
    return '$minutes دقيقة';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.mutedSurface,
      appBar: AppBar(title: Text(context.tr('airport_confirm_appbar_title'))),
      body: Column(
        children: [
          Expanded(child: _content()),
          _bottomBar(context),
        ],
      ),
    );
  }

  Widget _content() {
    final now = DateTime.now();
    final nextStep = _steps.firstWhere((s) => s.time.isAfter(now), orElse: () => _steps.last);
    final flightRemaining = widget.flightTime.difference(now);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.primaryDark, AppColors.primary]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('airport_confirm_banner_title'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
                const SizedBox(height: 10),
                Text('${widget.fromName} ← ${widget.airportName}', style: const TextStyle(color: Colors.white70, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 14),
                _CountdownTile(label: '${context.tr('airport_confirm_time_remaining_prefix')}${widget.direction == 'departure' ? context.tr('airport_confirm_word_departure') : context.tr('airport_confirm_word_arrival')}', value: _fmtDuration(flightRemaining)),
                const SizedBox(height: 8),
                _CountdownTile(label: nextStep.label, value: _fmtDuration(nextStep.time.difference(now))),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _sectionCard(
            title: context.tr('airport_confirm_section_trip_details'),
            children: [
              _row(context.tr('airport_confirm_row_direction'), widget.direction == 'departure' ? context.tr('airport_confirm_direction_departing') : context.tr('airport_confirm_direction_arriving')),
              _row(context.tr('airport_confirm_row_trip_type'), widget.tripType == 'international' ? context.tr('airport_confirm_trip_international') : context.tr('airport_confirm_trip_domestic')),
              _row(
                widget.direction == 'departure' ? context.tr('airport_confirm_row_datetime_departure') : context.tr('airport_confirm_row_datetime_arrival'),
                arDateTime(widget.flightTime),
                bold: true,
              ),
              _row(context.tr('airport_confirm_row_vehicle'), widget.vehicleLabel),
              if (widget.qualityLabel.isNotEmpty) _row(context.tr('airport_confirm_row_service_level'), widget.qualityLabel),
              _row(context.tr('airport_confirm_row_passengers'), '${widget.passengers}'),
              if (widget.companions > 0) _row(context.tr('airport_confirm_row_companions'), '${widget.companions}'),
              if (widget.bags > 0) _row(context.tr('airport_confirm_row_bags'), '${widget.bags}'),
              if (widget.address.isNotEmpty) _row(context.tr('airport_confirm_row_pickup_address'), widget.address),
              if (widget.airline.isNotEmpty) _row(context.tr('airport_confirm_row_airline'), widget.airline),
              if (widget.flightNo.isNotEmpty) _row(context.tr('airport_confirm_row_flight_no'), widget.flightNo),
              if (widget.terminal.isNotEmpty) _row(context.tr('airport_confirm_row_terminal'), widget.terminal),
              if (widget.flightCountry.isNotEmpty) _row(widget.direction == 'departure' ? context.tr('airport_confirm_row_traveling_to') : context.tr('airport_confirm_row_coming_from'), widget.flightCountry),
            ],
          ),
          const SizedBox(height: 16),
          _sectionCard(
            title: context.tr('airport_confirm_section_timeline'),
            children: [
              for (final step in _steps) _timelineRow(step, isNext: step == nextStep),
            ],
          ),
          const SizedBox(height: 16),
          _sectionCard(
            title: context.tr('airport_confirm_section_payment'),
            children: [
              _row(context.tr('airport_confirm_row_distance_fare'), '${widget.baseFare} ج.م'),
              if (widget.extraBagsFee > 0) _row(context.tr('airport_confirm_row_extra_bags_fee'), '${widget.extraBagsFee} ج.م'),
              if (widget.companionsFee > 0) _row(context.tr('airport_confirm_row_companion_fee'), '${widget.companionsFee} ج.م'),
              if (widget.waitPickupFee > 0) _row(context.tr('airport_confirm_row_wait_pickup_fee'), '${widget.waitPickupFee} ج.م'),
              if (widget.waitAirportFee > 0) _row(context.tr('airport_confirm_row_wait_airport_fee'), '${widget.waitAirportFee} ج.م'),
              const Divider(height: 20),
              _row(context.tr('airport_confirm_row_total'), '${widget.total} ج.م', bold: true),
              const SizedBox(height: 4),
              Text(context.tr('airport_confirm_payment_cash_note'), style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
            ],
          ),
        ],
    );
  }

  Widget _bottomBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: context.surfaceColor, border: Border(top: BorderSide(color: context.borderColor))),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                child: Text(context.tr('airport_confirm_btn_home')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => RideTrackingScreen(rideId: widget.rideId)),
                ),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                child: Text(context.tr('airport_confirm_btn_track')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({required String title, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: bold ? 14 : 12, fontWeight: bold ? FontWeight.w900 : FontWeight.w600, color: bold ? Colors.black : AppColors.textFaint)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(fontSize: bold ? 15 : 13, fontWeight: FontWeight.w800, color: bold ? AppColors.primary : Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timelineRow(fare.TimelineStep step, {required bool isNext}) {
    final timeStr = arTime(step.time);
    final passed = step.time.isBefore(DateTime.now());
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isNext ? AppColors.accent : (passed ? AppColors.textFaint : AppColors.primary),
            ),
            alignment: Alignment.center,
            child: Text(step.icon, style: const TextStyle(fontSize: 11)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.label, style: TextStyle(fontWeight: isNext ? FontWeight.w900 : FontWeight.w700, fontSize: 12)),
                if (step.sub.isNotEmpty) Text(step.sub, style: const TextStyle(fontSize: 10, color: AppColors.textFaint)),
              ],
            ),
          ),
          Text(timeStr, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: isNext ? AppColors.accent : Colors.black87)),
        ],
      ),
    );
  }
}

class _CountdownTile extends StatelessWidget {
  final String label;
  final String value;
  const _CountdownTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12))),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
        ],
      ),
    );
  }
}
