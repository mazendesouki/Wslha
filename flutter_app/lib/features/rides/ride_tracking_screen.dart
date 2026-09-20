import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../core/contact_launcher.dart';
import '../../core/date_format_ar.dart';
import '../../core/feature_flags.dart';
import '../../core/i18n.dart';
import '../../core/location_share.dart';
import '../../core/maps_launcher.dart';
import '../../core/notifications.dart';
import '../../core/pricing_settings.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../shared/widgets/finish_ride_button.dart';
import '../../shared/widgets/live_tracking_map.dart';
import '../../shared/widgets/sos_button.dart';
import '../../shared/widgets/waiting_timer_card.dart';
import '../airport/airport_fare.dart' show qualityLabels;
import '../driver/driver_repository.dart';
import '../favorites/favorite_driver_button.dart';
import '../ratings/rate_sheet.dart';
import '../ratings/ratings_repository.dart';
import '../ratings/trust_badge.dart';
import 'directions_service.dart';
import 'fare_calculator.dart' show haversineKm, roadFactor;
import 'places_service.dart' show PlaceResult;
import 'ride_chat_screen.dart';
import 'ride_repository.dart';

const Set<String> _liveTrackStatuses = {'accepted', 'arrived', 'in_progress'};

// Passing isDriverView flips the driver-facing card off (a driver looking at
// their own trip shouldn't see a "call the driver" card pointing at
// themselves) and shows the customer's contact info instead.

/// Same status → message mapping as track.astro's notifyStatusChange().
/// Kept as a set (not a Map<String,String>) since the actual text is now
/// looked up via context.tr('ride_tracking_notif_<status>') at the point of
/// use — this top-level const has no BuildContext to translate with.
const Set<String> _statusNotifKeys = {'accepted', 'arrived', 'in_progress', 'completed', 'cancelled'};

/// Ordered ride statuses (rides.astro / driver-dashboard.astro write these
/// same values to rides.status), mirrored on the icon timeline below —
/// same visual language as the web's track.astro "HungerStation-style"
/// timeline (icon steps + progress bar + ETA card), just without the live
/// map/rating modules, which are a bigger Phase-2 scope.
const List<_Step> _steps = [
  _Step('pending', '📋'),
  _Step('accepted', '🚗'),
  _Step('arrived', '📍'),
  _Step('in_progress', '🛣️'),
  _Step('completed', '✅'),
];

class _Step {
  final String key;
  final String icon;
  const _Step(this.key, this.icon);
}

// step.label was a hardcoded Arabic string on the const above; there is no
// BuildContext at const-init time, so the label is now resolved here from
// context.tr('ride_tracking_step_<key>') wherever a step is displayed.
String _stepLabel(BuildContext context, String key) => context.tr('ride_tracking_step_$key');

class RideTrackingScreen extends StatefulWidget {
  final String rideId;
  final bool isDriverView;
  /// Driver view only — called right before popping once the ride is
  /// finished, so the caller (driver_orders_screen.dart) can jump back to
  /// the home tab where a ready queue (if any) is waiting instead of
  /// leaving the driver looking at the history list they came from.
  final VoidCallback? onFinished;
  const RideTrackingScreen({super.key, required this.rideId, this.isDriverView = false, this.onFinished});

  @override
  State<RideTrackingScreen> createState() => _RideTrackingScreenState();
}

class _RideTrackingScreenState extends State<RideTrackingScreen> {
  final _rideRepo = RideRepository();
  final _driverRepo = DriverRepository();
  final _ratingsRepo = RatingsRepository();
  bool _ratingPrompted = false;

  // Cached by driver phone so the lookup only fires once per assigned
  // driver, not on every Realtime tick of the ride row.
  String? _driverProfilePhone;
  Future<Map<String, dynamic>?>? _driverProfileFuture;

  // Tracks the last status we already notified for, so a notification only
  // fires on an actual transition (not on every Realtime tick that repeats
  // the same status) — mirrors track.astro's `lastStatus` check.
  String? _lastNotifiedStatus;

  // Own phone, needed to settle commission on completion — only fetched
  // for the driver view (see _advance()); a customer viewing their own
  // ride never needs it.
  String? _myPhone;
  bool _advancing = false;

