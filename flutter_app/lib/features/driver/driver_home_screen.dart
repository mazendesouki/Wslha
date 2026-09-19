import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/contact_launcher.dart';
import '../../core/i18n.dart';
import '../../core/date_format_ar.dart';
import '../../core/feature_flags.dart';
import '../../core/maps_launcher.dart';
import '../../core/notifications.dart';
import '../../core/pricing_settings.dart';
import '../../core/push.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../shared/widgets/finish_ride_button.dart';
import '../../shared/widgets/logout_button.dart';
import '../../shared/widgets/sos_button.dart';
import '../../shared/widgets/waiting_timer_card.dart';
import '../airport/airport_fare.dart' as airport_fare;
import '../orders/orders_repository.dart';
import '../ratings/rate_sheet.dart';
import '../ratings/ratings_repository.dart';
import '../ratings/trust_badge.dart';
import '../rides/fare_calculator.dart' show haversineKm;
import '../rides/ride_repository.dart';
import 'active_job_store.dart';
import 'airport_ride_requests_screen.dart';
import 'driver_repository.dart';
import 'negotiation_screen.dart';

/// Visual language ported from driver-dashboard.astro: teal online toggle,
/// pulsing "radar" while idle, a list of 30s-countdown offer cards,
/// sequential trip-progress buttons (arrived → picked up → completed)
/// instead of one generic "finish" button, and a route preview + "open in
/// Google Maps" button for the current leg. Earnings/ratings tabs and the
/// rating modals are bigger Phase-2 scope — same call made for the
/// customer tracking screen's live map earlier. Active/queued-job state
/// itself lives in ActiveJobStore (shared with driver_orders_screen.dart's
/// history list) instead of local fields here.

class DriverHomeScreen extends StatefulWidget {
  final UserSession session;
  const DriverHomeScreen({super.key, required this.session});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  final _repo = DriverRepository();
  final _rideRepo = RideRepository();
  final _ordersRepo = OrdersRepository();
  Timer? _pollTimer;
  Timer? _countdownTimer;
  Timer? _locationTimer;
  StreamSubscription<Map<String, dynamic>>? _offersSub;

  bool _online = false;
  bool _busy = false;
  final _ratingsRepo = RatingsRepository();
  List<PendingOffer> _offers = [];
  String? _actingOnOfferId;
  final _jobs = ActiveJobStore.instance;
  String? _vehicleCategory;

  String get _onlinePrefKey => 'driver_online_${widget.session.phone}';

  @override
  void initState() {
    super.initState();
    _jobs.addListener(_onJobsChanged);
    // Motorcycle/cargo drivers do delivery only — the negotiation entry
    // point (ride requests) is hidden for them; the actual enforcement
    // (never seeing/accepting a ride offer at all) lives server-side.
    _repo.fetchVehicleInfo(widget.session.phone).then((info) {
      if (mounted && info != null) setState(() => _vehicleCategory = info['vehicle_category'] as String?);
    });

    // Restores state that used to be lost every time Android killed the
    // app in the background (e.g. the driver switched to another app
    // mid-ride) and it cold-started fresh on return: the active ride
    // (ActiveJobStore is in-memory only, so it comes back empty on a fresh
    // process) and the online/offline toggle (previously always started
    // off — see the removed comment below — which forced the driver to
    // manually reconnect every single time, not just after a real kill).
    _restoreActiveJob();
    _restoreOnlineStatus();
    // Needed for the waiting-time penalty cards below (grace period/fee,
    // db/security-63) to show the real admin-configured numbers.
    PricingSettings.refresh().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _restoreActiveJob() async {
    if (_jobs.job != null) return;
    final ride = await _rideRepo.findActiveRide(widget.session.phone, asDriver: true).catchError((_) => null);
    if (ride != null) {
      if (!mounted || _jobs.job != null) return;
      _jobs.activate('ride', ride, rideStep: ride['status'] as String? ?? 'accepted');
      return;
    }
    final order = await _ordersRepo.findActiveOrderForDriver(widget.session.phone).catchError((_) => null);
    if (order == null || !mounted || _jobs.job != null) return;
    _jobs.activate('order', order);
    if (order['status'] == 'on_the_way') _jobs.setPickedUp(true);
  }

  /// Auto-reconnecting on every cold start (regardless of prior state) used
  /// to make the app read as "locked" for a few seconds while location
  /// permission/GPS settled, before the driver could do anything — that's
  /// why this used to be fully manual. The difference here: this only
  /// re-runs _toggleOnline(true) when the driver's own last action was
  /// going online (an explicit, saved choice), not unconditionally on
  /// every open — going through the exact same code path (including its
  /// permission-failure Snackbar) rather than a separate, untested one.
  Future<void> _restoreOnlineStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final wasOnline = prefs.getBool(_onlinePrefKey) ?? false;
    if (!wasOnline || !mounted || _online) return;
    await _toggleOnline(true);
  }

