import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/contact_launcher.dart';
import '../../core/maps_launcher.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../shared/widgets/logout_button.dart';
import 'driver_repository.dart';

/// Visual language ported from driver-dashboard.astro: teal online toggle,
/// pulsing "radar" while idle, a 30s-countdown offer sheet, sequential
/// trip-progress buttons (arrived → picked up → completed) instead of one
/// generic "finish" button, and a route preview + "open in Google Maps"
/// button for the current leg. Earnings/ratings tabs and the receipt/
/// rating modals are bigger Phase-2 scope — same call made for the
/// customer tracking screen's live map earlier.
const int _offerCountdownSeconds = 30;

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

  bool _online = false;
  bool _busy = false;
  PendingOffer? _offer;
  int _countdown = _offerCountdownSeconds;
  Map<String, dynamic>? _activeJob;
  String? _activeJobType; // 'ride' | 'order'
  String _rideStep = 'accepted'; // accepted -> arrived -> in_progress -> completed
  bool _pickedUp = false; // orders only

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
    super.dispose();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!_online || _activeJob != null || _offer != null) return;
      final offer = await _repo.getPendingOffer(widget.session.phone);
      if (offer != null && mounted) _receiveOffer(offer);
    });
  }

  void _receiveOffer(PendingOffer offer) {
    HapticFeedback.heavyImpact();
    _countdownTimer?.cancel();
    _countdown = _offerCountdownSeconds;
    setState(() => _offer = offer);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _countdown--);
      if (_countdown <= 0) {
        t.cancel();
        _reject(auto: true);
      }
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
      if (ok) _startPolling();
    } else {
      await _repo.goOffline(widget.session.phone);
      _pollTimer?.cancel();
      setState(() {
        _online = false;
        _busy = false;
      });
    }
  }

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.error, duration: const Duration(seconds: 6)),
    );
  }

  Future<void> _accept() async {
    if (_offer == null) return;
    _countdownTimer?.cancel();
    setState(() => _busy = true);
    try {
      final ok = await _repo.acceptOffer(_offer!.offerId, widget.session.phone, widget.session.name);
      if (!mounted) return;
      if (!ok && mounted) _showError('السائق لم يستطع قبول الطلب (اتقبل من غيرك أو انتهت صلاحيته)');
      setState(() {
        _busy = false;
        if (ok) {
          _activeJob = _offer!.data;
          _activeJobType = _offer!.targetType;
          _rideStep = 'accepted';
          _pickedUp = false;
        }
        _offer = null;
      });
    } catch (e) {
      _showError(e);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _offer = null;
      });
    }
  }

  Future<void> _reject({bool auto = false}) async {
    if (_offer == null) return;
    setState(() => _busy = true);
    try {
      await _repo.rejectOffer(_offer!.offerId, widget.session.phone);
    } catch (e) {
      _showError(e);
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _offer = null;
    });
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
          await _repo.completeRide(rideId, widget.session.phone);
          if (!mounted) return;
          setState(() {
            _activeJob = null;
            _activeJobType = null;
            _busy = false;
          });
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
    setState(() => _busy = true);
    final orderId = job['id'].toString();
    try {
      if (!_pickedUp) {
        await _repo.markOrderPickedUp(orderId);
        if (!mounted) return;
        setState(() {
          _pickedUp = true;
          _busy = false;
        });
        return;
      }
      await _repo.confirmOrderDelivery(orderId, widget.session.phone);
      if (!mounted) return;
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
                child: _activeJob != null
                    ? _buildActiveJob()
                    : _offer != null
                        ? _OfferSheet(
                            offer: _offer!,
                            countdown: _countdown,
                            busy: _busy,
                            onAccept: _accept,
                            onReject: () => _reject(),
                          )
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

class _OfferSheet extends StatelessWidget {
  final PendingOffer offer;
  final int countdown;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  const _OfferSheet({
    required this.offer,
    required this.countdown,
    required this.busy,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final data = offer.data;
    final isOrder = offer.targetType == 'order';
    final from = isOrder ? (data['store_name'] as String? ?? '') : (data['from_area'] as String? ?? '');
    final to = isOrder ? (data['address'] as String? ?? data['area'] as String? ?? '') : (data['to_area'] as String? ?? '');
    final fare = data['fare'] ?? data['total'] ?? data['delivery_fee'] ?? '';

    return Center(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 20, offset: Offset(0, 8))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [AppColors.primaryDark, AppColors.primary]),
              ),
              child: Row(
                children: [
                  const Text('🔔', style: TextStyle(fontSize: 26)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isOrder ? 'طلب دليفري جديد!' : 'راكب جديد!',
                      style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900),
                    ),
                  ),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white70, width: 3)),
                    alignment: Alignment.center,
                    child: Text('$countdown', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _RouteRow(from: from, to: to),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      if (data['distance_km'] != null) _metaChip('${data['distance_km']} كم', 'المسافة'),
                      if (data['eta_minutes'] != null) _metaChip('${data['eta_minutes']} د', 'الوقت'),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(10)),
                        child: Column(
                          children: [
                            Text('$fare ج.م', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.success)),
                            const Text('الأجرة', style: TextStyle(fontSize: 9, color: AppColors.textFaint)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: busy ? null : onReject,
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                          child: const Text('رفض'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: busy ? null : onAccept,
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, padding: const EdgeInsets.symmetric(vertical: 14)),
                          child: const Text('قبول'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaChip(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
        Text(label, style: const TextStyle(fontSize: 9, color: AppColors.textFaint)),
      ],
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
