import 'package:flutter/material.dart';
import '../../core/feature_flags.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../shared/widgets/branded_header.dart';
import '../../shared/widgets/selectable_pill.dart';
import '../airport/airport_fare.dart' show qualityMultiplier;
import '../coupons/coupon_field.dart';
import '../coupons/coupon_repository.dart';
import 'address_field.dart';
import 'directions_service.dart';
import 'fare_calculator.dart' as fare_calc;
import 'places_service.dart';
import 'ride_repository.dart';
import 'ride_tracking_screen.dart';
import 'scheduled_rides_screen.dart';

const int _maxStops = 3;

// Shorter pill labels for this screen only (design canvas) — the shared
// qualityLabels map (airport_fare.dart) carries emoji + the grammatically
// full "عادية/نظيفة/مكيّفة" forms that airport_screen.dart's own pickers
// still use, so it's left untouched; only rides_screen.dart's display text
// is simplified here. The real percentages (qualityMultiplier) are NOT
// touched — they drive the actual fare calculation, so the label always
// shows exactly what the customer is really charged.
const Map<String, String> _tierShortLabels = {
  'regular': 'عادي',
  'clean': 'نظيف',
  'ac': 'تكييف',
  'modern': 'حديثة',
};

class RidesScreen extends StatefulWidget {
  // Prefills the from/destination fields — used by "احجز تاني" (rebook)
  // on invoices_screen.dart's ride history, so a customer can reuse a past
  // trip's addresses instead of typing them again. Left null for a normal
  // fresh booking.
  final PlaceResult? initialFrom;
  final PlaceResult? initialTo;
  const RidesScreen({super.key, this.initialFrom, this.initialTo});

  @override
  State<RidesScreen> createState() => _RidesScreenState();
}

class _RidesScreenState extends State<RidesScreen> {
  final _rideRepo = RideRepository();

  PlaceResult? _from;
  // Sequential stops — the last non-null one is the ride's real
  // destination; any before it are intermediate waypoints (e.g. an errand
  // stop) passed to createRide as `stops`.
  late List<PlaceResult?> _stops;
  int _passengers = 1;
  String _payment = 'cash';
  // 'regular' | 'ac' — same tier system airport rides already use (see
  // fare_calculator.dart's qualityMultiplier import), now offered on
  // regular/external rides too so a driver whose registered car has no AC
  // can't be matched to a customer who specifically asked for one.
  String _qualityTier = 'regular';
  bool _negotiable = false;
  bool _submitting = false;
  final _couponRepo = CouponRepository();
  String? _appliedCouponCode;
  DateTime? _scheduledAt;
  UserSession? _session;
  double _surgeMult = 1.0;
  String? _surgeFetchedFor;
  final _directionsService = DirectionsService();
  RoadRoute? _routedRoute;
  String? _routeFetchedFor;
  int? _availableDrivers;

  /// Every leg's PlaceResult in order, stopping at the first unfilled one —
  /// so a driver can fill stop 1 and leave stop 2/3 empty without breaking
  /// the fare preview.
  List<PlaceResult> get _filledPoints {
    if (_from == null) return [];
    final points = [_from!];
    for (final s in _stops) {
      if (s == null) break;
      points.add(s);
    }
    return points;
  }

  double get _straightKm {
    final points = _filledPoints;
    if (points.length < 2) return 0;
    double total = 0;
    for (var i = 0; i < points.length - 1; i++) {
      total += fare_calc.haversineKm(points[i].lat, points[i].lng, points[i + 1].lat, points[i + 1].lng);
    }
    return total;
  }

  // Real routed road distance when the Directions API call has come back for
  // the currently-filled points (_maybeRefreshRoute below); otherwise falls
  // back to the straightKm × roadFactor estimate exactly as before, so the
  // fare/ETA preview is never blocked on a network call.
  double get _roadKm => _routedRoute?.km ?? (_straightKm * fare_calc.roadFactor);
  bool get _isExternal => _roadKm > 0 && fare_calc.isExternalTrip(_roadKm);
  int get _fare {
    if (_straightKm <= 0) return 0;
    // fareForDistance() re-derives roadKm internally as straightKm ×
    // roadFactor — when a real routed distance came back, feed it that
    // straightKm-equivalent (_roadKm ÷ roadFactor) so its internal
    // multiplication reproduces the real _roadKm instead of the estimate,
    // without touching that function's contract (guard_ride_fare() server
    // side trusts distance_km as sent, so this is what actually gets billed).
    final fareInputKm = _routedRoute != null ? (_roadKm / fare_calc.roadFactor) : _straightKm;
    return _isExternal
        ? fare_calc.externalFareForDistance(_roadKm, qualityTier: _qualityTier, surgeMultiplier: _surgeMult)
        : fare_calc.fareForDistance(fareInputKm, toArea: _filledPoints.last.name, qualityTier: _qualityTier, surgeMultiplier: _surgeMult);
  }