  @override
  void initState() {
    super.initState();
    if (widget.isDriverView) {
      SessionStore.load().then((s) {
        if (mounted) setState(() => _myPhone = s?.phone);
      });
    }
    // Needed for WaitingTimerCard's grace-period/fee display (admin-
    // configurable, db/security-63) to show the real numbers instead of
    // the hardcoded fallback defaults.
    PricingSettings.refresh().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _maybePromptRating(String driverPhone, String? customerPhone) async {
    if (!mounted) return;
    final already = await _ratingsRepo.hasRatedRide(widget.rideId);
    if (already || !mounted) return;
    final result = await RateSheet.show(
      context,
      title: context.tr('ride_tracking_rate_title'),
      subtitle: context.tr('ride_tracking_rate_subtitle'),
      positiveTags: positiveDriverTags,
      negativeTags: negativeDriverTags,
    );
    if (result == null || !mounted) return;
    try {
      await _ratingsRepo.rateDriver(
        rideId: widget.rideId,
        customerPhone: customerPhone ?? '',
        rating: result.rating,
        tags: result.tags,
        comment: result.comment,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('ride_tracking_rating_thanks'))));
      }
    } catch (e) {
      // Submission can fail server-side (RPC rejects an already-rated or
      // not-yet-completed ride) — surface it instead of staying silent,
      // which looked like the rating just vanished with no feedback.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.tr('ride_tracking_rating_failed_prefix')} $e'), backgroundColor: AppColors.error, duration: const Duration(seconds: 6)),
        );
      }
    }
  }

  int _stepIndex(String status) {
    final i = _steps.indexWhere((s) => s.key == status);
    return i < 0 ? 0 : i;
  }

  /// Same step progression as driver_home_screen.dart's _advanceRide() —
  /// lets the driver work an already-accepted ride from the history list
  /// (طلباتي ورحلاتي), not just the one currently active on the home tab.
  Future<void> _advance(String status) async {
    if (_myPhone == null || _advancing) return;
    setState(() => _advancing = true);
    try {
      switch (status) {
        case 'accepted':
          final (lateMinutes, feeApplied) = await _driverRepo.markRideArrived(widget.rideId, _myPhone!);
          if (feeApplied && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${context.tr('ride_tracking_late_fee_prefix')} $lateMinutes ${context.tr('ride_tracking_late_fee_suffix')}'),
                backgroundColor: AppColors.error,
                duration: const Duration(seconds: 6),
              ),
            );
          }
          break;
        case 'arrived':
          await _driverRepo.markRideInProgress(widget.rideId, _myPhone!);
          break;
        default:
          final settlement = await _driverRepo.completeRide(widget.rideId, _myPhone!);
          if (!mounted) return;
          if (settlement != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${context.tr('ride_tracking_earnings_prefix')} ${settlement.driverEarn.toStringAsFixed(0)} ج.م'), duration: const Duration(seconds: 4)),
            );
          }
          widget.onFinished?.call();
          Navigator.of(context).pop();
          return;
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${context.tr('ride_tracking_error_prefix')} $e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _advancing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.mutedSurface,
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _rideRepo.watchRide(widget.rideId),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          final ride = snapshot.data!.first;
          final status = ride['status'] as String? ?? 'pending';
          final isCancelled = status == 'cancelled';
          final driverName = ride['driver_name'] as String?;
          final driverPhone = ride['driver_phone'] as String?;
          final customerName = ride['customer_name'] as String?;
          final customerPhone = ride['customer_phone'] as String?;
          final curIdx = _stepIndex(status);

          final qualityTier = ride['airport_quality_tier'] as String?;
          if (!widget.isDriverView &&
              _lastNotifiedStatus != null &&
              _lastNotifiedStatus != status &&
              _statusNotifKeys.contains(status)) {
            // accept_dispatch_offer() already refused this driver server-side
            // if their car didn't match the requested tier — so an
            // "accepted" ride here always genuinely has it. Naming that
            // explicitly (instead of a generic "قبِل السائق طلبك") is what
            // was asked for: the customer should see confirmation the
            // service they picked and paid extra for is actually coming.
            final msg = (status == 'accepted' && qualityTier != null && qualityTier != 'regular')
                ? '${context.tr('ride_tracking_tier_confirmed_notif_prefix')} "${qualityLabels[qualityTier] ?? qualityTier}" ${context.tr('ride_tracking_tier_confirmed_notif_suffix')}'
                : context.tr('ride_tracking_notif_$status');
            AppNotifications.instance.show('وصّلها — ${context.tr('ride_tracking_notif_title_suffix')}', msg);
          }
          _lastNotifiedStatus = status;

          if (!widget.isDriverView && status == 'completed' && !_ratingPrompted && driverPhone != null && driverPhone.isNotEmpty) {
            _ratingPrompted = true;
            // Same "فاتورة الرحلة" the driver already sees on completion
            // (driver_home_screen.dart's _ReceiptDialog) — shown here too,
            // minus the app's commission cut, which is between the
            // platform and the driver, not something the customer needs
            // to see. Shown first, then chains into the existing rating
            // prompt once dismissed.
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (!mounted) return;
              await showDialog(context: context, builder: (_) => _CustomerInvoiceDialog(ride: ride));
              if (!mounted) return;
              _maybePromptRating(driverPhone, customerPhone);
            });
          }

          if (!widget.isDriverView) {
            if (driverPhone != null && driverPhone.isNotEmpty && driverPhone != _driverProfilePhone) {
              _driverProfilePhone = driverPhone;
              _driverProfileFuture = _rideRepo.fetchDriverProfile(driverPhone);
            } else if (driverPhone == null || driverPhone.isEmpty) {
              _driverProfilePhone = null;
              _driverProfileFuture = null;
            }
          }

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: isCancelled ? AppColors.error : AppColors.primary,
                foregroundColor: Colors.white,
                title: Text(widget.isDriverView ? context.tr('ride_tracking_title_driver') : context.tr('ride_tracking_title_customer')),
                actions: [
                  if (FeatureFlags.chatEnabled && !isCancelled && status != 'completed' && driverPhone != null && driverPhone.isNotEmpty)
                    IconButton(
                      onPressed: () {
                        final myPhone = widget.isDriverView ? driverPhone : customerPhone;
                        if (myPhone == null || myPhone.isEmpty) return;
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => RideChatScreen(
                            rideId: widget.rideId,
                            myPhone: myPhone,
                            myRole: widget.isDriverView ? 'driver' : 'customer',
                            otherPartyName: widget.isDriverView
                                ? (customerName ?? context.tr('ride_tracking_default_customer_name'))
                                : (driverName ?? context.tr('ride_tracking_default_driver_name')),
                          ),
                        ));
                      },
                      icon: const Icon(Icons.chat_bubble_outline),
                      tooltip: context.tr('ride_tracking_chat_tooltip'),
                    ),
                  if (!isCancelled && status != 'completed' && status != 'pending')
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: SosButton(role: widget.isDriverView ? 'driver' : 'customer', rideId: widget.rideId),
                    ),
                ],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                        decoration: BoxDecoration(
                          color: context.surfaceColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: context.borderColor),
                          boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4))],
                        ),
                        child: isCancelled
                            ? Column(
                                children: [
                                  const Text('❌', style: TextStyle(fontSize: 32)),
                                  const SizedBox(height: 8),
                                  Text(context.tr('ride_tracking_cancelled_title'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.error)),
                                ],
                              )
                            : _Timeline(curIdx: curIdx),
                      ),
                      const SizedBox(height: 16),
                      if (!isCancelled) _EtaCard(status: status),
                      if (!isCancelled && !widget.isDriverView && status == 'accepted') ...[
                        const SizedBox(height: 12),
                        _ArrivalDeadlineCard(acceptedAt: ride['accepted_at'] as String?, etaMinutes: ride['eta_minutes'] as num?),
                      ],
                      // Shown to both sides, right when the ride is
                      // accepted — before the waiting period actually
                      // starts (that only begins once the driver marks
                      // arrived) — so both know the rule up front instead
                      // of finding out from a live counter after the fact.
                      if (!isCancelled && status == 'accepted') ...[
                        const SizedBox(height: 12),
                        _WaitingRulesNoticeCard(isDriverView: widget.isDriverView),
                      ],
                      if (!isCancelled && status == 'arrived' && ride['arrived_at'] != null) ...[
                        const SizedBox(height: 12),
                        WaitingTimerCard(
                          arrivedAt: DateTime.parse(ride['arrived_at'] as String).toLocal(),
                          isCustomerView: !widget.isDriverView,
                        ),
                      ],
                      if (!isCancelled &&
                          !widget.isDriverView &&
                          status == 'accepted' &&
                          qualityTier != null &&
                          qualityTier != 'regular') ...[
                        const SizedBox(height: 12),
                        _TierConfirmedCard(tierLabel: qualityLabels[qualityTier] ?? qualityTier),
                      ],
                      if (!isCancelled &&
                          !widget.isDriverView &&
                          ride['is_negotiable'] == true &&
                          status == 'pending' &&
                          (driverPhone == null || driverPhone.isEmpty)) ...[
                        const SizedBox(height: 16),
                        _OffersPanel(
                          rideRepo: _rideRepo,
                          rideId: widget.rideId,
                          customerPhone: customerPhone ?? '',
                        ),
                      ],
                      // Fixed-price rides go through the dispatch engine
                      // (server/index.js), which offers the ride to one
                      // nearby driver at a time with its own 30s countdown
                      // — a driver sees that timer, but the customer
                      // previously saw nothing at all while this cycled
                      // through several drivers, with no way to tell
                      // "still working on it" from "stuck", which is
                      // exactly why they'd give up and cancel manually.
                      if (!isCancelled &&
                          !widget.isDriverView &&
                          ride['is_negotiable'] != true &&
                          status == 'pending' &&
                          (driverPhone == null || driverPhone.isEmpty)) ...[
                        const SizedBox(height: 16),
                        _SearchingForDriverCard(createdAt: ride['created_at'] as String?),
                      ],
                      if (!isCancelled &&
                          !widget.isDriverView &&
                          driverPhone != null &&
                          driverPhone.isNotEmpty &&
                          _liveTrackStatuses.contains(status)) ...[
                        const SizedBox(height: 16),
                        _LiveMapSection(rideRepo: _rideRepo, driverPhone: driverPhone, ride: ride),
                      ],
                      if (!isCancelled && !widget.isDriverView && _driverProfileFuture != null) ...[
                        const SizedBox(height: 16),
                        FutureBuilder<Map<String, dynamic>?>(
                          future: _driverProfileFuture,
                          builder: (context, snap) {
                            if (snap.connectionState != ConnectionState.done) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                                ),
                              );
                            }
                            final profile = snap.data;
                            if (profile == null) return const SizedBox.shrink();
                            return _DriverCard(profile: profile, fallbackName: driverName, driverPhone: driverPhone);
                          },
                        ),
                      ],
                      if (widget.isDriverView && customerPhone != null && customerPhone.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _CustomerCard(name: customerName, phone: customerPhone),
                      ],
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: context.surfaceColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: context.borderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _infoRow(context.tr('ride_tracking_from_label'), '${ride['from_area'] ?? '—'}'),
                            if ((ride['stops'] as List?)?.isNotEmpty == true) ...[
                              const Divider(height: 20),
                              _infoRow(
                                context.tr('ride_tracking_stop_at_label'),
                                (ride['stops'] as List)
                                    .map((s) => (s as Map?)?['name'] as String? ?? '—')
                                    .join(' ← '),
                              ),
                            ],
                            const Divider(height: 20),
                            _infoRow(context.tr('ride_tracking_to_label'), '${ride['to_area'] ?? '—'}'),
                            const Divider(height: 20),
                            _infoRow(context.tr('ride_tracking_driver_label'), driverName?.isNotEmpty == true ? driverName! : context.tr('ride_tracking_assigning_driver')),
                            const Divider(height: 20),
                            _infoRow(context.tr('ride_tracking_fare_label'), '${ride['fare'] ?? 0} ج.م', highlight: true),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (FeatureFlags.rideShareEnabled && !widget.isDriverView && !isCancelled && status != 'completed') ...[
                        OutlinedButton.icon(
                          onPressed: () => shareRideTracking(
                            rideId: widget.rideId,
                            fromArea: ride['from_area'] as String?,
                            toArea: ride['to_area'] as String?,
                            driverName: driverName,
                          ),
                          icon: const Icon(Icons.family_restroom),
                          label: Text(context.tr('ride_tracking_share_with_family')),
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (!widget.isDriverView && (status == 'pending' || status == 'accepted' || status == 'arrived'))
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            side: const BorderSide(color: AppColors.error),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: Text(context.tr('ride_tracking_cancel_confirm_title')),
                                content: Text(context.tr('ride_tracking_cancel_confirm_body')),
                                actions: [
                                  TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(context.tr('ride_tracking_cancel_back'))),
                                  TextButton(
                                    onPressed: () => Navigator.of(context).pop(true),
                                    child: Text(context.tr('ride_tracking_cancel_confirm_action'), style: const TextStyle(color: AppColors.error)),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed != true || !context.mounted) return;
                            final customerPhone = ride['customer_phone'] as String? ?? '';
                            final error = await _rideRepo.cancelRide(widget.rideId, customerPhone);
                            if (!context.mounted) return;
                            if (error != null) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
                              return;
                            }
                            Navigator.of(context).pop();
                          },
                          child: Text(context.tr('ride_tracking_cancel_button')),
                        ),
                      if (widget.isDriverView && !isCancelled && status != 'completed' && status != 'pending')
                        _DriverStepButton(
                          status: status,
                          busy: _advancing,
                          onTap: () => _advance(status),
                          driverPhone: _myPhone,
                          destinationLat: (ride['to_lat'] as num?)?.toDouble(),
                          destinationLng: (ride['to_lng'] as num?)?.toDouble(),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool highlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textFaint, fontWeight: FontWeight.w700)),
        Text(
          value,
          style: TextStyle(
            fontSize: highlight ? 16 : 13,
            fontWeight: FontWeight.w900,
            color: highlight ? AppColors.success : context.bodyText,
          ),
        ),
      ],
    );
  }
}

