import 'package:flutter/material.dart';
import '../../core/date_format_ar.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../airport/airport_fare.dart' show qualityLabels;
import 'airport_ride_detail_screen.dart';
import 'driver_repository.dart';

/// Open airport-ride requests as a persistent browsable list — same shape
/// as NegotiationScreen (Realtime stream, no countdown), instead of the
/// single 30-second dispatch_offers card a driver otherwise only sees one
/// of at a time. See db/security-65-airport-ride-requests.sql.
class AirportRideRequestsScreen extends StatefulWidget {
  final UserSession session;
  const AirportRideRequestsScreen({super.key, required this.session});

  @override
  State<AirportRideRequestsScreen> createState() => _AirportRideRequestsScreenState();
}

class _AirportRideRequestsScreenState extends State<AirportRideRequestsScreen> {
  final _repo = DriverRepository();
  Set<String>? _rejectedIds;

  @override
  void initState() {
    super.initState();
    _loadRejected();
  }

  Future<void> _loadRejected() async {
    final ids = await _repo.fetchRejectedAirportRideIds(widget.session.phone);
    if (mounted) setState(() => _rejectedIds = ids);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF9),
      appBar: AppBar(title: const Text('✈️ طلبات توصيل المطار')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _repo.watchOpenAirportRides(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || _rejectedIds == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final rides = snapshot.data!
              .where((r) =>
                  r['status'] == 'pending' &&
                  (r['driver_phone'] == null || (r['driver_phone'] as String).isEmpty) &&
                  !_rejectedIds!.contains(r['id'].toString()))
              .toList();

          if (rides.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'مفيش طلبات توصيل مطار مفتوحة دلوقتي — هتظهر هنا أول ما عميل يحجز',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textFaint, fontWeight: FontWeight.w700),
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rides.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) => _AirportRideCard(
              ride: rides[i],
              onRejected: (id) => setState(() => _rejectedIds = {..._rejectedIds!, id}),
              session: widget.session,
            ),
          );
        },
      ),
    );
  }
}

class _AirportRideCard extends StatelessWidget {
  final Map<String, dynamic> ride;
  final UserSession session;
  final ValueChanged<String> onRejected;
  const _AirportRideCard({required this.ride, required this.session, required this.onRejected});

  @override
  Widget build(BuildContext context) {
    final direction = ride['airport_direction'] as String? ?? 'departure';
    final rawFlightTime = ride['flight_time'];
    final flightTime = rawFlightTime == null ? null : DateTime.tryParse(rawFlightTime.toString())?.toLocal();
    final distanceKm = (ride['distance_km'] as num?)?.toStringAsFixed(1);
    final etaMinutes = ride['eta_minutes'];
    final fare = ride['fare'];
    final qualityTier = ride['airport_quality_tier'] as String?;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AirportRideDetailScreen(ride: ride, session: session, onRejected: onRejected),
        )),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE9ECEB)),
            boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 2))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                    child: Text(direction == 'departure' ? '🛫' : '🛬', style: const TextStyle(fontSize: 18)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${ride['from_area'] ?? '—'} ← ${ride['to_area'] ?? '—'}',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (flightTime != null)
                          Text(arDateTime(flightTime), style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
                      ],
                    ),
                  ),
                  if (fare != null) Text('$fare ج.م', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.primary)),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (distanceKm != null) _chip('📏 $distanceKm كم'),
                  if (etaMinutes != null) _chip('🕐 $etaMinutes د'),
                  if (qualityTier != null && qualityTier != 'regular')
                    _chip('${qualityLabels[qualityTier] ?? qualityTier} مطلوبة', warn: true),
                ],
              ),
              const SizedBox(height: 4),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('اضغط لعرض كل تفاصيل الرحلة', style: TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, {bool warn = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: warn ? const Color(0xFFFFEDD5) : AppColors.primaryLight,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: warn ? const Color(0xFFB45309) : AppColors.primary),
      ),
    );
  }
}
