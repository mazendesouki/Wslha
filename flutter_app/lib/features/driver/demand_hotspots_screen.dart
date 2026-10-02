import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../airport/airport_fare.dart' show damiettaLat, damiettaLng;
import 'driver_repository.dart';

/// "مناطق الطلب الساخنة" — db/security-107-demand-hotspots.sql. Shows the
/// driver where pending rides/orders are currently clustered (grid cells,
/// not exact pickup points) so they can reposition instead of just waiting
/// for a dispatch offer to arrive.
class DemandHotspotsScreen extends StatefulWidget {
  const DemandHotspotsScreen({super.key});

  @override
  State<DemandHotspotsScreen> createState() => _DemandHotspotsScreenState();
}

class _DemandHotspotsScreenState extends State<DemandHotspotsScreen> {
  final _repo = DriverRepository();
  late Future<List<({double lat, double lng, int rideCount, int orderCount, int demandCount})>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.fetchDemandHotspots();
  }

  void _refresh() {
    setState(() => _future = _repo.fetchDemandHotspots());
  }

  Color _circleColor(int demandCount, int maxDemand) {
    final t = maxDemand <= 0 ? 0.0 : (demandCount / maxDemand).clamp(0.0, 1.0);
    return Color.lerp(AppColors.accent, AppColors.error, t)!.withValues(alpha: 0.55);
  }

  double _radiusMeters(int demandCount, int maxDemand) {
    final t = maxDemand <= 0 ? 0.0 : (demandCount / maxDemand).clamp(0.0, 1.0);
    return 250 + t * 550; // 250m..800m
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('hotspots_appbar_title')),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: context.tr('hotspots_refresh_tooltip'),
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: FutureBuilder<List<({double lat, double lng, int rideCount, int orderCount, int demandCount})>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }
          if (snap.hasError) {
            return Center(child: Text(context.tr('hotspots_error'), style: const TextStyle(color: AppColors.error)));
          }
          final hotspots = snap.data ?? [];
          final maxDemand = hotspots.isEmpty ? 0 : hotspots.map((h) => h.demandCount).reduce((a, b) => a > b ? a : b);
          final circles = {
            for (final h in hotspots)
              Circle(
                circleId: CircleId('${h.lat}_${h.lng}'),
                center: LatLng(h.lat, h.lng),
                radius: _radiusMeters(h.demandCount, maxDemand),
                fillColor: _circleColor(h.demandCount, maxDemand),
                strokeColor: _circleColor(h.demandCount, maxDemand).withValues(alpha: 0.9),
                strokeWidth: 1,
              ),
          };

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  context.tr('hotspots_subtitle'),
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textFaint, fontWeight: FontWeight.w600),
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    GoogleMap(
                      initialCameraPosition: const CameraPosition(target: LatLng(damiettaLat, damiettaLng), zoom: 12.5),
                      circles: circles,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      mapToolbarEnabled: false,
                    ),
                    if (hotspots.isEmpty)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: const [
                            BoxShadow(color: Colors.black12, blurRadius: 8),
                          ]),
                          child: Text(context.tr('hotspots_empty'), style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