/// Same label/color progression as driver_home_screen.dart's
/// _RideStepButtons (private there, so re-declared here rather than
/// shared — same visual language either way).
class _DriverStepButton extends StatelessWidget {
  final String status; // accepted | arrived | in_progress
  final bool busy;
  final VoidCallback onTap;
  final String? driverPhone;
  final double? destinationLat;
  final double? destinationLng;
  const _DriverStepButton({
    required this.status,
    required this.busy,
    required this.onTap,
    this.driverPhone,
    this.destinationLat,
    this.destinationLng,
  });

  @override
  Widget build(BuildContext context) {
    if (status != 'accepted' && status != 'arrived' && driverPhone != null && destinationLat != null && destinationLng != null) {
      return FinishRideButton(
        busy: busy,
        onTap: onTap,
        driverPhone: driverPhone!,
        destinationLat: destinationLat!,
        destinationLng: destinationLng!,
      );
    }
    final (label, color) = switch (status) {
      'accepted' => (context.tr('ride_tracking_driver_step_arrived'), AppColors.primaryLight),
      'arrived' => (context.tr('ride_tracking_driver_step_start'), AppColors.primary),
      _ => (context.tr('ride_tracking_driver_step_finish'), AppColors.success),
    };
    final isLight = status == 'accepted';
    return ElevatedButton(
      onPressed: busy ? null : onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: isLight ? AppColors.primary : Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      child: busy
          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
    );
  }
}

