import 'package:flutter/material.dart';
import '../../core/date_format_ar.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../airport/airport_fare.dart' show categoryLabels, qualityLabels;
import 'active_job_store.dart';
import 'driver_repository.dart';

/// Full details of one open airport ride, reached by tapping a card in
/// AirportRideRequestsScreen — trip route, passenger, distance, flight
/// date/time, requested vehicle/service tier, every line the customer
/// entered, and the total fare, with real Accept/Reject buttons (unlike
/// the negotiation flow, which has no reject and no separate detail
/// screen at all). See db/security-65-airport-ride-requests.sql.
class AirportRideDetailScreen extends StatefulWidget {
  final Map<String, dynamic> ride;
  final UserSession session;
  final ValueChanged<String> onRejected;
  const AirportRideDetailScreen({super.key, required this.ride, required this.session, required this.onRejected});

  @override
  State<AirportRideDetailScreen> createState() => _AirportRideDetailScreenState();
}

class _AirportRideDetailScreenState extends State<AirportRideDetailScreen> {
  final _repo = DriverRepository();
  bool _busy = false;

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    final rideId = widget.ride['id'].toString();
    try {
      final result = await _repo.acceptAirportRide(rideId, widget.session.phone, widget.session.name);
      if (!mounted) return;
      if (result != 'ok') {
        setState(() => _busy = false);
        _showError(
          result == 'vehicle_category_mismatch'
              ? context.tr('airport_ride_detail_err_category_mismatch')
              : result == 'quality_tier_mismatch'
                  ? context.tr('airport_ride_detail_err_quality_mismatch')
                  : context.tr('airport_ride_detail_err_already_taken'),
        );
        return;
      }
      final data = {...widget.ride, 'status': 'accepted'};
      final jobs = ActiveJobStore.instance;
      if (jobs.job == null) {
        jobs.activate('ride', data, rideStep: 'accepted');
      } else {
        jobs.enqueue(QueuedJob('ride', data));
      }
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showError(context.tr('airport_ride_detail_err_accept_failed'));
    }
  }

  Future<void> _reject() async {
    if (_busy) return;
    setState(() => _busy = true);
    final rideId = widget.ride['id'].toString();
    try {
      await _repo.rejectAirportRide(rideId, widget.session.phone);
      widget.onRejected(rideId);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showError(context.tr('airport_ride_detail_err_reject_failed'));
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: AppColors.error));
  }

  @override
  Widget build(BuildContext context) {
    final ride = widget.ride;
    final direction = ride['airport_direction'] as String? ?? 'departure';
    final tripType = ride['airport_trip_type'] as String? ?? 'international';
    final rawFlightTime = ride['flight_time'];
    final flightTime = rawFlightTime == null ? null : DateTime.tryParse(rawFlightTime.toString())?.toLocal();
    final category = ride['airport_vehicle_category'] as String?;
    final qualityTier = ride['airport_quality_tier'] as String?;
    final notes = (ride['notes'] as String?) ?? '';
    final lines = notes.split(' — ').where((l) => l.trim().isNotEmpty).toList();

    return Scaffold(
      backgroundColor: context.mutedSurface,
      appBar: AppBar(title: Text(context.tr('airport_ride_detail_appbar_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
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
                Text(
                  direction == 'departure' ? context.tr('airport_ride_detail_banner_departure') : context.tr('airport_ride_detail_banner_arrival'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  tripType == 'international' ? context.tr('airport_ride_detail_trip_international') : context.tr('airport_ride_detail_trip_domestic'),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 10),
                Text('${ride['from_area'] ?? '—'} ← ${ride['to_area'] ?? '—'}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _sectionCard(context.tr('airport_ride_detail_section_passenger'), [
            _row(context.tr('airport_ride_detail_row_name'), '${ride['customer_name'] ?? '—'}'),
            _row(context.tr('airport_ride_detail_row_phone'), '${ride['customer_phone'] ?? '—'}'),
            _row(context.tr('airport_ride_detail_row_passengers'), '${ride['passengers'] ?? 1}'),
          ]),
          const SizedBox(height: 12),
          _sectionCard(context.tr('airport_ride_detail_section_distance'), [
            if (ride['distance_km'] != null) _row(context.tr('airport_ride_detail_row_distance'), '${(ride['distance_km'] as num).toStringAsFixed(1)} كم'),
            if (ride['eta_minutes'] != null) _row(context.tr('airport_ride_detail_row_eta'), '${ride['eta_minutes']} دقيقة'),
          ]),
          const SizedBox(height: 12),
          if (flightTime != null)
            _sectionCard(context.tr('airport_ride_detail_section_datetime'), [
              _row(direction == 'departure' ? context.tr('airport_ride_detail_row_departure_time') : context.tr('airport_ride_detail_row_arrival_time'), arDateTime(flightTime), bold: true),
            ]),
          const SizedBox(height: 12),
          _sectionCard(context.tr('airport_ride_detail_section_vehicle'), [
            if (category != null) _row(context.tr('airport_ride_detail_row_vehicle_type'), categoryLabels[category] ?? category),
            _row(context.tr('airport_ride_detail_row_service_level'), qualityLabels[qualityTier ?? 'regular'] ?? context.tr('airport_ride_detail_quality_regular')),
          ]),
          if (lines.isNotEmpty) ...[
            const SizedBox(height: 12),
            _sectionCard(context.tr('airport_ride_detail_section_extra'), [
              for (final l in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(l, style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
                ),
            ]),
          ],
          const SizedBox(height: 12),
          _sectionCard(context.tr('airport_ride_detail_section_price'), [
            _row(context.tr('airport_ride_detail_row_total'), '${ride['fare'] ?? 0} ج.م', bold: true),
          ]),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _reject,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.error),
                    foregroundColor: AppColors.error,
                  ),
                  child: Text(context.tr('airport_ride_detail_btn_reject')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _busy ? null : _accept,
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: _busy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(context.tr('airport_ride_detail_btn_accept')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionCard(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE9ECEB)),
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
}
