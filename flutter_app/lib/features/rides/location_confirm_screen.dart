import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import 'places_service.dart';

/// Precise-pin confirmation — Google's Places Autocomplete/Details can only
/// return a broad area's *centroid* for a general suggestion (a
/// neighborhood/district name, not a specific address or business), which
/// can be genuinely far from where the customer actually is within that
/// area. Reported live: a booked ride's distance/fare came out wrong
/// exactly because of this. Shown after every autocomplete pick (see
/// address_field.dart's _select()) so the customer can drag the map to
/// their real spot before it's used for anything — same "confirm your
/// pin" pattern Uber/Careem use, instead of trusting the raw suggestion's
/// coordinates outright.
class LocationConfirmScreen extends StatefulWidget {
  final PlaceResult initial;
  const LocationConfirmScreen({super.key, required this.initial});

  @override
  State<LocationConfirmScreen> createState() => _LocationConfirmScreenState();
}

class _LocationConfirmScreenState extends State<LocationConfirmScreen> {
  final _places = PlacesService();
  GoogleMapController? _mapController;
  late LatLng _center = LatLng(widget.initial.lat, widget.initial.lng);
  late String _label = widget.initial.name;
  bool _resolving = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  void _onCameraMove(CameraPosition position) {
    _center = position.target;
  }

  void _onCameraIdle() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      setState(() => _resolving = true);
      final name = await _places.reverseGeocode(_center.latitude, _center.longitude);
      if (!mounted) return;
      setState(() {
        _label = name;
        _resolving = false;
      });
    });
  }

  void _confirm() {
    Navigator.of(context).pop(PlaceResult(_label, _center.latitude, _center.longitude));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('location_confirm_title'))),
      body: Stack(
        alignment: Alignment.center,
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _center, zoom: 17),
            onMapCreated: (c) => _mapController = c,
            onCameraMove: _onCameraMove,
            onCameraIdle: _onCameraIdle,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
          ),
          // Fixed pin in the exact screen center — the map pans underneath
          // it, so whatever sits under the pin IS the point being picked.
          IgnorePointer(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 36),
              child: Icon(Icons.location_pin, color: AppColors.error, size: 44),
            ),
          ),
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Material(
              color: context.surfaceColor,
              borderRadius: BorderRadius.circular(12),
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: AppColors.textFaint),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.tr('location_confirm_hint'),
                        style: const TextStyle(fontSize: 11.5, color: AppColors.textFaint, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Material(
              color: context.surfaceColor,
              borderRadius: BorderRadius.circular(16),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        _resolving
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.place_outlined, size: 18, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _label,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: _resolving ? null : _confirm,
                      child: Text(context.tr('location_confirm_button')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
