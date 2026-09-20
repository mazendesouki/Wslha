import 'package:flutter/material.dart';
import '../../core/date_format_ar.dart';
import '../../core/i18n.dart';
import '../../core/phone_utils.dart';
import '../../core/pricing_settings.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../shared/widgets/selectable_pill.dart';
import '../rides/address_field.dart';
import '../rides/directions_service.dart';
import '../rides/fare_calculator.dart' as fare_calc;
import '../rides/places_service.dart';
import 'airport_booking_confirmation_screen.dart';
import 'airport_fare.dart' as fare;
import 'airport_repository.dart';

/// Ported from airport.astro — same fields, same fare formula
/// (db/rides-vehicle-pricing.sql / src/data/airports.ts), same real-driver
/// vehicle catalog, and the same "رحلتك" trip-summary card (route + live
/// timeline + price breakdown) shown before booking. Distance/drive-time
/// prefer a real Directions API route (directions_service.dart) once it
/// comes back; falls back to haversine × road factor (same fallback
/// rides_screen.dart uses) while it's in flight or if it fails.
class AirportScreen extends StatefulWidget {
  const AirportScreen({super.key});

  @override
  State<AirportScreen> createState() => _AirportScreenState();
}

class _AirportScreenState extends State<AirportScreen> {
  final _repo = AirportRepository();

  // Wizard steps instead of one long scroll — same fields/validation as
  // before, just shown one group at a time with a progress bar and
  // رجوع/التالي buttons, per the reference mockup's multi-page flow.
  // Holds i18n keys, not display text — there's no BuildContext at
  // static-init time, so each title is resolved via context.tr() at the
  // point of use (see _stepProgressBar()).
  static const _stepTitleKeys = [
    'airport_step_trip_type',
    'airport_step_vehicle',
    'airport_step_route',
    'airport_step_passengers_wait',
    'airport_step_trip_info',
    'airport_step_confirm',
  ];
  int _currentStep = 0;
  final _scrollController = ScrollController();

  String _direction = 'departure'; // departure | arrival
  String _tripType = 'international'; // international | domestic

  List<fare.RegisteredVehicle> _vehicles = [];
  bool _loadingVehicles = true;
  String _category = 'sedan';
  fare.RegisteredVehicle? _selectedVehicle;
  int _selectedYear = DateTime.now().year;
  String _quality = 'regular';

  PlaceResult? _from;
  PlaceResult? _airport;
  final _addressCtrl = TextEditingController();
  DateTime? _flightTime;

  int _passengers = 1;
  int _companions = 0;
  int _bags = 1;

  int _waitPickupMin = 0;
  int _waitAirportMin = 0;

  final _airlineCtrl = TextEditingController();
  final _flightNoCtrl = TextEditingController();
  final _terminalCtrl = TextEditingController();
  final _flightCountryCtrl = TextEditingController();

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  bool _submitting = false;
  String? _error;

  final _directionsService = DirectionsService();
  RoadRoute? _routedRoute;
  String? _routeFetchedFor;