  void _onJobsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    _locationTimer?.cancel();
    _offersSub?.cancel();
    _jobs.removeListener(_onJobsChanged);
    super.dispose();
  }

  // Feeds the customer's live tracking map (features/rides/ride_tracking_
  // screen.dart) — goOnline() only sets a starting point, this keeps it
  // moving with the driver.
  void _startLocationPings() {
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (_online) _repo.pingLocation(widget.session.phone);
    });
  }

  // security-21's push trigger fires the instant a dispatch_offers row is
  // inserted for this driver — react to it immediately instead of waiting
  // for the next poll tick. The 5s poll below stays as a fallback for when
  // push isn't set up (no google-services.json) or a message is dropped.
  void _startPushWatch() {
    _offersSub?.cancel();
    _offersSub = PushRegistrar.onMessageData.listen((data) {
      if (data['type'] == 'dispatch_offer') _refreshOffers();
    });
  }

  // Pulls every currently-pending offer (not just one) — a driver mid-job
  // can still be offered (and accept) another, which lands in _jobs.queue
  // instead of replacing what they're currently doing. Shown as a list
  // (see _OffersListPanel) so more than one can sit there at once.
  Future<void> _refreshOffers() async {
    if (!_online) return;
    List<PendingOffer> offers;
    try {
      offers = await _repo.getPendingOffers(widget.session.phone);
    } catch (e) {
      // This runs every 5s — a red "خطأ" bar reappearing on every single
      // transient network blip (a driver moving between cell towers, a
      // momentary DNS hiccup) reads as the app being permanently broken,
      // which is exactly what was reported. Just retry silently on the
      // next tick instead of surfacing each failure; a real, sustained
      // outage still shows up as offers never arriving, same as before.
      return;
    }
    if (!mounted) return;
    final hadIds = _offers.map((o) => o.offerId).toSet();
    final isNew = offers.any((o) => !hadIds.contains(o.offerId));
    if (isNew) HapticFeedback.heavyImpact();
    setState(() => _offers = offers);
    _ensureCountdownTicking();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _refreshOffers());
  }

  // Just a UI heartbeat — each card computes its own remaining time from
  // offer.expiresAt, this only forces a rebuild every second so that
  // countdown actually ticks down on screen.
  void _ensureCountdownTicking() {
    if (_offers.isEmpty) {
      _countdownTimer?.cancel();
      _countdownTimer = null;
      return;
    }
    _countdownTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_offers.isEmpty) {
        _countdownTimer?.cancel();
        _countdownTimer = null;
        return;
      }
      setState(() {});
    });
  }

  Future<void> _toggleOnline(bool value) async {
    setState(() => _busy = true);
    if (value) {
      final ok = await _repo.goOnline(widget.session.phone, widget.session.name);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('driver_home_location_permission_needed'))),
        );
      }
      setState(() {
        _online = ok;
        _busy = false;
      });
      // Persisted so a real app relaunch (not just backgrounding) restores
      // this — see _restoreOnlineStatus() in initState(). Only saved on
      // success: a failed attempt (e.g. permission denied) must not look
      // "online" to the next cold start either.
      (await SharedPreferences.getInstance()).setBool(_onlinePrefKey, ok);
      if (ok) {
        _startPolling();
        _startPushWatch();
        _startLocationPings();
      }
    } else {
      await _repo.goOffline(widget.session.phone);
      _pollTimer?.cancel();
      _offersSub?.cancel();
      _locationTimer?.cancel();
      _countdownTimer?.cancel();
      _countdownTimer = null;
      setState(() {
        _online = false;
        _busy = false;
        _offers = [];
      });
      (await SharedPreferences.getInstance()).setBool(_onlinePrefKey, false);
    }
  }

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${context.tr('driver_home_error_prefix')} $e'), backgroundColor: AppColors.error, duration: const Duration(seconds: 6)),
    );
  }

  void _showReceipt(RideSettlement s, String rideId) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => _ReceiptDialog(settlement: s, rideId: rideId, driverPhone: widget.session.phone),
    );
  }

  Future<void> _accept(PendingOffer offer) async {
    if (_actingOnOfferId != null) return;
    setState(() => _actingOnOfferId = offer.offerId);
    try {
      final result = await _repo.acceptOffer(offer.offerId, widget.session.phone, widget.session.name);
      final ok = result == 'ok';
      if (!mounted) return;
      if (!ok) {
        _showError(
          result == 'vehicle_category_mismatch'
              ? context.tr('driver_home_accept_error_vehicle_mismatch')
              : result == 'quality_tier_mismatch'
                  ? context.tr('driver_home_accept_error_quality_mismatch')
                  : result == 'driver_not_approved'
                      ? context.tr('driver_home_accept_error_not_approved')
                      : context.tr('driver_home_accept_error_generic'),
        );
      }
      setState(() {
        _actingOnOfferId = null;
        _offers = _offers.where((o) => o.offerId != offer.offerId).toList();
        if (ok) {
          // offer.data is a snapshot taken when the offer was CREATED, not
          // when it was accepted just now — accepted_at is still null on
          // it, so _ArrivalDeadlineChip (which needs accepted_at +
          // eta_minutes) silently rendered nothing on the active-job card,
          // even though the customer's own deadline card worked fine
          // (their ride row was fetched live, already carrying the real
          // accepted_at the server just set). Stamping it here with "now"
          // is accurate enough — accept_dispatch_offer() just set it
          // server-side a moment ago.
          final data = {
            ...offer.data,
            'status': 'accepted',
            'accepted_at': DateTime.now().toUtc().toIso8601String(),
          };
          final job = QueuedJob(offer.targetType, data);
          if (_jobs.job == null) {
            _jobs.activate(job.type, job.data);
          } else {
            _jobs.enqueue(job);
          }
        }
      });
      if (ok) _scheduleAirportReminderIfNeeded(offer.data);
      _ensureCountdownTicking();
    } catch (e) {
      _showError(e);
      if (!mounted) return;
      setState(() {
        _actingOnOfferId = null;
        _offers = _offers.where((o) => o.offerId != offer.offerId).toList();
      });
    }
  }

  /// Airport jobs have a real deadline (be at the pickup point/airport by a
  /// specific moment, not just "whenever") — a local reminder 15 min before
  /// that moment so it doesn't get lost among regular ride offers.
  void _scheduleAirportReminderIfNeeded(Map<String, dynamic> data) {
    if (data['ride_type'] != 'airport') return;
    final pickupTime = airport_fare.primaryPickupTime(data);
    if (pickupTime == null) return;
    final rideId = data['id'];
    if (rideId == null) return;
    AppNotifications.instance.scheduleAt(
      rideId.hashCode,
      context.tr('driver_home_airport_reminder_title'),
      context.tr('driver_home_airport_reminder_body'),
      pickupTime.subtract(const Duration(minutes: 15)),
    );
  }

  Future<void> _reject(PendingOffer offer) async {
    if (_actingOnOfferId != null) return;
    setState(() => _actingOnOfferId = offer.offerId);
    try {
      await _repo.rejectOffer(offer.offerId, widget.session.phone);
    } catch (e) {
      _showError(e);
    }
    if (!mounted) return;
    setState(() {
      _actingOnOfferId = null;
      _offers = _offers.where((o) => o.offerId != offer.offerId).toList();
    });
    _ensureCountdownTicking();
  }

  Future<void> _advanceRide() async {
    final job = _jobs.job;
    if (job == null) return;
    final rideId = job['id'].toString();
    setState(() => _busy = true);
    try {
      switch (_jobs.rideStep) {
        case 'accepted':
          final (lateMinutes, feeApplied) = await _repo.markRideArrived(rideId, widget.session.phone);
          if (!mounted) return;
          // Same stale-snapshot issue the accepted_at fix addressed
          // earlier — job's map has no live arrived_at until this is
          // stamped, so WaitingTimerCard below (needs arrived_at) would
          // otherwise never appear right after tapping this button.
          job['arrived_at'] = DateTime.now().toUtc().toIso8601String();
          job['status'] = 'arrived';
          _jobs.setRideStep('arrived');
          setState(() => _busy = false);
          if (feeApplied && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${context.tr('driver_home_late_fee_warning_prefix')} $lateMinutes ${context.tr('driver_home_late_fee_warning_mid')} ${PricingSettings.driverLateFee.toStringAsFixed(0)} ${context.tr('driver_home_late_fee_warning_suffix')}'),
                backgroundColor: AppColors.error,
                duration: const Duration(seconds: 6),
              ),
            );
          }
          return;
        case 'arrived':
          await _repo.markRideInProgress(rideId, widget.session.phone);
          if (!mounted) return;
          // Same stale job['status'] issue as the accepted_at/arrived_at
          // fixes above — WaitingTimerCard's guard checks job['status'],
          // not _jobs.rideStep, so without this the waiting counter kept
          // counting on the driver's screen forever after tapping "ابدأ
          // الرحلة", even though the customer's own copy (driven by the
          // live ride stream) correctly disappeared right away.
          job['status'] = 'in_progress';
          _jobs.setRideStep('in_progress');
          setState(() => _busy = false);
          return;
        default:
          final settlement = await _repo.completeRide(rideId, widget.session.phone);
          if (!mounted) return;
          _jobs.clearActive();
          setState(() => _busy = false);
          if (settlement != null) _showReceipt(settlement, rideId);
          _promptRateCustomer(job, serviceType: 'ride', referenceId: rideId);
      }
    } catch (e) {
      _showError(e);
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  /// "العميل لم يحضر" (db/security-70) — the only way a driver could end a
  /// ride before this was cancel it themselves at all: customer_cancel_ride
  /// (security-40) is customer-only. Frees the driver immediately for
  /// another job and settles a wallet transfer both ways.
  Future<void> _handleNoShow(String rideId) async {
    try {
      final (waited, fee) = await _repo.reportNoShow(rideId, widget.session.phone);
      if (!mounted) return;
      _jobs.clearActive();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${context.tr('driver_home_noshow_success_prefix')} $waited ${context.tr('driver_home_noshow_success_mid')} ${fee.toStringAsFixed(0)} ${context.tr('driver_home_noshow_success_suffix')}'),
      ));
    } catch (e) {
      _showError(e);
    }
  }

  /// Driver→customer, mirroring driver-dashboard.astro's rate-customer
  /// modal — same private "reliability" signal shown to other drivers
  /// before they accept an offer (see _OfferCard).
  Future<void> _promptRateCustomer(Map<String, dynamic> job, {required String serviceType, required String referenceId}) async {
    final customerPhone = job['customer_phone'] as String?;
    if (customerPhone == null || customerPhone.isEmpty || !mounted) return;
    final result = await RateSheet.show(
      context,
      title: context.tr('driver_home_rate_customer_title'),
      subtitle: context.tr('driver_home_rate_customer_subtitle'),
      positiveTags: positiveCustomerTags,
      negativeTags: negativeCustomerTags,
    );
    if (result == null || !mounted) return;
    try {
      await _ratingsRepo.rateCustomer(
        driverPhone: widget.session.phone,
        rating: result.rating,
        serviceType: serviceType,
        referenceId: referenceId,
        tags: result.tags,
        comment: result.comment,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('driver_home_rate_customer_success'))));
      }
    } catch (e) {
      // Same silent-failure pattern as the other two rating flows — the
      // RPC can reject (already rated, reference doesn't belong to this
      // driver, etc.) and nothing said so before this fix.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.tr('driver_home_rate_customer_error_prefix')} $e'), backgroundColor: AppColors.error, duration: const Duration(seconds: 6)),
        );
      }
    }
  }

  Future<void> _advanceOrder() async {
    final job = _jobs.job;
    if (job == null) return;
    final orderId = job['id'].toString();

    if (!_jobs.pickedUp) {
      setState(() => _busy = true);
      try {
        await _repo.markOrderPickedUp(orderId, widget.session.phone);
        if (!mounted) return;
        _jobs.setPickedUp(true);
        setState(() => _busy = false);
      } catch (e) {
        _showError(e);
        if (!mounted) return;
        setState(() => _busy = false);
      }
      return;
    }

    final otp = await _askDeliveryOtp();
    if (otp == null || otp.isEmpty) return; // driver cancelled
    setState(() => _busy = true);
    try {
      final ok = await _repo.confirmOrderDelivery(orderId, widget.session.phone, otp);
      if (!mounted) return;
      if (!ok) {
        setState(() => _busy = false);
        _showError(context.tr('driver_home_otp_prompt_error'));
        return;
      }
      _jobs.clearActive();
      setState(() => _busy = false);
      _promptRateCustomer(job, serviceType: 'delivery', referenceId: orderId);
    } catch (e) {
      _showError(e);
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  Future<String?> _askDeliveryOtp() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('driver_home_otp_dialog_title')),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 4,
          decoration: InputDecoration(
            hintText: context.tr('driver_home_otp_dialog_hint'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.tr('action_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(context.tr('action_confirm')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.mutedSurface,
      appBar: AppBar(
        title: Text(context.tr('driver_home_title')),
        actions: [
          if (_vehicleCategory != 'motorcycle' && _vehicleCategory != 'cargo')
            // A driver previously had to remember to open this screen and
            // check manually — unlike fixed-price rides (actively pushed via
            // the dispatch engine), a new negotiable ride gave no signal at
            // all that it existed. This live badge (same open-rides stream
            // NegotiationScreen itself uses) is the closest equivalent to
            // that active "searching" experience without building a full
            // push-notification pipeline for negotiable rides.
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: _repo.watchOpenNegotiableRides(),
              builder: (context, snap) {
                final count = (snap.data ?? [])
                    .where((r) => r['status'] == 'pending' && (r['driver_phone'] == null || (r['driver_phone'] as String).isEmpty))
                    .length;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      tooltip: context.tr('driver_home_negotiation_tooltip'),
                      icon: const Text('🤝', style: TextStyle(fontSize: 20)),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => NegotiationScreen(session: widget.session)),
                      ),
                    ),
                    if (count > 0)
                      Positioned(
                        right: 4,
                        top: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(999)),
                          child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
                        ),
                      ),
                  ],
                );
              },
            ),
          if (_vehicleCategory != 'motorcycle' && _vehicleCategory != 'cargo')
            // Same live-badge pattern as the negotiation icon above, for
            // the parallel no-countdown airport-ride request list (see
            // db/security-65-airport-ride-requests.sql) — a driver
            // otherwise only ever sees an airport ride via the single
            // timed dispatch_offers card, with no way to browse or
            // inspect full trip details before deciding.
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: _repo.watchOpenAirportRides(),
              builder: (context, snap) {
                final count = (snap.data ?? [])
                    .where((r) => r['status'] == 'pending' && (r['driver_phone'] == null || (r['driver_phone'] as String).isEmpty))
                    .length;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      tooltip: context.tr('driver_home_airport_requests_tooltip'),
                      icon: const Text('✈️', style: TextStyle(fontSize: 20)),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => AirportRideRequestsScreen(session: widget.session)),
                      ),
                    ),
                    if (count > 0)
                      Positioned(
                        right: 4,
                        top: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(999)),
                          child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
                        ),
                      ),
                  ],
                );
              },
            ),
          const LogoutButton(),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatusCard(
                driverName: widget.session.name,
                driverPhone: widget.session.phone,
                online: _online,
                busy: _busy || _jobs.job != null,
                onChanged: _toggleOnline,
              ),
              const SizedBox(height: 20),
              Expanded(
                // Fresh offers take priority even mid-job — each is a 30s
                // decision, shown over (not instead of losing) the active
                // job, which is still sitting in _jobs.job underneath.
                child: _offers.isNotEmpty
                    ? _OffersListPanel(
                        offers: _offers,
                        actingOnOfferId: _actingOnOfferId,
                        onAccept: _accept,
                        onReject: _reject,
                      )
                    : _jobs.job != null
                        ? _buildActiveJob()
                        : _jobs.queue.isNotEmpty
                            ? _buildQueueOnly()
                            : _IdleView(online: _online),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double? _num(dynamic v) => v == null ? null : (v as num).toDouble();

  /// Coordinates for the leg the driver is currently on — pickup while
  /// heading to collect the rider/order, dropoff once they've got them.
  (double, double)? _currentLegOrigin(Map<String, dynamic> job, bool isOrder) {
    final lat = _num(isOrder ? job['store_lat'] : job['from_lat']);
    final lng = _num(isOrder ? job['store_lng'] : job['from_lng']);
    return (lat != null && lng != null) ? (lat, lng) : null;
  }

  (double, double)? _currentLegDestination(Map<String, dynamic> job, bool isOrder) {
    if (isOrder) {
      final lat = _num(job['customer_lat']) ?? _num(job['store_lat']);
      final lng = _num(job['customer_lng']) ?? _num(job['store_lng']);
      return (lat != null && lng != null) ? (lat, lng) : null;
    }
    // Rides: heading to pick up the rider first, then to their destination.
    final headingToPickup = _jobs.rideStep == 'accepted';
    final lat = _num(headingToPickup ? job['from_lat'] : job['to_lat']);
    final lng = _num(headingToPickup ? job['from_lng'] : job['to_lng']);
    return (lat != null && lng != null) ? (lat, lng) : null;
  }

  /// Shown instead of the idle radar view once the driver has finished
  /// their current job but still has accepted ones waiting — so they pick
  /// the next one instantly instead of watching an empty screen.
  Widget _buildQueueOnly() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(context.tr('driver_home_queue_ready_banner'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
          ),
          const SizedBox(height: 10),
          _QueueList(jobs: _jobs.queue, onTap: _jobs.switchToQueued),
        ],
      ),
    );
  }

  Widget _buildActiveJob() {
    final job = _jobs.job!;
    final isOrder = _jobs.jobType == 'order';
    final from = isOrder ? (job['store_name'] as String? ?? '') : (job['from_area'] as String? ?? '');
    final to = isOrder ? (job['address'] as String? ?? job['area'] as String? ?? '') : (job['to_area'] as String? ?? '');
    final fare = job['fare'] ?? job['total'] ?? job['delivery_fee'] ?? 0;
    final origin = _currentLegOrigin(job, isOrder);
    final destination = _currentLegDestination(job, isOrder);
    final customerName = job['customer_name'] as String?;
    final customerPhone = job['customer_phone'] as String?;

    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4))],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const SizedBox(width: 72),
                    Expanded(
                      child: Text(
                        isOrder ? context.tr('driver_home_active_order_title') : context.tr('driver_home_active_ride_title'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                    ),
                    SosButton(role: 'driver', rideId: isOrder ? null : job['id'] as String?),
                  ],
                ),
                if (customerPhone != null && customerPhone.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _CustomerContactRow(name: customerName, phone: customerPhone),
                ],
                const SizedBox(height: 14),
                _RouteRow(from: from, to: to, stops: isOrder ? const [] : _stopNames(job)),
                if (!isOrder && destination != null && (job['status'] == 'accepted' || job['status'] == 'in_progress'))
                  _DriverDistanceReadout(
                    driverPhone: widget.session.phone,
                    targetLat: destination.$1,
                    targetLng: destination.$2,
                    headingToPickup: job['status'] == 'accepted',
                  ),
                if (job['ride_type'] == 'airport') ...[
                  const SizedBox(height: 8),
                  _AirportFlightChip(data: job),
                ],
                if (!isOrder && job['status'] == 'accepted') ...[
                  const SizedBox(height: 8),
                  _ArrivalDeadlineChip(acceptedAt: job['accepted_at'] as String?, etaMinutes: job['eta_minutes'] as num?),
                  if (PricingSettings.driverLateFeeEnabled) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${context.tr('driver_home_late_grace_warning_prefix')} ${PricingSettings.driverLateGraceMinutes} ${context.tr('driver_home_late_grace_warning_mid')} ${PricingSettings.driverLateFee.toStringAsFixed(0)} ${context.tr('driver_home_late_grace_warning_suffix')}',
                      style: const TextStyle(fontSize: 10.5, color: AppColors.textFaint, fontWeight: FontWeight.w700, height: 1.4),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
                if (!isOrder && job['status'] == 'arrived' && job['arrived_at'] != null) ...[
                  const SizedBox(height: 8),
                  WaitingTimerCard(
                    arrivedAt: DateTime.parse(job['arrived_at'] as String).toLocal(),
                    isCustomerView: false,
                  ),
                  _NoShowButton(
                    arrivedAt: DateTime.parse(job['arrived_at'] as String).toLocal(),
                    onReport: () => _handleNoShow(job['id'] as String),
                  ),
                ],
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(999)),
                  child: Text('$fare ${context.tr('driver_home_currency')}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.success)),
                ),
              ],
            ),
          ),
          if (job['ride_type'] == 'airport') ...[
            const SizedBox(height: 16),
            _AirportDetailsCard(data: job, fare: fare),
          ],
          if (destination != null) ...[
            const SizedBox(height: 16),
            _RouteMapCard(origin: origin, destination: destination),
          ],
          if (_jobs.queue.isNotEmpty) ...[
            const SizedBox(height: 16),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text('${context.tr('driver_home_queue_next_banner_prefix')} ${_jobs.queue.length} ${context.tr('driver_home_queue_next_banner_suffix')}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.textFaint)),
            ),
            const SizedBox(height: 8),
            _QueueList(jobs: _jobs.queue, onTap: _jobs.switchToQueued),
          ],
          const SizedBox(height: 20),
          if (isOrder)
            ElevatedButton(
              onPressed: _busy ? null : _advanceOrder,
              style: ElevatedButton.styleFrom(
                backgroundColor: _jobs.pickedUp ? AppColors.success : AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(_jobs.pickedUp ? context.tr('driver_home_order_delivered') : context.tr('driver_home_order_picked_up_action')),
            )
          else
            _RideStepButtons(
              step: _jobs.rideStep,
              busy: _busy,
              onTap: _advanceRide,
              driverPhone: widget.session.phone,
              destinationLat: destination?.$1,
              destinationLng: destination?.$2,
            ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final String driverName;
  final String driverPhone;
  final bool online;
  final bool busy;
  final ValueChanged<bool> onChanged;
  const _StatusCard({
    required this.driverName,
    required this.driverPhone,
    required this.online,
    required this.busy,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: online ? const Color(0xFFF0FDF4) : context.surfaceColor,
        border: Border.all(color: online ? const Color(0xFF16A34A).withValues(alpha: 0.3) : const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(driverName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                const SizedBox(height: 2),
                Text(driverPhone, style: const TextStyle(fontSize: 11, color: AppColors.textFaint), textDirection: TextDirection.ltr),
              ],
            ),
          ),
          Column(
            children: [
              Switch(
                value: online,
                onChanged: busy ? null : onChanged,
                activeTrackColor: AppColors.success,
              ),
              Text(
                online ? context.tr('driver_home_status_online') : context.tr('driver_home_status_offline'),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: online ? AppColors.success : AppColors.textFaint),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IdleView extends StatefulWidget {
  final bool online;
  const _IdleView({required this.online});

  @override
  State<_IdleView> createState() => _IdleViewState();
}

class _IdleViewState extends State<_IdleView> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.online) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🔴', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 12),
            Text(context.tr('driver_home_idle_offline_title'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            const SizedBox(height: 4),
            Text(context.tr('driver_home_idle_offline_subtitle'), style: const TextStyle(color: AppColors.textFaint, fontSize: 12)),
          ],
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 140,
            height: 140,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    for (final delay in [0.0, 0.33, 0.66])
                      _radarRing((_controller.value + delay) % 1.0),
                    Container(
                      width: 56,
                      height: 56,
                      decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: const Text('🚗', style: TextStyle(fontSize: 24)),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Text(context.tr('driver_home_idle_waiting'), style: const TextStyle(color: AppColors.textFaint, fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _radarRing(double t) {
    final size = 56.0 + t * 84.0;
    final opacity = (1 - t).clamp(0.0, 1.0);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.primary.withValues(alpha: opacity * 0.6), width: 2),
      ),
    );
  }
}

/// Compact list of a driver's already-accepted-but-not-started jobs —
/// tapping one makes it the active job (see ActiveJobStore.switchToQueued).
class _QueueList extends StatelessWidget {
  final List<QueuedJob> jobs;
  final ValueChanged<int> onTap;
  const _QueueList({required this.jobs, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (int i = 0; i < jobs.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _QueueTile(job: jobs[i], onTap: () => onTap(i)),
        ],
      ],
    );
  }
}

class _QueueTile extends StatelessWidget {
  final QueuedJob job;
  final VoidCallback onTap;
  const _QueueTile({required this.job, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isOrder = job.type == 'order';
    final data = job.data;
    final from = isOrder ? (data['store_name'] as String? ?? '') : (data['from_area'] as String? ?? '');
    final to = isOrder ? (data['address'] as String? ?? data['area'] as String? ?? '') : (data['to_area'] as String? ?? '');
    final fare = data['fare'] ?? data['total'] ?? data['delivery_fee'] ?? 0;

    return Material(
      color: context.surfaceColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            children: [
              Text(isOrder ? '📦' : '🚖', style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$from ← $to', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text('$fare ${context.tr('driver_home_currency')}', style: const TextStyle(fontSize: 11, color: AppColors.success, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              const Icon(Icons.play_circle_fill, color: AppColors.primary, size: 26),
            ],
          ),
        ),
      ),
    );
  }
}

/// Every currently-pending offer shown as its own card (route thumbnail +
/// price + accept/reject) instead of one modal blocking the whole screen —
/// lets the driver compare and act on more than one at a time.
class _OffersListPanel extends StatelessWidget {
  final List<PendingOffer> offers;
  final String? actingOnOfferId;
  final void Function(PendingOffer) onAccept;
  final void Function(PendingOffer) onReject;
  const _OffersListPanel({
    required this.offers,
    required this.actingOnOfferId,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text('🔔', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 8),
            Text(
              offers.length == 1 ? context.tr('driver_home_offer_singular') : '${context.tr('driver_home_offer_plural_prefix')} ${offers.length} ${context.tr('driver_home_offer_plural_suffix')}',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            itemCount: offers.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final offer = offers[i];
              return _OfferCard(
                offer: offer,
                busy: actingOnOfferId == offer.offerId,
                onAccept: () => onAccept(offer),
                onReject: () => onReject(offer),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _OfferCard extends StatelessWidget {
  final PendingOffer offer;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  const _OfferCard({required this.offer, required this.busy, required this.onAccept, required this.onReject});

  double? _num(dynamic v) => v == null ? null : (v as num).toDouble();

  @override
  Widget build(BuildContext context) {
    final data = offer.data;
    final isOrder = offer.targetType == 'order';
    final from = isOrder ? (data['store_name'] as String? ?? '') : (data['from_area'] as String? ?? '');
    final to = isOrder ? (data['address'] as String? ?? data['area'] as String? ?? '') : (data['to_area'] as String? ?? '');
    final fare = data['fare'] ?? data['total'] ?? data['delivery_fee'] ?? '';
    final fromLat = _num(isOrder ? data['store_lat'] : data['from_lat']);
    final fromLng = _num(isOrder ? data['store_lng'] : data['from_lng']);
    final toLat = _num(isOrder ? (data['customer_lat'] ?? data['store_lat']) : data['to_lat']);
    final toLng = _num(isOrder ? (data['customer_lng'] ?? data['store_lng']) : data['to_lng']);
    final hasMap = fromLat != null && fromLng != null && toLat != null && toLng != null;
    final remaining = offer.expiresAt?.difference(DateTime.now()).inSeconds;

    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 16, offset: Offset(0, 6))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasMap)
            SizedBox(
              height: 110,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    staticRouteMapUrl(fromLat: fromLat, fromLng: fromLng, toLat: toLat, toLng: toLng, width: 640, height: 220),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(color: AppColors.primaryLight),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(999)),
                      child: Text(
                        isOrder ? context.tr('driver_home_offer_type_order') : context.tr('driver_home_offer_type_ride'),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11),
                      ),
                    ),
                  ),
                  if (remaining != null)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withValues(alpha: 0.55),
                          border: Border.all(color: Colors.white70, width: 2),
                        ),
                        alignment: Alignment.center,
                        child: Text('${remaining < 0 ? 0 : remaining}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _RouteRow(from: from, to: to, stops: _stopNames(data)),
                if (data['ride_type'] == 'airport') _AirportFlightChip(data: data),
                if (data['customer_phone'] != null && (data['customer_phone'] as String).isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TrustBadge(
                      future: RatingsRepository().customerReliability(data['customer_phone'] as String),
                      trustedLabel: context.tr('driver_home_trusted_customer'),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (data['distance_km'] != null) _metaChip('${(data['distance_km'] as num).toStringAsFixed(1)} ${context.tr('driver_home_unit_km')}'),
                    if (data['eta_minutes'] != null) _metaChip('${data['eta_minutes']} ${context.tr('driver_home_unit_min')}'),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(10)),
                      child: Text('$fare ${context.tr('driver_home_currency')}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.success)),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: busy ? null : onReject,
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                        child: Text(context.tr('driver_home_reject')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: busy ? null : onAccept,
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, padding: const EdgeInsets.symmetric(vertical: 12)),
                        child: busy
                            ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Text(context.tr('driver_home_accept')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaChip(String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(10)),
      child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: AppColors.primary)),
    );
  }
}

/// Appears once PricingSettings.noShowGraceMinutes have passed since
/// arrived_at — before that it renders nothing (WaitingTimerCard already
/// covers the countdown/fee-estimate UI for the earlier period).
class _NoShowButton extends StatefulWidget {
  final DateTime arrivedAt;
  final Future<void> Function() onReport;
  const _NoShowButton({required this.arrivedAt, required this.onReport});

  @override
  State<_NoShowButton> createState() => _NoShowButtonState();
}

class _NoShowButtonState extends State<_NoShowButton> {
  Timer? _timer;
  bool _ready = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _check();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _check());
  }

  void _check() {
    final elapsedMinutes = DateTime.now().difference(widget.arrivedAt).inMinutes;
    final ready = elapsedMinutes >= PricingSettings.noShowGraceMinutes;
    if (ready != _ready && mounted) setState(() => _ready = ready);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _confirm() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(context.tr('driver_home_noshow_dialog_title')),
        content: Text(context.tr('driver_home_noshow_dialog_body')),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(context.tr('driver_home_noshow_dialog_cancel'))),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.tr('driver_home_noshow_dialog_confirm'), style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    await widget.onReport();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!FeatureFlags.noShowEnabled || !_ready) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: OutlinedButton.icon(
        onPressed: _busy ? null : _confirm,
        icon: const Icon(Icons.person_off_outlined, color: AppColors.error),
        label: Text(context.tr('driver_home_noshow_button_label'), style: const TextStyle(color: AppColors.error)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.error),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}

