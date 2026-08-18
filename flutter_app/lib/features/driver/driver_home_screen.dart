import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/contact_launcher.dart';
import '../../core/maps_launcher.dart';
import '../../core/push.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../shared/widgets/logout_button.dart';
import 'driver_repository.dart';

/// Visual language ported from driver-dashboard.astro: teal online toggle,
/// pulsing "radar" while idle, a list of 30s-countdown offer cards,
/// sequential trip-progress buttons (arrived → picked up → completed)
/// instead of one generic "finish" button, and a route preview + "open in
/// Google Maps" button for the current leg. Earnings/ratings tabs and the
/// rating modals are bigger Phase-2 scope — same call made for the
/// customer tracking screen's live map earlier.

/// An accepted-but-not-yet-started job — the driver can accept a new offer
/// while another job is already active; it lands here instead of being
/// dropped, so finishing the current job (or switching manually) shows a
/// ready-to-go queue instead of an empty screen waiting for the next offer.
class QueuedJob {
  final String type; // 'ride' | 'order'
  final Map<String, dynamic> data;
  QueuedJob(this.type, this.data);
}

class DriverHomeScreen extends StatefulWidget {
  final UserSession session;
  const DriverHomeScreen({super.key, required this.session});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  final _repo = DriverRepository();
  Timer? _pollTimer;
  Timer? _countdownTimer;
  Timer? _locationTimer;
  StreamSubscription<Map<String, dynamic>>? _offersSub;

  bool _online = false;
  bool _busy = false;
  List<PendingOffer> _offers = [];
  String? _actingOnOfferId;
  Map<String, dynamic>? _activeJob;
  String? _activeJobType; // 'ride' | 'order'
  String _rideStep = 'accepted'; // accepted -> arrived -> in_progress -> completed
  bool _pickedUp = false; // orders only
  final List<QueuedJob> _queuedJobs = [];