  int get _eta => _routedRoute?.minutes ?? (_straightKm > 0 ? fare_calc.etaMinutes(_straightKm) : 0);

  /// Fetches the real road route once per distinct set of filled points —
  /// same debounce-by-key pattern as _maybeRefreshSurge. Clears the previous
  /// routed result immediately on a point change so the preview never shows
  /// a stale route for different points while the new one is in flight.
  void _maybeRefreshRoute() {
    final points = _filledPoints;
    if (points.length < 2) return;
    final key = points.map((p) => '${p.lat},${p.lng}').join('|');
    if (_routeFetchedFor == key) return;
    _routeFetchedFor = key;
    _routedRoute = null;
    _directionsService.fetchRoadRoute(points).then((route) {
      if (!mounted || _routeFetchedFor != key) return;
      setState(() => _routedRoute = route);
    });
  }

  bool get _hasMultiStop => _filledPoints.length > 2;

  // Reported as a real confusion/dispute risk: the moment a destination is
  // picked, _roadKm briefly falls back to the haversine × roadFactor
  // estimate (visibly different from the real routed distance — e.g. 4.6
  // vs. the real 2.6) until the Directions API call finishes and
  // _maybeRefreshRoute()'s setState lands. _submit() already awaits the
  // real route before actually booking, so the CHARGED fare was always
  // correct — but the customer briefly SAW the wrong number, which is what
  // was reported. True whenever there are enough points for a route but
  // the real one hasn't come back yet.
  bool get _routeLoading => _filledPoints.length >= 2 && _routedRoute == null;

  @override
  void initState() {
    super.initState();
    _from = widget.initialFrom;
    _stops = [widget.initialTo];
    SessionStore.load().then((s) => setState(() => _session = s));
    _rideRepo.fetchAvailableDriversCount().then((count) {
      if (mounted) setState(() => _availableDrivers = count);
    });
  }

  /// Refetches the surge multiplier only when the ride type (local ↔
  /// external) actually changes — cheap guard so this doesn't fire on
  /// every rebuild (setState during address selection, tier toggling…),
  /// just the ones where the multiplier could genuinely be different.
  void _maybeRefreshSurge() {
    final rideType = _isExternal ? 'external' : 'local';
    if (_surgeFetchedFor == rideType) return;
    _surgeFetchedFor = rideType;
    _rideRepo.fetchSurgeMultiplier(rideType: rideType).then((mult) {
      if (!mounted) return;
      setState(() => _surgeMult = mult);
    });
  }