/// Interactive live map + "open in Google Maps"/"share my location" actions
/// for the customer, shown while a driver is assigned and the ride hasn't
/// finished yet — lets them see for themselves whether the driver is on
/// the right path, instead of trusting the status text alone.
/// The "assistant" layer on top of the raw live map: a plain-language
/// distance/ETA readout that updates on every location ping (instead of
/// making the customer read the driver's position off the map
/// themselves), plus a one-time "السائق قرّب منك" push once the driver's
/// still-approaching-pickup distance drops under 300m — this is what
/// actually answers "فين السائق دلوقتي؟" instead of just showing a dot.
class _LiveMapSection extends StatefulWidget {
  final RideRepository rideRepo;
  final String driverPhone;
  final Map<String, dynamic> ride;
  const _LiveMapSection({required this.rideRepo, required this.driverPhone, required this.ride});

  @override
  State<_LiveMapSection> createState() => _LiveMapSectionState();
}

class _LiveMapSectionState extends State<_LiveMapSection> {
  bool _nearAlertSent = false;

  // Same real-routing preference + debounce pattern as driver_home_screen.
  // dart's _DriverDistanceReadout (see that widget's doc comment) — the
  // driver's live GPS ping stream can fire every few seconds, so a real
  // Directions API fetch only happens after a >300m move or 30s, falling
  // back to haversine × roadFactor in between and before the first result.
  final _directionsService = DirectionsService();
  RoadRoute? _routedRoute;
  double? _routedForLat;
  double? _routedForLng;
  LatLng? _routedForTarget;
  DateTime? _routedAt;

  double? _num(dynamic v) => v == null ? null : (v as num).toDouble();

