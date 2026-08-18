import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Interactive live map — pickup/dropoff pins plus a driver marker that
/// glides between successive GPS pings instead of snapping, so the
/// customer can actually see the car approaching (the practical
/// equivalent of a "3D moving car" animation without a custom 3D engine).
/// Replaces the old static-image route preview wherever the ride/order is
/// actively being driven.
class LiveTrackingMap extends StatefulWidget {
  final LatLng? driverPosition;
  final double? driverHeading;
  final LatLng origin;
  final LatLng destination;
  const LiveTrackingMap({
    super.key,
    required this.driverPosition,
    this.driverHeading,
    required this.origin,
    required this.destination,
  });

  @override
  State<LiveTrackingMap> createState() => _LiveTrackingMapState();
}

class _LiveTrackingMapState extends State<LiveTrackingMap> with SingleTickerProviderStateMixin {
  GoogleMapController? _map;
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 2500))
    ..addListener(_onTick);
  LatLng? _from;
  LatLng? _to;
  LatLng? _shown;
  bool _fitted = false;

  @override
  void initState() {
    super.initState();
    _shown = widget.driverPosition;
    _to = widget.driverPosition;
  }

  @override
  void didUpdateWidget(covariant LiveTrackingMap old) {
    super.didUpdateWidget(old);
    final next = widget.driverPosition;
    if (next != null && (next.latitude != _to?.latitude || next.longitude != _to?.longitude)) {
      _from = _shown ?? next;
      _to = next;
      _anim
        ..reset()
        ..forward();
    }
  }

  void _onTick() {
    if (_from == null || _to == null) return;
    final t = Curves.easeInOut.transform(_anim.value);
    setState(() {
      _shown = LatLng(
        _from!.latitude + (_to!.latitude - _from!.latitude) * t,
        _from!.longitude + (_to!.longitude - _from!.longitude) * t,
      );
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  LatLngBounds _boundsFor(List<LatLng> points) {
    double minLat = points.first.latitude, maxLat = points.first.latitude;
    double minLng = points.first.longitude, maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng));
  }

  @override
  Widget build(BuildContext context) {
    final driver = _shown;
    final markers = <Marker>{
      Marker(markerId: const MarkerId('origin'), position: widget.origin, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen)),
      Marker(markerId: const MarkerId('destination'), position: widget.destination, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed)),
      if (driver != null)
        Marker(
          markerId: const MarkerId('driver'),
          position: driver,
          rotation: widget.driverHeading ?? 0,
          anchor: const Offset(0.5, 0.5),
          flat: true,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ),
    };

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 260,
        child: GoogleMap(
          initialCameraPosition: CameraPosition(target: driver ?? widget.origin, zoom: 14),
          markers: markers,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          onMapCreated: (c) {
            _map = c;
            _fitToMarkers(driver);
          },
        ),
      ),
    );
  }

  void _fitToMarkers(LatLng? driver) {
    if (_fitted) return;
    _fitted = true;
    final points = [widget.origin, widget.destination, if (driver != null) driver];
    Future.delayed(const Duration(milliseconds: 300), () {
      _map?.animateCamera(CameraUpdate.newLatLngBounds(_boundsFor(points), 60));
    });
  }
}
