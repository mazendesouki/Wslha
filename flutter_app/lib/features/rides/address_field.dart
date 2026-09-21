import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import 'location_confirm_screen.dart';
import 'places_service.dart';

class AddressField extends StatefulWidget {
  final String label;
  final String hint;
  final void Function(PlaceResult) onSelected;
  /// Shows a "📍 موقعي الحالي" GPS button — same button rides.astro shows
  /// on the "من" field only, not "إلى" (you don't ride to where you
  /// already are).
  final bool showLocationButton;
  /// Passed through to PlacesService.autocomplete's `types` — e.g.
  /// 'airport' for the airport picker (airport.astro's #airport-input).
  final String? placesTypes;
  /// Leading icon distinguishing this field at a glance (e.g. a start pin
  /// vs. a flag for the destination) — optional so callers that don't set
  /// one keep the plain look.
  final IconData? prefixIcon;
  /// Pre-fills both the text field and the value reported via onSelected —
  /// used by "احجز تاني" (rebook) so a reused past trip's address shows up
  /// immediately instead of an empty field the customer has to retype.
  final PlaceResult? initialValue;
  /// Shows LocationConfirmScreen's draggable-pin map after every
  /// autocomplete pick, since a broad suggestion (a neighborhood/district
  /// name) resolves to that whole area's centroid — genuinely far from the
  /// customer's real spot, and was reported live as booking a wrong
  /// distance/fare. Left true by default; off for the airport picker
  /// (placesTypes: 'airport'), which already only returns precise
  /// individual-airport points, not broad areas.
  final bool confirmOnMap;

  const AddressField({
    super.key,
    required this.label,
    required this.hint,
    required this.onSelected,
    this.showLocationButton = false,
    this.placesTypes,
    this.prefixIcon,
    this.initialValue,
    this.confirmOnMap = true,
  });

  @override
  State<AddressField> createState() => _AddressFieldState();
}

class _AddressFieldState extends State<AddressField> {
  late final _controller = TextEditingController(text: widget.initialValue?.name ?? '');
  final _places = PlacesService();
  Timer? _debounce;
  List<PlaceSuggestion> _suggestions = [];
  bool _loading = false;
  bool _locLoading = false;
  String? _locError;

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (value.trim().length < 2) {
        setState(() => _suggestions = []);
        return;
      }
      setState(() => _loading = true);
      final results = await _places.autocomplete(value, types: widget.placesTypes);
      if (!mounted) return;
      setState(() {
        _suggestions = results;
        _loading = false;
      });
      // ignore: avoid_print
      print('[AddressField] "${widget.label}" query="$value" results=${results.length} error=${_places.lastError}');
    });
  }

  Future<void> _useMyLocation() async {
    setState(() {
      _locLoading = true;
      _locError = null;
      _suggestions = [];
    });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        setState(() {
          _locLoading = false;
          _locError = context.tr('address_field_location_permission_needed');
        });
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() {
          _locLoading = false;
          _locError = context.tr('address_field_location_service_disabled');
        });
        return;
      }
      // Reported bug: the spinner span forever with no way out — a GPS fix
      // can simply never arrive (weak signal, indoors, a device/emulator
      // with no real GPS) and getCurrentPosition() has no timeout of its
      // own, so it just hangs. A bounded wait here means _locLoading always
      // gets reset one way or another.
      final pos = await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 15));
      final name = await _places.reverseGeocode(pos.latitude, pos.longitude);
      if (!mounted) return;
      _controller.text = name;
      widget.onSelected(PlaceResult(name, pos.latitude, pos.longitude));
      setState(() => _locLoading = false);
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _locLoading = false;
        _locError = context.tr('address_field_location_timeout');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _locLoading = false;
        _locError = context.tr('address_field_location_failed');
      });
    }
  }

  Future<void> _select(PlaceSuggestion s) async {
    setState(() => _suggestions = []);
    _controller.text = s.description;
    final detail = await _places.details(s.placeId);
    if (detail == null) return;
    var result = detail;
    if (widget.confirmOnMap && mounted) {
      final confirmed = await Navigator.of(context).push<PlaceResult>(
        MaterialPageRoute(builder: (_) => LocationConfirmScreen(initial: detail)),
      );
      // A null result (system back button, no explicit cancel action on
      // that screen) falls back to the raw suggestion rather than leaving
      // the field with nothing selected.
      if (confirmed != null) result = confirmed;
    }
    if (!mounted) return;
    _controller.text = result.name;
    widget.onSelected(result);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          onChanged: _onChanged,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            prefixIcon: widget.prefixIcon == null ? null : Icon(widget.prefixIcon),
            suffixIcon: _loading || _locLoading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : widget.showLocationButton
                    ? IconButton(
                        icon: const Icon(Icons.my_location, color: AppColors.primary),
                        tooltip: context.tr('address_field_use_current_location'),
                        onPressed: _useMyLocation,
                      )
                    : null,
          ),
        ),
        if (_locError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_locError!, style: const TextStyle(fontSize: 11, color: AppColors.error)),
          ),
        // TEMPORARY diagnostic — surfaces the Places API failure reason
        // directly on screen since wireless-ADB logcat has been unreliable
        // for debugging this on-device. Remove once autocomplete is confirmed
        // working end to end.
        if (!_loading && _suggestions.isEmpty && _places.lastError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _places.lastError!,
              style: const TextStyle(fontSize: 11, color: Colors.red),
            ),
          ),
        if (_suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE5E7EB)),
              borderRadius: BorderRadius.circular(10),
            ),
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _suggestions.length,
              separatorBuilder: (context, i) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final s = _suggestions[i];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.location_on_outlined, color: AppColors.primary),
                  title: Text(s.description, style: const TextStyle(fontSize: 13)),
                  onTap: () => _select(s),
                );
              },
            ),
          ),
      ],
    );
  }
}