  void _maybeFetchRoute(double lat, double lng, LatLng target) {
    final targetChanged = _routedForTarget != target;
    final movedFar = targetChanged || _routedForLat == null || haversineKm(lat, lng, _routedForLat!, _routedForLng!) > 0.3;
    final stale = _routedAt == null || DateTime.now().difference(_routedAt!) > const Duration(seconds: 30);
    if (!movedFar && !stale) return;
    _routedForLat = lat;
    _routedForLng = lng;
    _routedForTarget = target;
    _routedAt = DateTime.now();
    _directionsService.fetchRoadRoute([PlaceResult('', lat, lng), PlaceResult('', target.latitude, target.longitude)]).then((route) {
      if (!mounted || route == null) return;
      setState(() => _routedRoute = route);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ride = widget.ride;
    final fromLat = _num(ride['from_lat']);
    final fromLng = _num(ride['from_lng']);
    final toLat = _num(ride['to_lat']);
    final toLng = _num(ride['to_lng']);
    if (fromLat == null || fromLng == null || toLat == null || toLng == null) return const SizedBox.shrink();
    final origin = LatLng(fromLat, fromLng);
    final destination = LatLng(toLat, toLng);
    final status = ride['status'] as String? ?? 'accepted';
    // Before pickup the driver is heading to the customer; after pickup
    // they're heading to the drop-off — the readout should always track
    // whichever leg is actually happening right now.
    final headingToPickup = status == 'accepted' || status == 'arrived';
    final target = headingToPickup ? origin : destination;

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: widget.rideRepo.watchDriverLocation(widget.driverPhone),
      builder: (context, snap) {
        final loc = (snap.data != null && snap.data!.isNotEmpty) ? snap.data!.first : null;
        final driverLat = _num(loc?['lat']);
        final driverLng = _num(loc?['lng']);
        final driverHeading = _num(loc?['heading']);
        final driverPos = (driverLat != null && driverLng != null) ? LatLng(driverLat, driverLng) : null;

        String? readout;
        if (driverPos != null && status != 'arrived') {
          WidgetsBinding.instance.addPostFrameCallback((_) => _maybeFetchRoute(driverPos.latitude, driverPos.longitude, target));
          final routed = _routedForTarget == target ? _routedRoute : null;
          final distanceKm = routed?.km ?? (haversineKm(driverPos.latitude, driverPos.longitude, target.latitude, target.longitude) * roadFactor);
          final distanceM = distanceKm * 1000;
          final etaMin = routed?.minutes ?? (distanceKm / 25 * 60).ceil().clamp(1, 999); // ~25 km/h city average fallback
          final distanceLabel = distanceM < 1000 ? '${distanceM.round()} م' : '${distanceKm.toStringAsFixed(1)} كم';
          readout = headingToPickup
              ? '${context.tr('ride_tracking_driver_near_pickup_prefix')} $distanceLabel ${context.tr('ride_tracking_driver_near_pickup_suffix')}$etaMin ${context.tr('ride_tracking_minutes_unit')}'
              : '${context.tr('ride_tracking_driver_near_dest_prefix')} $distanceLabel ${context.tr('ride_tracking_driver_near_dest_suffix')}$etaMin ${context.tr('ride_tracking_minutes_unit')}';

          // TEMPORARY test threshold — the tester's phone GPS is ~1,646 km
          // from the pickup coordinates used in test rides, so the real
          // 300m trigger can never fire during testing. Widened here only
          // to confirm the notification/sound mechanics work at all;
          // revert to 300 once that's confirmed.
          if (headingToPickup && distanceM < 2000000 && !_nearAlertSent) {
            _nearAlertSent = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              AppNotifications.instance.show('وصّلها', context.tr('ride_tracking_driver_getting_close'), channelId: 'wslha_proximity_v3');
            });
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.borderColor),
                boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4))],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                    child: Row(
                      children: [
                        const Text('🚖', style: TextStyle(fontSize: 14)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            readout ?? context.tr('ride_tracking_driver_on_map'),
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  LiveTrackingMap(driverPosition: driverPos, driverHeading: driverHeading, origin: origin, destination: destination),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => openMapsNavigation(
                      driverPos?.latitude ?? destination.latitude,
                      driverPos?.longitude ?? destination.longitude,
                    ),
                    icon: const Icon(Icons.map_outlined),
                    label: Text(context.tr('ride_tracking_open_google_maps')),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => shareLocationOnWhatsApp(),
                    icon: const Icon(Icons.share_location_outlined),
                    label: Text(context.tr('ride_tracking_share_location')),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _Timeline extends StatelessWidget {
  final int curIdx;
  const _Timeline({required this.curIdx});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(_steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          final segDone = (i ~/ 2) < curIdx;
          return Expanded(
            child: Container(height: 3, color: segDone ? AppColors.primary : const Color(0xFFE5E7EB)),
          );
        }
        final idx = i ~/ 2;
        final step = _steps[idx];
        final done = idx < curIdx;
        final active = idx == curIdx;
        final bg = done || active ? AppColors.primary : context.surfaceColor;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: bg,
                border: Border.all(color: done || active ? AppColors.primary : const Color(0xFFE5E7EB), width: 2.5),
                boxShadow: active
                    ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 10, spreadRadius: 2)]
                    : null,
              ),
              alignment: Alignment.center,
              child: Text(step.icon, style: TextStyle(fontSize: 16, color: done || active ? Colors.white : null)),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 56,
              child: Text(
                _stepLabel(context, step.key),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: done || active ? context.bodyText : AppColors.textFaint,
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _DriverCard extends StatelessWidget {
  final Map<String, dynamic> profile;
  final String? fallbackName;
  final String? driverPhone;
  const _DriverCard({required this.profile, required this.fallbackName, required this.driverPhone});

  @override
  Widget build(BuildContext context) {
    final name = (profile['full_name'] as String?)?.trim();
    final photoUrl = profile['driver_photo_url'] as String?;
    final vehicleCategory = profile['vehicle_category'] as String?;
    final vehicleModel = profile['vehicle_model'] as String?;
    final vehicleColor = profile['vehicle_color'] as String?;
    final vehicleYear = profile['vehicle_year'];
    final regNumber = profile['vehicle_reg_number'] as String?;
    final carPhotoUrl = profile['vehicle_front_url'] as String?;
    final hasAc = profile['has_ac'] == true;
    final isClean = profile['is_clean'] == true;

    final categoryLabels = {
      'sedan': context.tr('ride_tracking_vehicle_category_sedan'),
      'suv': context.tr('ride_tracking_vehicle_category_suv'),
      'van': context.tr('ride_tracking_vehicle_category_van'),
    };
    final carLine = [
      categoryLabels[vehicleCategory] ?? vehicleCategory,
      vehicleColor,
      vehicleModel,
      if (vehicleYear != null) '$vehicleYear',
    ].where((s) => s != null && s.isNotEmpty).join(' — ');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.primaryLight,
                backgroundImage: (photoUrl != null && photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null,
                child: (photoUrl == null || photoUrl.isEmpty)
                    ? const Text('🧑‍✈️', style: TextStyle(fontSize: 22))
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (name != null && name.isNotEmpty) ? name : (fallbackName ?? context.tr('ride_tracking_default_driver_name')),
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: context.bodyText),
                    ),
                    if (carLine.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(carLine, style: const TextStyle(fontSize: 12, color: AppColors.textFaint, fontWeight: FontWeight.w700)),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      (regNumber != null && regNumber.isNotEmpty) ? '🚘 $regNumber' : context.tr('ride_tracking_reg_number_missing'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: (regNumber != null && regNumber.isNotEmpty) ? context.bodyText : AppColors.textFaint,
                      ),
                    ),
                    if (driverPhone != null && driverPhone!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          TrustBadge(
                            future: RatingsRepository().driverTrustBadge(driverPhone!),
                            trustedLabel: context.tr('ride_tracking_trusted_driver'),
                          ),
                          _DriverLevelBadge(driverPhone: driverPhone!),
                          _DriverTripCountBadge(driverPhone: driverPhone!),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (driverPhone != null && driverPhone!.isNotEmpty) ...[
                FavoriteDriverButton(driverPhone: driverPhone!),
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(12)),
                  child: IconButton(
                    onPressed: () => callPhone(driverPhone!),
                    icon: const Icon(Icons.call, color: AppColors.success),
                    tooltip: context.tr('ride_tracking_call_driver_tooltip'),
                  ),
                ),
              ],
            ],
          ),
          if (hasAc || isClean) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              children: [
                if (hasAc) _badge(context.tr('ride_tracking_ac_badge')),
                if (isClean) _badge(context.tr('ride_tracking_clean_badge')),
              ],
            ),
          ],
          if (carPhotoUrl != null && carPhotoUrl.isNotEmpty) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                carPhotoUrl,
                height: 140,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const SizedBox(
                    height: 140,
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _badge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.primary)),
    );
  }
}

