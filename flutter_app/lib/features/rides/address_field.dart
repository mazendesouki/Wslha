import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/theme.dart';
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

  const AddressField({
    super.key,
    required this.label,
    required this.hint,
    required this.onSelected,
    this.showLocationButton = false,
    this.placesTypes,
  });

  @override
  State<AddressField> createState() => _AddressFieldState();
}

class _AddressFieldState extends State<AddressField> {
  final _controller = TextEditingController();
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
          _locError = 'محتاجين إذن الموقع عشان نحدد نقطة انطلاقك';
        });
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() {
          _locLoading = false;
          _locError = 'خدمة تحديد الموقع (GPS) مقفولة على جهازك';
        });
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      final name = await _places.reverseGeocode(pos.latitude, pos.longitude);
      if (!mounted) return;
      _controller.text = name;
      widget.onSelected(PlaceResult(name, pos.latitude, pos.longitude));
      setState(() => _locLoading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _locLoading = false;
        _locError = 'تعذّر تحديد موقعك، حاول تاني';
      });
    }
  }

  Future<void> _select(PlaceSuggestion s) async {
    setState(() => _suggestions = []);
    _controller.text = s.description;
    final detail = await _places.details(s.placeId);
    if (detail != null) widget.onSelected(detail);
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
            suffixIcon: _loading || _locLoading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : widget.showLocationButton
                    ? IconButton(
                        icon: const Icon(Icons.my_location, color: AppColors.primary),
                        tooltip: 'استخدم موقعي الحالي',
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