  @override
  void initState() {
    super.initState();
    SessionStore.load().then((s) {
      if (!mounted || s == null) return;
      setState(() {
        _nameCtrl.text = s.name;
        _phoneCtrl.text = s.phone;
      });
    });
    _loadVehicles();
    // Airport fares have no server-side recompute (see pricing_settings.dart),
    // so this is what actually keeps the price shown here in sync with any
    // admin change — refreshed on every visit to this screen instead of once
    // at app startup, so a price update takes effect without an app restart.
    PricingSettings.refresh().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _airlineCtrl.dispose();
    _flightNoCtrl.dispose();
    _terminalCtrl.dispose();
    _flightCountryCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Blocks moving off the "نقطة الانطلاق والوصول" step without the fields
  /// the fare calc and later steps depend on — same requirements _submit()
  /// already enforced, just surfaced earlier instead of only at the end.
  String? _stepValidationError(int step) {
    if (step == 2) {
      if (_from == null) {
        return _direction == 'departure' ? context.tr('airport_error_pick_origin') : context.tr('airport_error_pick_destination');
      }
      if (_airport == null) return context.tr('airport_error_pick_airport');
      if (_flightTime == null) return context.tr('airport_error_pick_flight_time');
    }
    if (step == 4) {
      if (_nameCtrl.text.trim().length < 2) return context.tr('airport_error_traveler_name');
      if (!isEgyptianMobile(normalizeEgyptianPhone(_phoneCtrl.text.trim()))) return egPhoneError;
    }
    return null;
  }

  void _goToStep(int step) {
    _scrollController.jumpTo(0);
    setState(() {
      _currentStep = step;
      _error = null;
    });
  }

  void _nextStep() {
    final err = _stepValidationError(_currentStep);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    if (_currentStep < _stepTitleKeys.length - 1) _goToStep(_currentStep + 1);
  }

  void _prevStep() {
    if (_currentStep > 0) _goToStep(_currentStep - 1);
  }

  Future<void> _loadVehicles() async {
    final vehicles = await _repo.fetchRegisteredVehicles();
    if (!mounted) return;
    setState(() {
      _vehicles = vehicles;
      _loadingVehicles = false;
      final inCategory = vehicles.where((v) => v.category == _category).toList();
      if (inCategory.isNotEmpty) {
        _selectedVehicle = inCategory.first;
        _selectedYear = inCategory.first.yearTo;
      } else if (vehicles.isNotEmpty) {
        _category = vehicles.first.category;
        _selectedVehicle = vehicles.first;
        _selectedYear = vehicles.first.yearTo;
      }
    });
  }

  double get _straightKm {
    if (_from == null || _airport == null) return 0;
    return fare_calc.haversineKm(_from!.lat, _from!.lng, _airport!.lat, _airport!.lng);
  }

  // Real routed road distance once the Directions API call comes back for
  // the current from/airport pair (_maybeRefreshRoute below); falls back to
  // the straightKm × roadFactor estimate exactly as before otherwise.
  double get _roadKm => _routedRoute?.km ?? (_straightKm * fare_calc.roadFactor);

  /// Same debounce-by-key pattern as rides_screen.dart's _maybeRefreshRoute.
  void _maybeRefreshRoute() {
    if (_from == null || _airport == null) return;
    final key = '${_from!.lat},${_from!.lng}|${_airport!.lat},${_airport!.lng}';
    if (_routeFetchedFor == key) return;
    _routeFetchedFor = key;
    _routedRoute = null;
    _directionsService.fetchRoadRoute([_from!, _airport!]).then((route) {
      if (!mounted || _routeFetchedFor != key) return;
      setState(() => _routedRoute = route);
    });
  }

  // etaMinutes() assumes a flat 40km/h city-traffic average, which is
  // realistic for a short in-town trip but wildly pessimistic once the
  // distance is a real highway drive (e.g. Damietta→Cairo was estimating
  // ~5-6 hours instead of the real ~2h45m). Prefer the known airport's
  // real, highway-calibrated drive time when the picked airport matches
  // one in fare.knownAirports; fall back to the straight-line estimate
  // only for an airport outside that list.
  int get _driveMinutes {
    final known = fare.matchKnownAirport(_airport?.name);
    if (known != null) return known.driveMinutes;
    if (_routedRoute != null) return _routedRoute!.minutes;
    return _straightKm > 0 ? fare_calc.etaMinutes(_straightKm) : 0;
  }

  int get _baseFare {
    if (_roadKm <= 0 || _selectedVehicle == null) return 0;
    final raw = fare.fareForVehicle(_roadKm, _selectedVehicle!.category, _selectedYear);
    final withQuality = raw * (fare.qualityMultiplier[_quality] ?? 1.0);
    final rounded = (withQuality / 50).ceil() * 50;
    return rounded < fare.airportMinFare ? fare.airportMinFare.round() : rounded;
  }

  int get _extraBagsFee {
    final info = fare.vehicleCategoryInfo[_category];
    final freeBags = info?.freeBags ?? 2;
    final extra = _bags - freeBags;
    return extra > 0 ? extra * fare.extraBagFee : 0;
  }

  int get _companionsFee => _companions * fare.companionFee;
  int get _waitPickupFee => fare.waitPickupFeeFor(_waitPickupMin);
  int get _waitAirportFee => _direction == 'arrival' ? 0 : fare.waitAirportFeeFor(_waitAirportMin);

  int get _total => _baseFare + _extraBagsFee + _companionsFee + _waitPickupFee + _waitAirportFee;

  void _onCategoryChanged(String cat) {
    setState(() {
      _category = cat;
      final inCategory = _vehicles.where((v) => v.category == cat).toList();
      _selectedVehicle = inCategory.isNotEmpty ? inCategory.first : null;
      _selectedYear = _selectedVehicle?.yearTo ?? DateTime.now().year;
    });
  }

  Future<void> _pickFlightTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(hours: 2)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 2))));
    if (time == null) return;
    setState(() => _flightTime = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _submit() async {
    setState(() => _error = null);

    final name = _nameCtrl.text.trim();
    final phone = normalizeEgyptianPhone(_phoneCtrl.text.trim());
    if (name.length < 2) {
      setState(() => _error = context.tr('airport_error_traveler_name'));
      return;
    }
    if (!isEgyptianMobile(phone)) {
      setState(() => _error = egPhoneError);
      return;
    }
    if (_from == null) {
      setState(() => _error = _direction == 'departure' ? context.tr('airport_error_pick_origin') : context.tr('airport_error_pick_destination'));
      return;
    }
    if (_airport == null) {
      setState(() => _error = context.tr('airport_error_pick_airport'));
      return;
    }
    if (_flightTime == null) {
      setState(() => _error = context.tr('airport_error_pick_flight_time'));
      return;
    }
    if (_selectedVehicle == null) {
      setState(() => _error = context.tr('airport_error_no_vehicles'));
      return;
    }

    setState(() => _submitting = true);

    // Same race as rides_screen.dart's _submit(): the background fetch
    // from _maybeRefreshRoute() (driven by build()) may not have come back
    // yet if the traveler filled the wizard quickly — wait for it here so
    // the distance/fare actually booked always matches the real route,
    // not the haversine × roadFactor estimate shown only while it's in
    // flight.
    if (_routedRoute == null) {
      final route = await _directionsService.fetchRoadRoute([_from!, _airport!]);
      if (mounted && route != null) {
        setState(() {
          _routedRoute = route;
          _routeFetchedFor = '${_from!.lat},${_from!.lng}|${_airport!.lat},${_airport!.lng}';
        });
      }
    }

    try {
      final directionLabel = _direction == 'departure' ? context.tr('airport_note_direction_departure') : context.tr('airport_note_direction_arrival');
      final tripLabel = _tripType == 'international' ? context.tr('airport_note_trip_international') : context.tr('airport_note_trip_domestic');
      final notes = [
        '${context.tr('airport_note_delivery_prefix')} — $directionLabel ($tripLabel)',
        '🚘 ${fare.categoryLabels[_category]} ${_selectedVehicle!.name} $_selectedYear',
        if (_quality != 'regular') '${context.tr('airport_note_requested_service')} ${fare.qualityLabels[_quality]}',
        if (_companions > 0) '${context.tr('airport_note_companions')} $_companions',
        if (_bags > 0) '${context.tr('airport_note_bags')} $_bags',
        if (_airlineCtrl.text.trim().isNotEmpty) '${context.tr('airport_note_airline')} ${_airlineCtrl.text.trim()}',
        if (_flightNoCtrl.text.trim().isNotEmpty) '${context.tr('airport_note_flight_no')} ${_flightNoCtrl.text.trim()}',
        if (_terminalCtrl.text.trim().isNotEmpty) '${context.tr('airport_note_terminal')} ${_terminalCtrl.text.trim()}',
        if (_flightCountryCtrl.text.trim().isNotEmpty) '${context.tr('airport_note_country')} ${_flightCountryCtrl.text.trim()}',
        if (_addressCtrl.text.trim().isNotEmpty) '${context.tr('airport_note_address_detail')} ${_addressCtrl.text.trim()}',
        '${context.tr('airport_note_time_prefix')} ${_direction == "departure" ? context.tr('airport_note_departure_time') : context.tr('airport_note_arrival_time')}: ${arDateTime(_flightTime!)}',
      ].join(' — ');

      final ride = await _repo.createAirportRide(
        customerPhone: phone,
        customerName: name,
        fromArea: _from!.name,
        fromLat: _from!.lat,
        fromLng: _from!.lng,
        airportName: _airport!.name,
        airportLat: _airport!.lat,
        airportLng: _airport!.lng,
        distanceKm: _roadKm,
        fare: _total,
        etaMinutes: _driveMinutes,
        passengers: _passengers,
        vehicleYear: _selectedYear,
        vehicleCategory: _selectedVehicle!.category,
        qualityTier: _quality,
        notes: notes,
        flightTime: _flightTime!,
        direction: _direction,
        tripType: _tripType,
      );

      if (!mounted) return;
      if (ride == null || ride['id'] == null) {
        setState(() {
          _submitting = false;
          _error = context.tr('airport_error_submit_failed');
        });
        return;
      }
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => AirportBookingConfirmationScreen(
          rideId: ride['id'].toString(),
          direction: _direction,
          tripType: _tripType,
          flightTime: _flightTime!,
          driveMinutes: _driveMinutes,
          fromName: _from!.name,
          airportName: _airport!.name,
          address: _addressCtrl.text.trim(),
          vehicleLabel: '${_selectedVehicle!.name} $_selectedYear',
          qualityLabel: _quality == 'regular' ? '' : (fare.qualityLabels[_quality] ?? ''),
          passengers: _passengers,
          companions: _companions,
          bags: _bags,
          airline: _airlineCtrl.text.trim(),
          flightNo: _flightNoCtrl.text.trim(),
          terminal: _terminalCtrl.text.trim(),
          flightCountry: _flightCountryCtrl.text.trim(),
          baseFare: _baseFare,
          extraBagsFee: _extraBagsFee,
          companionsFee: _companionsFee,
          waitPickupFee: _waitPickupFee,
          waitAirportFee: _waitAirportFee,
          total: _total,
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = '${context.tr('airport_error_submit_failed_prefix')} $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_from != null && _airport != null) _maybeRefreshRoute();
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('airport_app_bar_title'))),
      body: Column(
        children: [
          _stepProgressBar(),
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              child: _stepContent(),
            ),
          ),
          _stepNavBar(),
        ],
      ),
    );
  }

  /// Row of dots-with-labels across the top — filled/checked once passed,
  /// outlined for the current step, plain for what's ahead. Tapping a
  /// completed step jumps back to it directly.
  Widget _stepProgressBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(color: context.surfaceColor, border: Border(bottom: BorderSide(color: context.borderColor))),
      child: Row(
        children: [
          for (var i = 0; i < _stepTitleKeys.length; i++) ...[
            Expanded(
              child: GestureDetector(
                onTap: i < _currentStep ? () => _goToStep(i) : null,
                child: Column(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i <= _currentStep ? AppColors.primary : context.surfaceColor,
                        border: Border.all(color: i <= _currentStep ? AppColors.primary : const Color(0xFFCBD5D3), width: 1.6),
                      ),
                      child: i < _currentStep
                          ? const Icon(Icons.check, size: 15, color: Colors.white)
                          : Text('${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: i == _currentStep ? Colors.white : AppColors.textFaint)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.tr(_stepTitleKeys[i]),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: i == _currentStep ? AppColors.primaryDark : AppColors.textFaint),
                    ),
                  ],
                ),
              ),
            ),
            if (i < _stepTitleKeys.length - 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Container(width: 12, height: 1.6, color: i < _currentStep ? AppColors.primary : context.borderColor),
              ),
          ],
        ],
      ),
    );
  }

  Widget _stepNavBar() {
    final isLast = _currentStep == _stepTitleKeys.length - 1;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: context.surfaceColor, border: Border(top: BorderSide(color: context.borderColor))),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFFEF2F2), border: Border.all(color: const Color(0xFFFCA5A5)), borderRadius: BorderRadius.circular(10)),
                  child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
                ),
              ),
            Row(
              children: [
                if (_currentStep > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _submitting ? null : _prevStep,
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: Text(context.tr('airport_nav_back')),
                    ),
                  ),
                if (_currentStep > 0) const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : (isLast ? _submit : _nextStep),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isLast ? AppColors.accent : null,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _submitting
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(isLast ? context.tr('airport_nav_confirm') : context.tr('airport_nav_next')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepContent() {
    final catInfo = fare.vehicleCategoryInfo[_category];
    final maxTravelers = catInfo?.maxTravelers ?? 3;
    final maxBags = catInfo?.maxBags ?? 2;

    switch (_currentStep) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionTitle('1', context.tr('airport_section_trip_direction')),
            _sectionCard([
              _radioRow(context.tr('airport_section_trip_direction'), _direction, {
                'departure': context.tr('airport_direction_departure'),
                'arrival': context.tr('airport_direction_arrival'),
              }, (v) => setState(() => _direction = v)),
            ]),
            const SizedBox(height: 10),
            _sectionCard([
              _radioRow(context.tr('airport_trip_type_label'), _tripType, {
                'international': context.tr('airport_trip_type_international'),
                'domestic': context.tr('airport_trip_type_domestic'),
              }, (v) => setState(() => _tripType = v)),
              const SizedBox(height: 8),
              Text(
                _tripType == 'international'
                    ? context.tr('airport_trip_type_info_international')
                    : context.tr('airport_trip_type_info_domestic'),
                style: const TextStyle(fontSize: 11, color: AppColors.primaryDark, fontWeight: FontWeight.w600),
              ),
            ]),
          ],
        );

      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionTitle('2', context.tr('airport_section_vehicle')),
            _sectionCard([
              if (_loadingVehicles)
                const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
              else if (_vehicles.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(context.tr('airport_no_vehicles'), style: const TextStyle(color: AppColors.error, fontSize: 12)),
                )
              else ...[
                for (final cat in fare.vehicleCategoryInfo.keys.where((cat) => _vehicles.any((v) => v.category == cat)))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _VehicleCategoryCard(
                      info: fare.vehicleCategoryInfo[cat]!,
                      label: fare.categoryLabels[cat]!.replaceAll(RegExp(r'^[^ ]+ '), ''),
                      selected: _category == cat,
                      mostPopular: cat == 'sedan',
                      estimatedFare: _roadKm > 0
                          ? fare.fareForVehicle(_roadKm, cat, _vehicles.firstWhere((v) => v.category == cat).yearTo)
                          : null,
                      onTap: () => _onCategoryChanged(cat),
                    ),
                  ),
                const SizedBox(height: 10),
                DropdownButtonFormField<fare.RegisteredVehicle>(
                  initialValue: _selectedVehicle,
                  decoration: InputDecoration(labelText: context.tr('airport_make_model_label'), prefixIcon: const Icon(Icons.directions_car_outlined)),
                  items: _vehicles
                      .where((v) => v.category == _category)
                      .map((v) => DropdownMenuItem(value: v, child: Text(v.name)))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _selectedVehicle = v;
                      _selectedYear = v.yearTo;
                    });
                  },
                ),
                const SizedBox(height: 10),
                if (_selectedVehicle != null)
                  DropdownButtonFormField<int>(
                    initialValue: _selectedYear,
                    decoration: InputDecoration(labelText: context.tr('airport_year_label'), prefixIcon: const Icon(Icons.calendar_today_outlined)),
                    items: [for (var y = _selectedVehicle!.yearTo; y >= _selectedVehicle!.yearFrom; y--) y]
                        .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                        .toList(),
                    onChanged: (y) => setState(() => _selectedYear = y ?? _selectedYear),
                  ),
                const SizedBox(height: 14),
                Text(context.tr('airport_service_level_label'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: fare.qualityLabels.keys
                      .map((q) => SelectablePill(
                            label: '${fare.qualityLabels[q]}'
                                '${q == 'regular' ? '' : ' (+${(((fare.qualityMultiplier[q] ?? 1) - 1) * 100).round()}%)'}',
                            selected: _quality == q,
                            onTap: () => setState(() => _quality = q),
                          ))
                      .toList(),
                ),
              ],
            ]),
          ],
        );

      case 2:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionTitle('3', context.tr('airport_section_route')),
            if (_airport != null) ...[
              _AirportBanner(airportName: _airport!.name),
              const SizedBox(height: 12),
            ],
            _sectionCard([
              AddressField(
                label: _direction == 'departure' ? context.tr('airport_origin_label_departure') : context.tr('airport_origin_label_arrival'),
                hint: context.tr('airport_origin_hint'),
                showLocationButton: true,
                prefixIcon: Icons.trip_origin,
                onSelected: (r) => setState(() => _from = r),
              ),
              const SizedBox(height: 12),
              AddressField(
                label: _direction == 'departure' ? context.tr('airport_airport_label_departure') : context.tr('airport_airport_label_arrival'),
                hint: context.tr('airport_airport_hint'),
                placesTypes: 'airport',
                prefixIcon: Icons.flight_takeoff,
                onSelected: (r) => setState(() => _airport = r),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _addressCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: context.tr('airport_pickup_address_label'),
                  hintText: context.tr('airport_pickup_address_hint'),
                  prefixIcon: const Icon(Icons.home_outlined),
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickFlightTime,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: _direction == 'departure' ? context.tr('airport_flight_datetime_departure') : context.tr('airport_flight_datetime_arrival'),
                    prefixIcon: const Icon(Icons.event_outlined),
                  ),
                  child: Text(
                    _flightTime == null ? context.tr('airport_choose_datetime') : arDateTime(_flightTime!),
                    style: TextStyle(color: _flightTime == null ? AppColors.textFaint : Colors.black87),
                  ),
                ),
              ),
            ]),
          ],
        );

      case 3:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionTitle('4', context.tr('airport_section_passengers_bags')),
            _StepperCard(
              icon: Icons.person_outline,
              label: context.tr('airport_passenger_count_label'),
              value: _passengers,
              min: 1,
              max: maxTravelers,
              onChanged: (v) => setState(() => _passengers = v),
            ),
            const SizedBox(height: 10),
            _StepperCard(
              icon: Icons.group_outlined,
              label: context.tr('airport_companion_label'),
              sublabel: '${fare.companionFee} ${context.tr('airport_companion_fee_suffix')}',
              value: _companions,
              min: 0,
              max: 9,
              onChanged: (v) => setState(() => _companions = v),
            ),
            const SizedBox(height: 10),
            _StepperCard(
              icon: Icons.luggage_outlined,
              label: context.tr('airport_bags_label'),
              sublabel: context.tr('airport_bags_sublabel'),
              value: _bags,
              min: 0,
              max: maxBags,
              onChanged: (v) => setState(() => _bags = v),
            ),
            const SizedBox(height: 18),
            _sectionTitle('5', context.tr('airport_section_wait_times')),
            _sectionCard([
              DropdownButtonFormField<int>(
                initialValue: _waitPickupMin,
                decoration: InputDecoration(labelText: context.tr('airport_wait_pickup_label'), prefixIcon: const Icon(Icons.hourglass_empty)),
                items: [
                  DropdownMenuItem(value: 0, child: Text(context.tr('airport_wait_none'))),
                  DropdownMenuItem(value: 15, child: Text(context.tr('airport_wait_15_free'))),
                  DropdownMenuItem(value: 30, child: Text(context.tr('airport_wait_30_fee'))),
                  DropdownMenuItem(value: 45, child: Text(context.tr('airport_wait_45_fee'))),
                  DropdownMenuItem(value: 60, child: Text(context.tr('airport_wait_60_fee'))),
                ],
                onChanged: (v) => setState(() => _waitPickupMin = v ?? 0),
              ),
              if (_direction != 'arrival') ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: _waitAirportMin,
                  decoration: InputDecoration(labelText: context.tr('airport_wait_airport_label'), prefixIcon: const Icon(Icons.timer_outlined)),
                  items: [
                    DropdownMenuItem(value: 0, child: Text(context.tr('airport_wait_none'))),
                    DropdownMenuItem(value: 30, child: Text(context.tr('airport_wait_30_free'))),
                    DropdownMenuItem(value: 60, child: Text(context.tr('airport_wait_60_fee_airport'))),
                    DropdownMenuItem(value: 90, child: Text(context.tr('airport_wait_90_fee'))),
                  ],
                  onChanged: (v) => setState(() => _waitAirportMin = v ?? 0),
                ),
              ],
            ]),
          ],
        );

      case 4:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionTitle('6', context.tr('airport_section_flight_info')),
            _sectionCard([
              TextField(controller: _airlineCtrl, decoration: InputDecoration(labelText: context.tr('airport_airline_label'), hintText: context.tr('airport_airline_hint'), prefixIcon: const Icon(Icons.airlines_outlined))),
              const SizedBox(height: 10),
              TextField(controller: _flightNoCtrl, decoration: InputDecoration(labelText: context.tr('airport_flight_no_label'), hintText: 'MS 712', prefixIcon: const Icon(Icons.confirmation_number_outlined))),
              const SizedBox(height: 10),
              TextField(controller: _terminalCtrl, decoration: InputDecoration(labelText: context.tr('airport_terminal_label'), hintText: context.tr('airport_terminal_hint'), prefixIcon: const Icon(Icons.holiday_village_outlined))),
              const SizedBox(height: 10),
              TextField(
                controller: _flightCountryCtrl,
                decoration: InputDecoration(
                  labelText: _direction == 'departure' ? context.tr('airport_country_label_departure') : context.tr('airport_country_label_arrival'),
                  hintText: context.tr('airport_country_hint'),
                  prefixIcon: const Icon(Icons.public_outlined),
                ),
              ),
            ]),
            const SizedBox(height: 18),
            _sectionTitle('7', context.tr('airport_section_traveler_info')),
            _sectionCard([
              TextField(controller: _nameCtrl, decoration: InputDecoration(labelText: context.tr('airport_traveler_name_label'), prefixIcon: const Icon(Icons.person_outline))),
              const SizedBox(height: 10),
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: context.tr('airport_phone_label'), hintText: '01xxxxxxxxx', prefixIcon: const Icon(Icons.phone_outlined)),
              ),
            ]),
          ],
        );

      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionTitle('8', context.tr('airport_section_confirm')),
            if (_roadKm > 0 && _flightTime != null)
              _tripSummaryCard()
            else
              Text(context.tr('airport_confirm_step_missing'), style: const TextStyle(fontSize: 11, color: AppColors.textFaint), textAlign: TextAlign.center),
          ],
        );
    }
  }

  /// Matches airport.astro's "رحلتك" sidebar: route header, live timeline,
  /// price breakdown table, total — confirm button and error box now live
  /// in the fixed _stepNavBar() instead of scrolling with this card, same
  /// as every other step's رجوع/التالي bar, so this whole step fits one
  /// screen without needing to scroll to reach the confirm action.
  Widget _tripSummaryCard() {
    final steps = fare.buildTimeline(
      direction: _direction,
      tripType: _tripType,
      flightTime: _flightTime!,
      driveMinutes: _driveMinutes,
    );
    final vehicleLabel = _selectedVehicle != null ? '${_selectedVehicle!.name} $_selectedYear' : '—';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppColors.primaryDark, AppColors.primary])),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('airport_trip_summary_title'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
                const SizedBox(height: 3),
                Text(
                  '${_from?.name ?? "—"} ← ${_airport?.name ?? "—"}',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < steps.length; i++) _timelineRow(steps[i], isLast: i == steps.length - 1),
                const Divider(height: 16),
                _fareLine(context.tr('airport_fare_distance'), '${_roadKm.toStringAsFixed(0)} كم', isText: true),
                _fareLine(context.tr('airport_fare_vehicle'), vehicleLabel, isText: true),
                if (_extraBagsFee > 0) _fareLine(context.tr('airport_fare_extra_bags'), '$_extraBagsFee ج.م', isText: true),
                if (_companionsFee > 0) _fareLine(context.tr('airport_fare_companions'), '$_companionsFee ج.م', isText: true),
                if (_waitPickupFee > 0) _fareLine(context.tr('airport_fare_wait_pickup'), '$_waitPickupFee ج.م', isText: true),
                if (_waitAirportFee > 0) _fareLine(context.tr('airport_fare_wait_airport'), '$_waitAirportFee ج.م', isText: true),
                const Divider(height: 16),
                _fareLine(context.tr('airport_fare_total'), '$_total ج.م', bold: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _timelineRow(fare.TimelineStep step, {required bool isLast}) {
    final timeStr = arTime(step.time);
    final dateStr = '${_weekday(step.time.weekday)} ${step.time.day} ${_month(step.time.month)}';
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text(step.icon, style: const TextStyle(fontSize: 11)),
              ),
              if (!isLast) Expanded(child: Container(width: 1.5, color: const Color(0xFFE5E7EB))),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(step.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                  Text('$dateStr ${context.tr('airport_timeline_at')} $timeStr', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: AppColors.primary)),
                  if (step.sub.isNotEmpty)
                    Text(step.sub, style: const TextStyle(fontSize: 10, color: AppColors.textFaint)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _weekdayKeys = [
    'airport_weekday_mon', 'airport_weekday_tue', 'airport_weekday_wed', 'airport_weekday_thu',
    'airport_weekday_fri', 'airport_weekday_sat', 'airport_weekday_sun',
  ];
  static const _monthKeys = [
    'airport_month_jan', 'airport_month_feb', 'airport_month_mar', 'airport_month_apr',
    'airport_month_may', 'airport_month_jun', 'airport_month_jul', 'airport_month_aug',
    'airport_month_sep', 'airport_month_oct', 'airport_month_nov', 'airport_month_dec',
  ];
  String _weekday(int w) => context.tr(_weekdayKeys[w - 1]);
  String _month(int m) => context.tr(_monthKeys[m - 1]);

  Widget _fareLine(String label, String value, {bool bold = false, bool isText = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: bold ? 14 : 12, fontWeight: bold ? FontWeight.w900 : FontWeight.w600, color: AppColors.textFaint)),
          Text(value, style: TextStyle(fontSize: bold ? 16 : 12, fontWeight: FontWeight.w900, color: bold ? AppColors.success : Colors.black87)),
        ],
      ),
    );
  }

  /// Groups a numbered section's fields into one tinted card instead of a
  /// flat list separated by dividers — same card language as the rest of
  /// the app's screens.
  // White + thin border instead of a solid teal fill — was the one thing
  // still visibly unchanged after the vehicle-card redesign below (every
  // section on this screen sat inside a solid green-tinted box, which read
  // as the "same as before" even once the card contents were reworked).
  Widget _sectionCard(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }

  Widget _sectionTitle(String number, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          CircleAvatar(radius: 12, backgroundColor: AppColors.primary, child: Text(number, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900))),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _radioRow(String label, String value, Map<String, String> options, ValueChanged<String> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.entries
              .map((e) => SelectablePill(label: e.value, selected: value == e.key, onTap: () => onChanged(e.key)))
              .toList(),
        ),
      ],
    );
  }

}