  @override
  void initState() {
    super.initState();
    // Go online automatically as soon as the driver opens the app, instead
    // of always starting offline and requiring a manual tap first — the
    // driver can still switch back off with the same toggle at any time
    // (e.g. after finishing their last trip for the day).
    _toggleOnline(true);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    _locationTimer?.cancel();
    _offersSub?.cancel();
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
  // can still be offered (and accept) another, which lands in _queuedJobs
  // instead of replacing what they're currently doing. Shown as a list
  // (see _OffersListPanel) so more than one can sit there at once.
  Future<void> _refreshOffers() async {
    if (!_online) return;
    final offers = await _repo.getPendingOffers(widget.session.phone);
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
          const SnackBar(content: Text('محتاجين إذن الموقع عشان تظهر للطلبات القريبة')),
        );
      }
      setState(() {
        _online = ok;
        _busy = false;
      });
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
    }
  }

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.error, duration: const Duration(seconds: 6)),
    );
  }

  void _showReceipt(RideSettlement s) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => _ReceiptDialog(settlement: s),
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
              ? 'نوع سيارتك لا يطابق نوع السيارة المطلوب لرحلة المطار دي'
              : result == 'quality_tier_mismatch'
                  ? 'سيارتك المسجّلة لا تطابق مستوى الخدمة المطلوب لرحلة المطار دي (مكيّفة/نظيفة/موديل حديث)'
                  : result == 'driver_not_approved'
                      ? 'حسابك لسه قيد المراجعة من الإدارة — مينفعش تقبل رحلات لحد ما يتم اعتماد طلبك'
                      : 'السائق لم يستطع قبول الطلب (اتقبل من غيرك أو انتهت صلاحيته)',
        );
      }
      setState(() {
        _actingOnOfferId = null;
        _offers = _offers.where((o) => o.offerId != offer.offerId).toList();
        if (ok) {
          final job = QueuedJob(offer.targetType, offer.data);
          if (_activeJob == null) {
            _activateJob(job);
          } else {
            _queuedJobs.add(job);
          }
        }
      });
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

  void _activateJob(QueuedJob job) {
    _activeJob = job.data;
    _activeJobType = job.type;
    _rideStep = 'accepted';
    _pickedUp = false;
  }

  /// Switching mid-job puts the job being left back at the front of the
  /// queue instead of dropping it — nothing accepted is ever lost.
  void _switchToQueuedJob(int index) {
    setState(() {
      final next = _queuedJobs.removeAt(index);
      if (_activeJob != null) {
        _queuedJobs.insert(0, QueuedJob(_activeJobType!, _activeJob!));
      }
      _activateJob(next);
    });
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
    final job = _activeJob;
    if (job == null) return;
    final rideId = job['id'].toString();
    setState(() => _busy = true);
    try {
      switch (_rideStep) {
        case 'accepted':
          await _repo.markRideArrived(rideId);
          if (!mounted) return;
          setState(() {
            _rideStep = 'arrived';
            _busy = false;
          });
          return;
        case 'arrived':
          await _repo.markRideInProgress(rideId);
          if (!mounted) return;
          setState(() {
            _rideStep = 'in_progress';
            _busy = false;
          });
          return;
        default:
          final settlement = await _repo.completeRide(rideId, widget.session.phone);
          if (!mounted) return;
          setState(() {
            _activeJob = null;
            _activeJobType = null;
            _busy = false;
          });
          if (settlement != null) _showReceipt(settlement);
      }
    } catch (e) {
      _showError(e);
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  Future<void> _advanceOrder() async {
    final job = _activeJob;
    if (job == null) return;
    final orderId = job['id'].toString();

    if (!_pickedUp) {
      setState(() => _busy = true);
      try {
        await _repo.markOrderPickedUp(orderId);
        if (!mounted) return;
        setState(() {
          _pickedUp = true;
          _busy = false;
        });
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
        _showError('كود التسليم غير صحيح');
        return;
      }
      setState(() {
        _activeJob = null;
        _activeJobType = null;
        _busy = false;
      });
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
        title: const Text('كود التسليم'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 4,
          decoration: const InputDecoration(
            hintText: 'اطلب من العميل الكود المعروض في صفحة تتبّع الطلب',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF9),
      appBar: AppBar(
        title: const Text('وصّلها سائق'),
        actions: const [LogoutButton()],
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
                busy: _busy || _activeJob != null,
                onChanged: _toggleOnline,
              ),
              const SizedBox(height: 20),
              Expanded(
                // Fresh offers take priority even mid-job — each is a 30s
                // decision, shown over (not instead of losing) the active
                // job, which is still sitting in _activeJob underneath.
                child: _offers.isNotEmpty
                    ? _OffersListPanel(
                        offers: _offers,
                        actingOnOfferId: _actingOnOfferId,
                        onAccept: _accept,
                        onReject: _reject,
                      )
                    : _activeJob != null
                        ? _buildActiveJob()
                        : _queuedJobs.isNotEmpty
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
    final headingToPickup = _rideStep == 'accepted';
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
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text('🗂️ عندك طلبات جاهزة — اختار واحد وابدأ فورًا', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
          ),
          const SizedBox(height: 10),
          _QueueList(jobs: _queuedJobs, onTap: _switchToQueuedJob),
        ],
      ),
    );
  }

  Widget _buildActiveJob() {
    final job = _activeJob!;
    final isOrder = _activeJobType == 'order';
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
                Text(isOrder ? '📦 طلب قيد التنفيذ' : '🚖 مشوار قيد التنفيذ', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                if (customerPhone != null && customerPhone.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _CustomerContactRow(name: customerName, phone: customerPhone),
                ],
                const SizedBox(height: 14),
                _RouteRow(from: from, to: to),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(999)),
                  child: Text('$fare ج.م', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.success)),
                ),
              ],
            ),
          ),
          if (destination != null) ...[
            const SizedBox(height: 16),
            _RouteMapCard(origin: origin, destination: destination),
          ],
          if (_queuedJobs.isNotEmpty) ...[
            const SizedBox(height: 16),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text('🗂️ قدامك ${_queuedJobs.length} طلب جاهز — دوس عشان تبدأه دلوقتي', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.textFaint)),
            ),
            const SizedBox(height: 8),
            _QueueList(jobs: _queuedJobs, onTap: _switchToQueuedJob),
          ],
          const SizedBox(height: 20),
          if (isOrder)
            ElevatedButton(
              onPressed: _busy ? null : _advanceOrder,
              style: ElevatedButton.styleFrom(
                backgroundColor: _pickedUp ? AppColors.success : AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(_pickedUp ? '✓ تم التسليم' : '📦 التقطت الطلب من المتجر'),
            )
          else
            _RideStepButtons(step: _rideStep, busy: _busy, onTap: _advanceRide),
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
        color: online ? const Color(0xFFF0FDF4) : Colors.white,
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
                online ? 'متصل' : 'غير متصل',
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
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🔴', style: TextStyle(fontSize: 40)),
            SizedBox(height: 12),
            Text('أنت غير متصل', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            SizedBox(height: 4),
            Text('اضغط "متصل" عشان تبدأ تستقبل طلبات', style: TextStyle(color: AppColors.textFaint, fontSize: 12)),
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
          const Text('جاري الانتظار على طلبات...', style: TextStyle(color: AppColors.textFaint, fontSize: 13, fontWeight: FontWeight.w700)),
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
/// tapping one makes it the active job (see _switchToQueuedJob).
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
      color: Colors.white,
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
                    Text('$fare ج.م', style: const TextStyle(fontSize: 11, color: AppColors.success, fontWeight: FontWeight.w700)),
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
              offers.length == 1 ? 'عندك عرض جديد' : 'عندك ${offers.length} عروض جديدة',
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
        color: Colors.white,
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
                        isOrder ? '📦 دليفري' : '🚖 رحلة',
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
                _RouteRow(from: from, to: to),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (data['distance_km'] != null) _metaChip('${(data['distance_km'] as num).toStringAsFixed(1)} كم'),
                    if (data['eta_minutes'] != null) _metaChip('${data['eta_minutes']} د'),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(10)),
                      child: Text('$fare ج.م', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.success)),
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
                        child: const Text('رفض'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: busy ? null : onAccept,
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, padding: const EdgeInsets.symmetric(vertical: 12)),
                        child: busy
                            ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('قبول'),
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
      decoration: BoxDecoration(color: const Color(0xFFF7FAF9), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Expanded(
            child: Text(
              (name != null && name!.isNotEmpty) ? name! : 'العميل',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: () => callPhone(phone),
            icon: const Icon(Icons.call, color: AppColors.success),
            tooltip: 'اتصل بالعميل',
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            onPressed: () => openWhatsApp(phone),
            icon: const Icon(Icons.chat, color: Color(0xFF25D366)),
            tooltip: 'تواصل عبر واتساب',
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Row(
              children: const [
                Text('🗺️', style: TextStyle(fontSize: 14)),
                SizedBox(width: 6),
                Text('خريطة المسار', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
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
                child: const Text('تعذّر تحميل معاينة الخريطة', style: TextStyle(fontSize: 11, color: AppColors.textFaint)),
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
                label: const Text('افتح Google Maps للملاحة'),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  final String from;
  final String to;
  const _RouteRow({required this.from, required this.to});

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
        Padding(
          padding: const EdgeInsets.only(right: 4.5),
          child: Container(width: 1.5, height: 14, color: const Color(0xFFE5E7EB)),
        ),
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

class _ReceiptDialog extends StatelessWidget {
  final RideSettlement settlement;
  const _ReceiptDialog({required this.settlement});

  String _egp(double v) => '${v.toStringAsFixed(0)} ج.م';

  @override
  Widget build(BuildContext context) {
    final s = settlement;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('✅', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 8),
            const Text('فاتورة الرحلة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
            const SizedBox(height: 20),
            _row('المبلغ الأصلي (الأجرة)', _egp(s.fare)),
            const Divider(height: 24),
            _row('رسوم التطبيق (${s.rate.toStringAsFixed(0)}%)', '- ${_egp(s.commission)}', color: AppColors.error),
            const Divider(height: 24),
            _row('الإجمالي المستحق لك', _egp(s.driverEarn), bold: true, color: AppColors.success),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('تمام'),
              ),
            ),
          ],
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
  const _RideStepButtons({required this.step, required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (step) {
      'accepted' => ('📍 وصلت لنقطة الانطلاق', AppColors.primaryLight),
      'arrived' => ('✓ الراكب صعد، ابدأ الرحلة', AppColors.primary),
      _ => ('✓ وصلنا للوجهة — إنهاء الرحلة', AppColors.success),
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