/// Same level tiers driver_profile_screen.dart shows the driver about
/// themselves (🌱/🥉/🥈/🥇/💎, based on how many customer ratings they've
/// accumulated) — surfaced here too so the customer sees it before/during
/// the ride, not just the raw "4.8 (23)" number.
class _DriverLevelBadge extends StatelessWidget {
  final String driverPhone;
  const _DriverLevelBadge({required this.driverPhone});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RatingSummary>(
      future: RatingsRepository().driverTrustBadge(driverPhone),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final level = levelForRatingCount(snap.data!.count);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(999)),
          child: Text(
            '${level.emoji} ${level.label}',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.black87),
          ),
        );
      },
    );
  }
}

/// Total completed trips (rides only, same "overall.trips" the driver's own
/// stats tab reads) — lets the customer see this isn't a brand-new driver
/// even if they don't have many ratings yet.
class _DriverTripCountBadge extends StatelessWidget {
  final String driverPhone;
  const _DriverTripCountBadge({required this.driverPhone});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: DriverRepository().fetchTripStats(driverPhone),
      builder: (context, snap) {
        final trips = ((snap.data?['overall'] as Map?)?['trips'] as num?)?.toInt();
        if (trips == null) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(999)),
          child: Text('🚗 $trips ${context.tr('ride_tracking_trip_count_suffix')}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.black87)),
        );
      },
    );
  }
}