/// Confirms the picked airport at a glance — the reference mockup used a
/// full photo banner; wslha has no real per-airport photo library, so this
/// keeps the same "you're booking to/from X" reassurance with an icon
/// badge on brand instead of borrowing a stock photo.
class _AirportBanner extends StatelessWidget {
  final String airportName;
  const _AirportBanner({required this.airportName});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.primaryDark, AppColors.primary]),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
            child: const Icon(Icons.flight_takeoff, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(airportName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(context.tr('airport_banner_choose_details'), style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One field, one card — mirrors the reference mockup's passenger/luggage
/// steppers (icon badge + label + -/value/+ row) instead of stacking three
/// stepper rows inside a single shared card.
class _StepperCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? sublabel;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  const _StepperCard({
    required this.icon,
    required this.label,
    this.sublabel,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.primaryLight, shape: BoxShape.circle),
            child: Icon(icon, color: AppColors.primaryDark, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                if (sublabel != null) Text(sublabel!, style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
              ],
            ),
          ),
          IconButton(onPressed: value > min ? () => onChanged(value - 1) : null, icon: const Icon(Icons.remove_circle_outline)),
          Text('$value', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          IconButton(onPressed: value < max ? () => onChanged(value + 1) : null, icon: const Icon(Icons.add_circle_outline)),
        ],
      ),
    );
  }
}