/// Static-map route preview (pickup/dropoff pins, no live tracking or
/// polyline — see the file-level doc comment) + a button that hands off to
/// the Google Maps app for actual turn-by-turn navigation.
/// Call + WhatsApp buttons for reaching the customer — the WhatsApp option
/// covers cases where a call doesn't get the driver to the right spot
/// (customer describes a landmark, sends a location pin, etc).
class _CustomerContactRow extends StatelessWidget {
  final String? name;
  final String phone;
  const _CustomerContactRow({required this.name, required this.phone});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: context.mutedSurface, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Expanded(
            child: Text(
              (name != null && name!.isNotEmpty) ? name! : context.tr('driver_home_customer_fallback_name'),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: () => callPhone(phone),
            icon: const Icon(Icons.call, color: AppColors.success),
            tooltip: context.tr('driver_home_call_customer_tooltip'),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            onPressed: () => openWhatsApp(phone),
            icon: const Icon(Icons.chat, color: Color(0xFF25D366)),
            tooltip: context.tr('driver_home_whatsapp_customer_tooltip'),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _RouteMapCard extends StatelessWidget {
  final (double, double)? origin;
  final (double, double) destination;
  const _RouteMapCard({required this.origin, required this.destination});

  @override
  Widget build(BuildContext context) {
    final o = origin ?? destination;
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Row(
              children: [
                const Text('🗺️', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Text(context.tr('driver_home_route_map_title'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
              ],
            ),
          ),
          AspectRatio(
            aspectRatio: 640 / 280,
            child: Image.network(
              staticRouteMapUrl(fromLat: o.$1, fromLng: o.$2, toLat: destination.$1, toLng: destination.$2),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                color: const Color(0xFFF3F4F6),
                alignment: Alignment.center,
                child: Text(context.tr('driver_home_route_map_error'), style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
              ),
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => openMapsNavigation(destination.$1, destination.$2),
                icon: const Icon(Icons.navigation_outlined),
                label: Text(context.tr('driver_home_open_maps_button')),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// rides.stops (db/security-29) — intermediate waypoints as
/// [{"name":...,"lat":...,"lng":...}, ...], excluding origin/destination.
/// Top-level so both _DriverHomeScreenState and the offer-card widget can
/// call it without duplicating the same parsing logic.
List<String> _stopNames(Map<String, dynamic> job) {
  final stops = job['stops'];
  if (stops is! List) return const [];
  return stops
      .whereType<Map>()
      .map((s) => (s['name'] as String?)?.trim())
      .whereType<String>()
      .where((s) => s.isNotEmpty)
      .toList();
}

class _RouteRow extends StatelessWidget {
  final String from;
  final String to;
  final List<String> stops;
  const _RouteRow({required this.from, required this.to, this.stops = const []});

  Widget _connector() => Padding(
        padding: const EdgeInsets.only(right: 4.5),
        child: Container(width: 1.5, height: 14, color: const Color(0xFFE5E7EB)),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Container(width: 10, height: 10, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(child: Text(from, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
          ],
        ),
        for (final stop in stops) ...[
          _connector(),
          Row(
            children: [
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle)),
              const SizedBox(width: 9),
              Expanded(child: Text('🛑 $stop', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textFaint))),
            ],
          ),
        ],
        _connector(),
        Row(
          children: [
            Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(child: Text(to, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
          ],
        ),
      ],
    );
  }
}

/// Compact flight-time badge for airport jobs — offer cards and the
/// active-job card otherwise look identical to a normal ride, even though
/// airport bookings have a real deadline (see security-32's flight_time
/// column) the driver needs to see at a glance.
/// The deadline the driver needs to reach the customer's pickup point by
/// (accepted_at + eta_minutes) — matches mark_ride_arrived's own
/// server-side late calculation (db/security-29): more than 5 minutes
/// past this deducts 20 ج.م from the driver's wallet automatically once
/// they mark themselves arrived, so this is a real deadline, not just an
/// estimate.
class _ArrivalDeadlineChip extends StatelessWidget {
  final String? acceptedAt;
  final num? etaMinutes;
  const _ArrivalDeadlineChip({required this.acceptedAt, required this.etaMinutes});

  @override
  Widget build(BuildContext context) {
    final accepted = acceptedAt == null ? null : DateTime.tryParse(acceptedAt!)?.toLocal();
    if (accepted == null || etaMinutes == null) return const SizedBox.shrink();
    final deadline = accepted.add(Duration(minutes: etaMinutes!.round()));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(999)),
      child: Text(
        '${context.tr('driver_home_arrival_deadline_prefix')} ${arTime(deadline)} ${context.tr('driver_home_arrival_deadline_suffix')}',
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF92400E)),
      ),
    );
  }
}

/// Same live distance/ETA readout ride_tracking_screen.dart shows the
/// customer (fed by the driver's own periodic pingLocation() writes to
/// driver_locations) — mirrored here so the driver sees the same numbers
/// about themselves, not just the customer. Kept separate from that
/// customer-facing widget instead of sharing one, since the two screens
/// differ enough (layout, "you"/"them" wording) that factoring it out
/// wasn't worth the indirection for ~15 lines of logic.
class _DriverDistanceReadout extends StatelessWidget {
  final String driverPhone;
  final double targetLat;
  final double targetLng;
  final bool headingToPickup;
  const _DriverDistanceReadout({
    required this.driverPhone,
    required this.targetLat,
    required this.targetLng,
    required this.headingToPickup,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: RideRepository().watchDriverLocation(driverPhone),
      builder: (context, snap) {
        final loc = (snap.data != null && snap.data!.isNotEmpty) ? snap.data!.first : null;
        final lat = (loc?['lat'] as num?)?.toDouble();
        final lng = (loc?['lng'] as num?)?.toDouble();
        if (lat == null || lng == null) return const SizedBox.shrink();

        final distanceKm = haversineKm(lat, lng, targetLat, targetLng);
        final distanceM = distanceKm * 1000;
        final etaMin = (distanceKm / 25 * 60).ceil().clamp(1, 999); // ~25 km/h city average
        final distanceLabel = distanceM < 1000 ? '${distanceM.round()} ${context.tr('driver_home_unit_meter')}' : '${distanceKm.toStringAsFixed(1)} ${context.tr('driver_home_unit_km')}';
        final text = headingToPickup
            ? '${context.tr('driver_home_distance_to_customer_prefix')} $distanceLabel ${context.tr('driver_home_distance_eta_suffix')}$etaMin ${context.tr('driver_home_eta_minutes_suffix')}'
            : '${context.tr('driver_home_distance_to_destination_prefix')} $distanceLabel ${context.tr('driver_home_distance_eta_suffix')}$etaMin ${context.tr('driver_home_eta_minutes_suffix')}';

        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(text, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.primary)),
        );
      },
    );
  }
}

class _AirportFlightChip extends StatelessWidget {
  final Map<String, dynamic> data;
  const _AirportFlightChip({required this.data});

