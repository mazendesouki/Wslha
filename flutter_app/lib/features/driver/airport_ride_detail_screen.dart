import 'package:flutter/material.dart';
import '../../core/date_format_ar.dart';
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
              ? 'نوع سيارتك لا يطابق نوع السيارة المطلوب لرحلة المطار دي'
              : result == 'quality_tier_mismatch'
                  ? 'سيارتك المسجّلة لا تطابق مستوى الخدمة اللي طلبه العميل (مكيّفة/نظيفة/موديل حديث)'
                  : 'الرحلة دي اتقبلت من سائق تاني قبلك',
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
      _showError('تعذّر قبول الرحلة، حاول تاني');
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
      _showError('تعذّر رفض الرحلة، حاول تاني');
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
      appBar: AppBar(title: const Text('تفاصيل رحلة المطار')),
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
                  direction == 'departure' ? '🛫 توصيل من العميل إلى المطار (مغادرة)' : '🛬 توصيل من المطار إلى العميل (وصول)',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  tripType == 'international' ? 'رحلة دولية' : 'رحلة محلية',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 10),
                Text('${ride['from_area'] ?? '—'} ← ${ride['to_area'] ?? '—'}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _sectionCard('👤 بيانات المسافر', [
            _row('الاسم', '${ride['customer_name'] ?? '—'}'),
            _row('رقم الجوال', '${ride['customer_phone'] ?? '—'}'),
            _row('عدد المسافرين', '${ride['passengers'] ?? 1}'),
          ]),
          const SizedBox(height: 12),
          _sectionCard('📍 بيانات المسافة', [
            if (ride['distance_km'] != null) _row('المسافة', '${(ride['distance_km'] as num).toStringAsFixed(1)} كم'),
            if (ride['eta_minutes'] != null) _row('الوقت المتوقع للطريق', '${ride['eta_minutes']} دقيقة'),
          ]),
          const SizedBox(height: 12),
          if (flightTime != null)
            _sectionCard('🕐 المواعيد والتواريخ', [
              _row(direction == 'departure' ? 'موعد الإقلاع' : 'موعد الهبوط', arDateTime(flightTime), bold: true),
            ]),
          const SizedBox(height: 12),
          _sectionCard('🚗 السيارة والخدمة المطلوبة', [
            if (category != null) _row('نوع السيارة', categoryLabels[category] ?? category),
            _row('مستوى الخدمة', qualityLabels[qualityTier ?? 'regular'] ?? 'عادية'),
          ]),
          if (lines.isNotEmpty) ...[
            const SizedBox(height: 12),
            _sectionCard('📋 تفاصيل إضافية', [
              for (final l in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(l, style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
                ),
            ]),
          ],
          const SizedBox(height: 12),
          _sectionCard('💳 تفاصيل السعر', [
            _row('إجمالي الرحلة', '${ride['fare'] ?? 0} ج.م', bold: true),
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
                  child: const Text('رفض'),
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
                      : const Text('قبول الرحلة'),
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