/// Vehicle-category picker card — a fresh layout (icon badge, capacity
/// pills, live price, "الأكثر طلبًا" tag) rather than just adding fields to
/// the old chip shape, while staying on the app's own teal/gold identity
/// instead of borrowing the reference mockup's navy palette.
class _VehicleCategoryCard extends StatelessWidget {
  final fare.VehicleCategoryInfo info;
  final String label;
  final bool selected;
  final bool mostPopular;
  final int? estimatedFare;
  final VoidCallback onTap;
  const _VehicleCategoryCard({
    required this.info,
    required this.label,
    required this.selected,
    required this.mostPopular,
    required this.estimatedFare,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.surfaceColor,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: selected ? AppColors.primary : context.borderColor, width: selected ? 2 : 1),
            boxShadow: selected
                ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.14), blurRadius: 14, offset: const Offset(0, 4))]
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: Text(info.icon, style: const TextStyle(fontSize: 26)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                        if (mostPopular) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                            child: Text(context.tr('airport_most_popular_tag'), style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: AppColors.success)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(info.desc, style: const TextStyle(fontSize: 11.5, color: AppColors.textFaint)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _capacityPill(Icons.person_outline, '${info.maxTravelers}'),
                        const SizedBox(width: 6),
                        _capacityPill(Icons.luggage_outlined, '${info.maxBags}'),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? AppColors.primary : Colors.transparent,
                      border: Border.all(color: selected ? AppColors.primary : const Color(0xFFCBD5D3), width: 1.6),
                    ),
                    child: selected ? const Icon(Icons.check, size: 15, color: Colors.white) : null,
                  ),
                  if (estimatedFare != null) ...[
                    const SizedBox(height: 10),
                    Text('$estimatedFare ج.م', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppColors.primaryDark)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _capacityPill(IconData icon, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: const Color(0xFFF3F5F4), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.textFaint),
          const SizedBox(width: 3),
          Text(value, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