class _CustomerCard extends StatelessWidget {
  final String? name;
  final String phone;
  const _CustomerCard({required this.name, required this.phone});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Row(
        children: [
          FutureBuilder<String?>(
            future: RideRepository().fetchAccountAvatar(phone),
            builder: (context, snap) {
              final avatarUrl = snap.data;
              return CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.primaryLight,
                backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty) ? NetworkImage(avatarUrl) : null,
                child: (avatarUrl == null || avatarUrl.isEmpty) ? const Text('🧑', style: TextStyle(fontSize: 20)) : null,
              );
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              (name != null && name!.isNotEmpty) ? name! : context.tr('ride_tracking_default_customer_fallback'),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: context.bodyText),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(left: 6),
            decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(12)),
            child: IconButton(
              onPressed: () => callPhone(phone),
              icon: const Icon(Icons.call, color: AppColors.success),
              tooltip: context.tr('ride_tracking_call_customer_tooltip'),
            ),
          ),
          Container(
            decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(12)),
            child: IconButton(
              onPressed: () => openWhatsApp(phone),
              icon: const Icon(Icons.chat, color: AppColors.success),
              tooltip: context.tr('ride_tracking_whatsapp_tooltip'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Live list of driver price offers on a negotiable ride still waiting for
/// a driver — shown instead of/above the plain "جارٍ التعيين" state while
/// status stays 'pending'. Disappears on its own once a driver is assigned
/// (the outer condition in build() stops rendering it).
class _OffersPanel extends StatefulWidget {
  final RideRepository rideRepo;
  final String rideId;
  final String customerPhone;
  const _OffersPanel({required this.rideRepo, required this.rideId, required this.customerPhone});

  @override
  State<_OffersPanel> createState() => _OffersPanelState();
}

class _OffersPanelState extends State<_OffersPanel> {
  // Tracks which offer is mid-action and which kind, so only that offer's
  // buttons show a spinner (the rest of the list stays interactive).
  String? _busyOfferId;
  bool _busyIsReject = false;

  Future<void> _accept(String offerId) async {
    setState(() { _busyOfferId = offerId; _busyIsReject = false; });
    final error = await widget.rideRepo.acceptPriceOffer(widget.rideId, offerId, widget.customerPhone);
    if (!mounted) return;
    setState(() => _busyOfferId = null);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _reject(String offerId) async {
    setState(() { _busyOfferId = offerId; _busyIsReject = true; });
    final ok = await widget.rideRepo.rejectPriceOffer(widget.rideId, offerId, widget.customerPhone);
    if (!mounted) return;
    setState(() => _busyOfferId = null);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('ride_tracking_offer_reject_failed'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: widget.rideRepo.watchRideOffers(widget.rideId),
      builder: (context, snapshot) {
        final offers = (snapshot.data ?? [])
            .where((o) => o['status'] == 'pending')
            .toList()
          ..sort((a, b) => ((a['offered_price'] as num?) ?? 0).compareTo((b['offered_price'] as num?) ?? 0));

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.borderColor),
            boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Text('🤝', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(context.tr('ride_tracking_offers_title'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                  ),
                  if (offers.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(999)),
                      child: Text('${offers.length}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.primary)),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (offers.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    context.tr('ride_tracking_offers_waiting'),
                    style: const TextStyle(fontSize: 12, color: AppColors.textFaint),
                    textAlign: TextAlign.center,
                  ),
                )
              else
                ...offers.map((o) {
                  final id = o['id'].toString();
                  final price = (o['offered_price'] as num?)?.toStringAsFixed(0) ?? '—';
                  final name = (o['driver_name'] as String?)?.trim();
                  final isBusy = _busyOfferId == id;
                  final anyBusy = _busyOfferId != null;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: context.mutedSurface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const CircleAvatar(
                              radius: 18,
                              backgroundColor: AppColors.primaryLight,
                              child: Text('🧑‍✈️', style: TextStyle(fontSize: 14)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                (name != null && name.isNotEmpty) ? name : context.tr('ride_tracking_offer_driver_fallback'),
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                            ),
                            Text('$price ج.م', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.success, fontSize: 14)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: !anyBusy ? () => _reject(id) : null,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.error,
                                  side: const BorderSide(color: AppColors.error),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                ),
                                child: (isBusy && _busyIsReject)
                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.error))
                                    : Text(context.tr('ride_tracking_offer_reject'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: !anyBusy ? () => _accept(id) : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                ),
                                child: (isBusy && !_busyIsReject)
                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : Text(context.tr('ride_tracking_offer_accept'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}

/// Shown while status='accepted' — the driver is en route but hasn't
/// reached the pickup point yet. Surfaces the same deadline the driver
/// sees on their own active-job card, plus the late-arrival penalty
/// (mark_ride_arrived, db/security-29: 20 ج.م خصم من محفظة السائق لو
/// اتأخر أكتر من 5 دقايق من وقت القبول) so the customer understands why
/// being ready on time at the pickup point matters — the fee lands on
/// the driver, not the customer, but a customer who isn't ready is what
/// usually causes it.
class _ArrivalDeadlineCard extends StatelessWidget {
  final String? acceptedAt;
  final num? etaMinutes;
  const _ArrivalDeadlineCard({required this.acceptedAt, required this.etaMinutes});

  @override
  Widget build(BuildContext context) {
    final accepted = acceptedAt == null ? null : DateTime.tryParse(acceptedAt!)?.toLocal();
    if (accepted == null || etaMinutes == null) return const SizedBox.shrink();
    final deadline = accepted.add(Duration(minutes: etaMinutes!.round()));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        border: Border.all(color: const Color(0xFFFDE68A), width: 1.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🚗', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${context.tr('ride_tracking_expected_arrival_prefix')} ${arTime(deadline)} ${context.tr('ride_tracking_expected_arrival_mid')} ${etaMinutes!.round()} ${context.tr('ride_tracking_minutes_unit')})',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: Colors.black87),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            PricingSettings.driverLateFeeEnabled
                ? '${context.tr('ride_tracking_be_ready_fee_prefix')} ${PricingSettings.driverLateGraceMinutes} ${context.tr('ride_tracking_be_ready_fee_mid')} ${PricingSettings.driverLateFee.toStringAsFixed(0)} ${context.tr('ride_tracking_be_ready_fee_suffix')}'
                : context.tr('ride_tracking_be_ready_plain'),
            style: const TextStyle(fontSize: 11, color: AppColors.textFaint, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// Shown to both sides right when the ride is accepted (before any
/// waiting actually starts) — explains both penalty rules up front:
/// the driver's for arriving late, and the customer's for taking too
/// long to board once the driver's there. Values come from
/// PricingSettings (db/security-63, admin-configurable).
class _WaitingRulesNoticeCard extends StatelessWidget {
  final bool isDriverView;
  const _WaitingRulesNoticeCard({required this.isDriverView});

  @override
  Widget build(BuildContext context) {
    if (isDriverView && !PricingSettings.driverLateFeeEnabled) {
      // Driver-lateness fee is currently switched off by the admin
      // (db/security-64) — nothing to warn the driver about here.
      return const SizedBox.shrink();
    }
    final text = isDriverView
        ? '${context.tr('ride_tracking_driver_late_rule_prefix')} ${PricingSettings.driverLateGraceMinutes} ${context.tr('ride_tracking_driver_late_rule_mid')} ${PricingSettings.driverLateFee.toStringAsFixed(0)} ${context.tr('ride_tracking_driver_late_rule_suffix')}'
        : '${context.tr('ride_tracking_customer_late_rule_prefix')} ${PricingSettings.customerLateGraceMinutes} ${context.tr('ride_tracking_customer_late_rule_mid')} ${PricingSettings.customerLateFeePerMinute.toStringAsFixed(0)} ${context.tr('ride_tracking_customer_late_rule_suffix')}';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          const Text('ℹ️', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 11, color: AppColors.textFaint, fontWeight: FontWeight.w700, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

/// Confirms the paid-for tier is actually coming — accept_dispatch_offer()
/// already refused this driver server-side if their car didn't match, so
/// this is a guarantee, not a hope. In-page (not just the push notification
/// _statusNotif triggers) so it's still visible if the customer missed/
/// dismissed the notification.
class _TierConfirmedCard extends StatelessWidget {
  final String tierLabel;
  const _TierConfirmedCard({required this.tierLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        border: Border.all(color: const Color(0xFFA7F3D0), width: 1.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Text('✅', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${context.tr('ride_tracking_tier_confirmed_card_prefix')} "$tierLabel" ${context.tr('ride_tracking_tier_confirmed_card_suffix')}',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: Color(0xFF065F46)),
            ),
          ),
        ],
      ),
    );
  }
}

// Was a top-level const Map<String,String> keyed by payment method, but its
// values need translation — there's no BuildContext at const-init time, so
// this helper resolves the text at the point of use instead.
String? _paymentLabel(BuildContext context, String? key) {
  if (key == 'cash') return context.tr('ride_tracking_payment_cash');
  if (key == 'wallet') return context.tr('ride_tracking_payment_wallet');
  return null;
}

/// Customer's own copy of the "فاتورة الرحلة" the driver already gets on
/// completion (driver_home_screen.dart's _ReceiptDialog) — same event,
/// deliberately different fields: no commission (that's a platform↔driver
/// split, not the customer's business), and adds the route/distance/
/// date-time/payment-method context a driver's receipt doesn't need.
class _CustomerInvoiceDialog extends StatelessWidget {
  final Map<String, dynamic> ride;
  const _CustomerInvoiceDialog({required this.ride});

  @override
  Widget build(BuildContext context) {
    final fare = ((ride['fare'] as num?) ?? 0).toDouble();
    final tier = ride['airport_quality_tier'] as String?;
    final distanceKm = (ride['distance_km'] as num?)?.toStringAsFixed(1);
    final payment = ride['payment'] as String?;
    final completedAt = DateTime.tryParse(ride['completed_at'] as String? ?? '')?.toLocal();
    final rideId = ride['id']?.toString();
    final customerPhone = ride['customer_phone'] as String?;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          // Only fetched once the ride is already completed (this dialog
          // only ever shows then), by which point any late-boarding fee
          // (charged at the arrived→in_progress transition, db/security-63)
          // has long since been recorded.
          future: (rideId != null) ? RideRepository().fetchRidePenalties(rideId) : Future.value(const []),
          builder: (context, snap) {
            // Filters by note text (not just phone) — if the same phone
            // was used to test both the customer and driver accounts,
            // matching on phone alone would wrongly pull the driver's
            // own late-arrival fee into the customer's invoice.
            final lateFee = (snap.data ?? [])
                .where((p) => p['phone'] == customerPhone && (p['note'] as String? ?? '').contains('انتظار السائق'))
                .fold<double>(0, (sum, p) => sum + ((p['amount'] as num).abs()));
            final total = fare + lateFee;

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: Text('✅', style: TextStyle(fontSize: 40))),
                const SizedBox(height: 8),
                Center(child: Text(context.tr('ride_tracking_invoice_title'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900))),
                const SizedBox(height: 20),
                _row(context.tr('ride_tracking_from_label'), '${ride['from_area'] ?? '—'}'),
                const Divider(height: 22),
                _row(context.tr('ride_tracking_to_label'), '${ride['to_area'] ?? '—'}'),
                if (distanceKm != null) ...[
                  const Divider(height: 22),
                  _row(context.tr('ride_tracking_invoice_distance'), '$distanceKm كم'),
                ],
                if (completedAt != null) ...[
                  const Divider(height: 22),
                  _row(context.tr('ride_tracking_invoice_datetime'), arDateTime(completedAt)),
                ],
                if (tier != null && tier != 'regular') ...[
                  const Divider(height: 22),
                  _row(context.tr('ride_tracking_invoice_service'), qualityLabels[tier] ?? tier),
                ],
                const Divider(height: 22),
                _row(context.tr('ride_tracking_invoice_fare'), '${fare.toStringAsFixed(0)} ج.م'),
                if (lateFee > 0) ...[
                  const Divider(height: 22),
                  _row(context.tr('ride_tracking_invoice_boarding_delay_fee'), '+ ${lateFee.toStringAsFixed(0)} ج.م', color: AppColors.error),
                ],
                if (payment != null) ...[
                  const Divider(height: 22),
                  _row(context.tr('ride_tracking_invoice_payment_method'), _paymentLabel(context, payment) ?? payment),
                ],
                const Divider(height: 22),
                _row(context.tr('ride_tracking_invoice_total_due'), '${total.toStringAsFixed(0)} ج.م', bold: true, color: AppColors.success),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(context.tr('ride_tracking_invoice_ok')),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textFaint, fontWeight: FontWeight.w700)),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: bold ? 17 : 14,
            fontWeight: bold ? FontWeight.w900 : FontWeight.w800,
            color: color ?? Colors.black87,
          ),
        ),
      ],
    );
  }
}

/// Ticks on its own (independent of the ride row's StreamBuilder, which
/// only rebuilds on an actual database change — and nothing changes while
/// this cycles silently through drivers) so the elapsed counter visibly
/// moves instead of looking frozen. Escalates its message/color past 90s
/// as a hint toward the existing "إلغاء الرحلة" button rather than a
/// separate auto-cancel — this app has always left cancellation as an
/// explicit customer choice.
class _SearchingForDriverCard extends StatefulWidget {
  final String? createdAt;
  const _SearchingForDriverCard({required this.createdAt});

  @override
  State<_SearchingForDriverCard> createState() => _SearchingForDriverCardState();
}

class _SearchingForDriverCardState extends State<_SearchingForDriverCard> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final created = widget.createdAt == null ? null : DateTime.tryParse(widget.createdAt!)?.toLocal();
    final elapsedSeconds = created == null ? 0 : DateTime.now().difference(created).inSeconds.clamp(0, 999);
    final longWait = elapsedSeconds >= 90;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: longWait ? const Color(0xFFFFFBEB) : context.surfaceColor,
        border: Border.all(color: longWait ? const Color(0xFFFDE68A) : context.borderColor, width: longWait ? 1.5 : 1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  longWait ? context.tr('ride_tracking_searching_long') : context.tr('ride_tracking_searching'),
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: longWait ? Colors.black87 : context.bodyText),
                ),
              ),
              const SizedBox(width: 8),
              Text('$elapsedSeconds ث', style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
            ],
          ),
          if (longWait) ...[
            const SizedBox(height: 6),
            Text(
              context.tr('ride_tracking_searching_long_hint'),
              style: const TextStyle(fontSize: 11, color: AppColors.textFaint, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

class _EtaCard extends StatelessWidget {
  final String status;
  const _EtaCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, badge, badgeColor) = switch (status) {
      'completed' => (context.tr('ride_tracking_eta_completed_label'), context.tr('ride_tracking_eta_completed_badge'), AppColors.success),
      'in_progress' => (context.tr('ride_tracking_eta_in_progress_label'), context.tr('ride_tracking_eta_in_progress_badge'), AppColors.primary),
      'arrived' => (context.tr('ride_tracking_eta_arrived_label'), context.tr('ride_tracking_eta_arrived_badge'), AppColors.primary),
      'accepted' => (context.tr('ride_tracking_eta_accepted_label'), context.tr('ride_tracking_eta_accepted_badge'), AppColors.primary),
      _ => (context.tr('ride_tracking_eta_pending_label'), context.tr('ride_tracking_eta_pending_badge'), AppColors.textFaint),
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 1.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Text('🕐', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black87)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(999)),
            child: Text(badge, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: badgeColor)),
          ),
        ],
      ),
    );
  }
}