  @override
  Widget build(BuildContext context) {
    final raw = data['flight_time'];
    final flightTime = raw == null ? null : DateTime.tryParse(raw.toString())?.toLocal();
    if (flightTime == null) return const SizedBox.shrink();
    final direction = data['airport_direction'] as String? ?? 'departure';
    final label = direction == 'departure' ? context.tr('driver_home_flight_departure_short') : context.tr('driver_home_flight_arrival_short');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(999)),
      child: Text('✈️ $label ${arDateTime(flightTime)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF1D4ED8))),
    );
  }
}

/// Full airport-trip details for the driver's active-job screen — shown
/// right after accepting an airport ride, per the request that the driver
/// see the same direction/details/total the customer sees on their own
/// confirmation screen. `notes` already carries every entered detail
/// (vehicle, quality, companions, bags, flight info, pickup address) as one
/// formatted string (see airport_screen.dart's _submit()) — no separate
/// per-line cost breakdown is persisted server-side, only the final fare
/// total, which is what's shown here.
class _AirportDetailsCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final dynamic fare;
  const _AirportDetailsCard({required this.data, required this.fare});

  @override
  Widget build(BuildContext context) {
    final direction = data['airport_direction'] as String? ?? 'departure';
    final directionLabel = direction == 'departure' ? context.tr('driver_home_airport_direction_departure') : context.tr('driver_home_airport_direction_arrival');
    final rawFlightTime = data['flight_time'];
    final flightTime = rawFlightTime == null ? null : DateTime.tryParse(rawFlightTime.toString())?.toLocal();
    final notes = (data['notes'] as String?) ?? '';
    final lines = notes.split(' — ').where((l) => l.trim().isNotEmpty).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: context.surfaceColor, borderRadius: BorderRadius.circular(16), boxShadow: const [
        BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4)),
      ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(directionLabel, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
          if (flightTime != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(8)),
              child: Text(
                '🕐 ${direction == "departure" ? context.tr('driver_home_flight_departure_time_label') : context.tr('driver_home_flight_arrival_time_label')}: ${arDateTime(flightTime)}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF1D4ED8)),
              ),
            ),
          ],
          const SizedBox(height: 10),
          ...lines.map((l) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(l, style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
              )),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(context.tr('driver_home_airport_total_label'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
              Text('$fare ${context.tr('driver_home_currency')}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.success)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReceiptDialog extends StatelessWidget {
  final RideSettlement settlement;
  final String rideId;
  final String driverPhone;
  const _ReceiptDialog({required this.settlement, required this.rideId, required this.driverPhone});

  @override
  Widget build(BuildContext context) {
    final s = settlement;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: RideRepository().fetchRidePenalties(rideId),
          builder: (context, snap) {
            // A late-arrival fee (db/security-63/64) is deducted from the
            // driver's wallet separately, at the moment they mark
            // "arrived" — well before settle_ride_commission() runs here,
            // so driverEarn above already doesn't include it. Shown as an
            // informational line so the driver understands why their
            // wallet moved by more than just this ride's commission cut,
            // not folded into the totals above (which are this ride's
            // fare/commission/earnings specifically).
            // Filters by note text (not just phone) — if the same phone
            // was used to test both the customer and driver accounts,
            // matching on phone alone would wrongly pull the customer's
            // late-boarding fee into the driver's own receipt.
            final lateFee = (snap.data ?? [])
                .where((p) => p['phone'] == driverPhone && (p['note'] as String? ?? '').contains('تأخير وصول'))
                .fold<double>(0, (sum, p) => sum + ((p['amount'] as num).abs()));

            final currency = context.tr('driver_home_currency');
            String egp(double v) => '${v.toStringAsFixed(0)} $currency';
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('✅', style: TextStyle(fontSize: 40)),
                const SizedBox(height: 8),
                Text(context.tr('driver_home_receipt_title'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                const SizedBox(height: 20),
                _row(context.tr('driver_home_receipt_fare_label'), egp(s.fare)),
                const Divider(height: 24),
                _row('${context.tr('driver_home_receipt_commission_prefix')}${s.rate.toStringAsFixed(0)}${context.tr('driver_home_receipt_commission_suffix')}', '- ${egp(s.commission)}', color: AppColors.error),
                const Divider(height: 24),
                _row(context.tr('driver_home_receipt_total_earned'), egp(s.driverEarn), bold: true, color: AppColors.success),
                if (lateFee > 0) ...[
                  const Divider(height: 24),
                  _row(context.tr('driver_home_receipt_late_fee_label'), '- ${egp(lateFee)}', color: AppColors.error),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(context.tr('driver_home_receipt_ok_button')),
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

class _RideStepButtons extends StatelessWidget {
  final String step; // accepted | arrived | in_progress
  final bool busy;
  final VoidCallback onTap;
  final String? driverPhone;
  final double? destinationLat;
  final double? destinationLng;
  const _RideStepButtons({
    required this.step,
    required this.busy,
    required this.onTap,
    this.driverPhone,
    this.destinationLat,
    this.destinationLng,
  });

  @override
  Widget build(BuildContext context) {
    if (step != 'accepted' && step != 'arrived' && driverPhone != null && destinationLat != null && destinationLng != null) {
      return FinishRideButton(
        busy: busy,
        onTap: onTap,
        driverPhone: driverPhone!,
        destinationLat: destinationLat!,
        destinationLng: destinationLng!,
      );
    }
    final (label, color) = switch (step) {
      'accepted' => (context.tr('driver_home_ride_step_arrived'), AppColors.primaryLight),
      'arrived' => (context.tr('driver_home_ride_step_start'), AppColors.primary),
      _ => (context.tr('driver_home_ride_step_finish'), AppColors.success),
    };
    final isLight = step == 'accepted';
    return ElevatedButton(
      onPressed: busy ? null : onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: isLight ? AppColors.primary : Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
    );
  }
}