  Future<void> _submit() async {
    final points = _filledPoints;
    if (points.length < 2 || _session == null) return;
    setState(() => _submitting = true);

    // The background fetch from _maybeRefreshRoute() (driven by build())
    // may not have come back yet if the customer filled the form and
    // tapped submit quickly — that would otherwise silently book this one
    // ride on the haversine × roadFactor estimate even though the fare
    // preview and every other screen end up using the real route once it
    // arrives. Wait for it here so what actually gets booked always
    // matches what was shown.
    if (_routedRoute == null) {
      final route = await _directionsService.fetchRoadRoute(points);
      if (mounted && route != null) {
        setState(() {
          _routedRoute = route;
          _routeFetchedFor = points.map((p) => '${p.lat},${p.lng}').join('|');
        });
      }
    }

    final destination = points.last;
    final waypoints = points.sublist(1, points.length - 1); // between origin and final destination

    Map<String, dynamic>? ride;
    try {
      ride = await _rideRepo.createRide(
        customerPhone: _session!.phone,
        customerName: _session!.name,
        fromArea: _from!.name,
        fromLat: _from!.lat,
        fromLng: _from!.lng,
        toArea: destination.name,
        toLat: destination.lat,
        toLng: destination.lng,
        distanceKm: _roadKm,
        fare: _fare,
        etaMinutes: _eta,
        passengers: _passengers,
        payment: _payment,
        rideType: _isExternal ? 'external' : 'local',
        stops: waypoints.map((p) => {'name': p.name, 'lat': p.lat, 'lng': p.lng}).toList(),
        isNegotiable: _negotiable,
        qualityTier: _qualityTier,
        scheduledAt: _scheduledAt,
      );
    } catch (e) {
      // createRide() throws straight from the Supabase insert on failure
      // (network drop, RLS denial) rather than returning null — without
      // this catch, _submitting stayed true forever with the button
      // frozen mid-spinner and no explanation, on the single most-used
      // action in the customer app.
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${context.tr('rides_submit_failed_prefix')} $e'), backgroundColor: AppColors.error, duration: const Duration(seconds: 6)),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _submitting = false);

    final rideId = ride?['id']?.toString();
    if (rideId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('rides_submit_failed_generic'))),
      );
      return;
    }

    final couponCode = _appliedCouponCode;
    if (couponCode != null) {
      // Best-effort: the ride is already booked either way — a coupon
      // failure here (already used, race with another device) shouldn't
      // block the ride the customer just paid full price to secure.
      try {
        final credited = await _couponRepo.redeem(
          code: couponCode, phone: _session!.phone, amount: _fare.toDouble(), serviceType: 'ride', referenceId: rideId,
        );
        if (mounted && credited > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${context.tr('rides_coupon_credited_prefix')} ${credited.toStringAsFixed(0)} ${context.tr('rides_coupon_credited_suffix')}')),
          );
        }
      } catch (_) {}
    }

    if (!mounted) return;

    if (_scheduledAt != null) {
      // A scheduled ride has no driver/dispatch yet (status stays
      // 'scheduled' until pg_cron activates it near the pickup time — see
      // ride_repository.dart's createRide doc) so RideTrackingScreen would
      // just show an empty "waiting for a driver" state with nothing to
      // actually track. Confirm and send them to the scheduled-rides list
      // instead, where they can review/cancel it.
      final at = _scheduledAt!;
      setState(() => _scheduledAt = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${context.tr('rides_scheduled_confirmation_prefix')} ${at.day}/${at.month} ${context.tr('rides_scheduled_confirmation_at')} ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}')),
      );
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ScheduledRidesScreen(phone: _session!.phone)),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RideTrackingScreen(rideId: rideId)),
    );
  }

  Future<void> _pickScheduleTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 14)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (time == null || !mounted) return;
    final picked = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (picked.isBefore(now.add(const Duration(minutes: 30)))) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('rides_schedule_too_soon'))),
      );
      return;
    }
    setState(() => _scheduledAt = picked);
  }

  void _addStop() {
    if (_stops.length >= _maxStops) return;
    setState(() => _stops.add(null));
  }

  void _removeStop(int index) {
    setState(() => _stops.removeAt(index));
  }

  String _stopLabel(int index) {
    // Only the last stop field reads as "الوجهة" — earlier ones are
    // waypoints the driver stops at along the way.
    if (index == _stops.length - 1) {
      return _stops.length > 1 ? context.tr('rides_stop_final_destination') : context.tr('rides_stop_to');
    }
    return '${context.tr('rides_stop_label_prefix')} ${index + 1}';
  }

  @override
  Widget build(BuildContext context) {
    if (_filledPoints.length >= 2) {
      _maybeRefreshSurge();
      _maybeRefreshRoute();
    }
    final ready = _filledPoints.length >= 2 && _session != null && !_submitting;

    return Scaffold(
      backgroundColor: context.mutedSurface,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 56),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_availableDrivers != null && _availableDrivers! > 0) ...[
                _buildAvailableDriversCard(context),
                const SizedBox(height: 10),
              ],
              _sectionLabel(context.tr('rides_section_from_to')),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.surfaceColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.borderColor),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AddressField(
                      label: context.tr('rides_from_label'),
                      hint: context.tr('rides_from_hint'),
                      showLocationButton: true,
                      prefixIcon: Icons.trip_origin,
                      initialValue: widget.initialFrom,
                      onSelected: (r) => setState(() => _from = r),
                    ),
                    const SizedBox(height: 12),
                    for (var i = 0; i < _stops.length; i++) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: AddressField(
                              key: ValueKey('stop-$i-${_stops.length}'),
                              label: _stopLabel(i),
                              hint: i == _stops.length - 1 ? context.tr('rides_stop_hint_final') : context.tr('rides_stop_hint_waypoint'),
                              prefixIcon: i == _stops.length - 1 ? Icons.flag_outlined : Icons.location_on_outlined,
                              initialValue: _stops[i],
                              onSelected: (r) => setState(() => _stops[i] = r),
                            ),
                          ),
                          if (_stops.length > 1)
                            IconButton(
                              icon: const Icon(Icons.close, color: AppColors.textFaint),
                              onPressed: () => _removeStop(i),
                              tooltip: context.tr('rides_remove_stop_tooltip'),
                            ),
                        ],
                      ),
                      if (i < _stops.length - 1) const SizedBox(height: 12),
                    ],
                    if (FeatureFlags.multistopEnabled && _stops.length < _maxStops)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _addStop,
                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), visualDensity: VisualDensity.compact),
                          icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                          label: Text(context.tr('rides_add_stop'), style: const TextStyle(fontSize: 12)),
                        ),
                      ),
                    const Divider(height: 16),
                    Row(
                      children: [
                        const Icon(Icons.people_outline, size: 20, color: AppColors.textFaint),
                        const SizedBox(width: 8),
                        Text(context.tr('rides_passenger_count'), style: const TextStyle(fontWeight: FontWeight.w700)),
                        const Spacer(),
                        _CounterButton(
                          icon: Icons.remove,
                          filled: false,
                          onPressed: _passengers > 1 ? () => setState(() => _passengers--) : null,
                        ),
                        SizedBox(
                          width: 28,
                          child: Text('$_passengers', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                        ),
                        _CounterButton(
                          icon: Icons.add,
                          filled: true,
                          onPressed: _passengers < 4 ? () => setState(() => _passengers++) : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _sectionLabel(context.tr('rides_section_service_payment')),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: context.surfaceColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.borderColor),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final tier in const ['regular', 'clean', 'ac', 'modern'])
                            SelectablePill(
                              label: '${_tierShortLabels[tier]!}'
                                  '${tier == 'regular' ? '' : ' (+${(((qualityMultiplier[tier] ?? 1) - 1) * 100).round()}%)'}',
                              selected: _qualityTier == tier,
                              onTap: () => setState(() => _qualityTier = tier),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                      child: Text(
                        context.tr('rides_tier_change_warning'),
                        style: const TextStyle(fontSize: 9.5, color: AppColors.textFaint, height: 1.3),
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          SelectablePill(label: context.tr('rides_payment_cash'), selected: _payment == 'cash', onTap: () => setState(() => _payment = 'cash')),
                          SelectablePill(label: context.tr('rides_payment_wallet'), selected: false, enabled: false, onTap: () {}),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      value: _negotiable,
                      onChanged: (v) => setState(() => _negotiable = v),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      activeThumbColor: AppColors.primary,
                      title: Text(context.tr('rides_negotiable_title'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      subtitle: Text(
                        context.tr('rides_negotiable_subtitle'),
                        style: const TextStyle(fontSize: 10.5, color: AppColors.primaryDark, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              if (_straightKm > 0) ...[
                _sectionLabel(context.tr('rides_section_fare_summary')),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppColors.primary, AppColors.primaryDark], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 6))],
                  ),
                  child: Column(
                    children: [
                      if (_negotiable)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            context.tr('rides_negotiable_notice'),
                            style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      if (_isExternal)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            context.tr('rides_external_notice'),
                            style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      if (_surgeMult > 1)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            '${context.tr('rides_surge_notice_prefix')}${_surgeMult.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 11, color: Color(0xFFFCA5A5), fontWeight: FontWeight.w800),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      if (_hasMultiStop)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            '${context.tr('rides_multistop_notice_prefix')} (${_filledPoints.length - 1} ${context.tr('rides_multistop_notice_stop_unit')}) — ${context.tr('rides_multistop_notice_suffix')}',
                            style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      if (_routeLoading)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              context.tr('rides_route_loading'),
                              style: const TextStyle(fontSize: 12.5, color: Colors.white, fontWeight: FontWeight.w700),
                            ),
                          ],
                        )
                      else
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _statColumn('${(_roadKm).toStringAsFixed(1)} كم', context.tr('rides_stat_distance')),
                            _statColumn('$_eta دقيقة', context.tr('rides_stat_eta')),
                            _statColumn('$_fare ج.م', context.tr('rides_stat_fare'), highlighted: true),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
              if (FeatureFlags.scheduledRidesEnabled && !_negotiable) ...[
                const SizedBox(height: 12),
                InkWell(
                  onTap: _pickScheduleTime,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: _scheduledAt != null ? AppColors.primary.withValues(alpha: 0.08) : context.surfaceColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _scheduledAt != null ? AppColors.primary : context.borderColor),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.event_available, size: 18, color: AppColors.primaryDark),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _scheduledAt == null
                                ? context.tr('rides_schedule_later')
                                : '${context.tr('rides_scheduled_for_prefix')} ${_scheduledAt!.day}/${_scheduledAt!.month} — ${_scheduledAt!.hour.toString().padLeft(2, '0')}:${_scheduledAt!.minute.toString().padLeft(2, '0')}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (_scheduledAt != null)
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => setState(() => _scheduledAt = null),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              if (FeatureFlags.couponsEnabled && _fare > 0 && _session != null) ...[
                const SizedBox(height: 12),
                CouponField(
                  phone: _session!.phone,
                  amount: _fare.toDouble(),
                  serviceType: 'ride',
                  onChanged: (code, check) => setState(() => _appliedCouponCode = check != null ? code : null),
                ),
              ],
              const SizedBox(height: 10),
              // Gold gradient CTA (design canvas) — sets the primary booking
              // action visually apart from the teal used everywhere else on
              // the screen (header, fare summary, selected pills).
              Container(
                decoration: BoxDecoration(
                  gradient: ready ? const LinearGradient(colors: [Color(0xFFD4A24C), AppColors.accent]) : null,
                  color: ready ? null : context.borderColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: ready ? [BoxShadow(color: AppColors.accent.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 8))] : null,
                ),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    disabledBackgroundColor: Colors.transparent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: ready ? _submit : null,
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          _scheduledAt != null
                              ? context.tr('rides_submit_schedule')
                              : (_negotiable ? context.tr('rides_submit_negotiable') : context.tr('rides_submit_now')),
                          style: TextStyle(color: ready ? Colors.white : AppColors.textFaint, fontWeight: FontWeight.w900, fontSize: 15),
                        ),
                ),
              ),
            ],
          ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Signature branded header (design direction "ب") — BrandedHeader with
  /// the personal greeting as title + city as subtitle, plus the
  /// "my scheduled rides" action. See shared/widgets/branded_header.dart
  /// for why every other screen uses the same shell.
  Widget _buildHeader(BuildContext context) {
    return BrandedHeader(
      title: '${context.tr('home_greeting_prefix')} ${_session?.name.isNotEmpty == true ? _session!.name : context.tr('home_greeting_default_name')} 👋',
      subtitle: _session?.city,
      trailing: FeatureFlags.scheduledRidesEnabled && _session != null
          ? IconButton(
              tooltip: context.tr('rides_my_scheduled_rides'),
              icon: const Icon(Icons.event_available, color: Colors.white),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ScheduledRidesScreen(phone: _session!.phone)),
              ),
            )
          : null,
    );
  }

  /// The design canvas's "live status card" element (design direction ب)
  /// — a real, live number (db/security-91) rather than a fabricated one:
  /// only renders when there's at least one genuinely available driver
  /// right now, so it never shows a misleading "0 سائق متاح".
  Widget _buildAvailableDriversCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.borderColor),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.success),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$_availableDrivers ${context.tr('rides_available_drivers_suffix')}',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            context.tr('rides_available_drivers_live_badge'),
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: AppColors.accent),
          ),
        ],
      ),
    );
  }

  Widget _statColumn(String value, String label, {bool highlighted = false}) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: highlighted ? 18 : 15, color: highlighted ? AppColors.accent : Colors.white)),
        Text(label, style: const TextStyle(fontSize: 10.5, color: Colors.white70, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, right: 4),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
      );
}

/// Small circular +/- button for the passenger counter — a filled teal
/// circle for "+" and a light outlined circle for "-", matching the design
/// canvas's rounded counter treatment instead of plain Material icon
/// buttons.
class _CounterButton extends StatelessWidget {
  final IconData icon;
  final bool filled;
  final VoidCallback? onPressed;
  const _CounterButton({required this.icon, required this.filled, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      label: icon == Icons.add ? context.tr('rides_passenger_increase') : context.tr('rides_passenger_decrease'),
      child: Material(
        color: filled ? (enabled ? AppColors.primary : AppColors.primary.withValues(alpha: 0.35)) : context.mutedSurface,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 28,
            height: 28,
            child: Icon(icon, size: 16, color: filled ? Colors.white : (enabled ? AppColors.textFaint : AppColors.textFaint.withValues(alpha: 0.4))),
          ),
        ),
      ),
    );
  }
}
