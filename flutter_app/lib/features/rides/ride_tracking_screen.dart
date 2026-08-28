import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../core/contact_launcher.dart';
import '../../core/date_format_ar.dart';
import '../../core/location_share.dart';
import '../../core/maps_launcher.dart';
import '../../core/notifications.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../shared/widgets/live_tracking_map.dart';
import '../driver/driver_repository.dart';
import '../ratings/rate_sheet.dart';
import '../ratings/ratings_repository.dart';
import '../ratings/trust_badge.dart';
import 'ride_repository.dart';

const Set<String> _liveTrackStatuses = {'accepted', 'arrived', 'in_progress'};

// Passing isDriverView flips the driver-facing card off (a driver looking at
// their own trip shouldn't see a "call the driver" card pointing at
// themselves) and shows the customer's contact info instead.

/// Same status → message mapping as track.astro's notifyStatusChange().
const Map<String, String> _statusNotif = {
  'accepted': '🚗 قبِل السائق طلبك وهو في طريقه إليك',
  'arrived': '📍 السائق وصل لنقطة الانطلاق',
  'in_progress': '🛣️ رحلتك بدأت الآن',
  'completed': '✅ وصلت رحلتك بسلام، شكرًا لاستخدامك وصّلها',
  'cancelled': '❌ تم إلغاء الرحلة',
};

/// Ordered ride statuses (rides.astro / driver-dashboard.astro write these
/// same values to rides.status), mirrored on the icon timeline below —
/// same visual language as the web's track.astro "HungerStation-style"
/// timeline (icon steps + progress bar + ETA card), just without the live
/// map/rating modules, which are a bigger Phase-2 scope.
const List<_Step> _steps = [
  _Step('pending', '📋', 'تم استلام الطلب'),
  _Step('accepted', '🚗', 'تم قبول الطلب'),
  _Step('arrived', '📍', 'السائق وصل'),
  _Step('in_progress', '🛣️', 'في الطريق'),
  _Step('completed', '✅', 'اكتملت الرحلة'),
];

class _Step {
  final String key;
  final String icon;
  final String label;
  const _Step(this.key, this.icon, this.label);
}

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
  }

  Future<void> _maybePromptRating(String driverPhone, String? customerPhone) async {
    if (!mounted) return;
    final already = await _ratingsRepo.hasRatedRide(widget.rideId);
    if (already || !mounted) return;
    final result = await RateSheet.show(
      context,
      title: 'قيّم رحلتك مع السائق',
      subtitle: 'رأيك بيساعدنا نحسّن الخدمة',
      positiveTags: positiveDriverTags,
      negativeTags: negativeDriverTags,
    );
    if (result == null || !mounted) return;
    await _ratingsRepo.rateDriver(
      rideId: widget.rideId,
      driverPhone: driverPhone,
      customerPhone: customerPhone ?? '',
      rating: result.rating,
      tags: result.tags,
      comment: result.comment,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ شكرًا على تقييمك')));
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
                content: Text('⚠️ اتأخرت $lateMinutes دقيقة عن العميل — اتخصم 20 ج.م تلقائيًا من محفظتك'),
                backgroundColor: AppColors.error,
                duration: const Duration(seconds: 6),
              ),
            );
          }
          break;
        case 'arrived':
          await _driverRepo.markRideInProgress(widget.rideId);
          break;
        default:
          final settlement = await _driverRepo.completeRide(widget.rideId, _myPhone!);
          if (!mounted) return;
          if (settlement != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('✅ تم إنهاء الرحلة — أرباحك: ${settlement.driverEarn.toStringAsFixed(0)} ج.م'), duration: const Duration(seconds: 4)),
            );
          }
          widget.onFinished?.call();
          Navigator.of(context).pop();
          return;
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _advancing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF9),
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

          if (!widget.isDriverView &&
              _lastNotifiedStatus != null &&
              _lastNotifiedStatus != status &&
              _statusNotif.containsKey(status)) {
            AppNotifications.instance.show('وصّلها — تحديث رحلتك', _statusNotif[status]!);
          }
          _lastNotifiedStatus = status;

          if (!widget.isDriverView && status == 'completed' && !_ratingPrompted && driverPhone != null && driverPhone.isNotEmpty) {
            _ratingPrompted = true;
            WidgetsBinding.instance.addPostFrameCallback((_) => _maybePromptRating(driverPhone, customerPhone));
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
                title: Text(widget.isDriverView ? 'تفاصيل الرحلة' : 'تتبّع الرحلة'),
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
                          color: AppColors.cardTint,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4))],
                        ),
                        child: isCancelled
                            ? Column(
                                children: const [
                                  Text('❌', style: TextStyle(fontSize: 32)),
                                  SizedBox(height: 8),
                                  Text('الرحلة ملغاة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.error)),
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
                          color: AppColors.cardTint,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _infoRow('من', '${ride['from_area'] ?? '—'}'),
                            if ((ride['stops'] as List?)?.isNotEmpty == true) ...[
                              const Divider(height: 20),
                              _infoRow(
                                '🛑 توقف عند',
                                (ride['stops'] as List)
                                    .map((s) => (s as Map?)?['name'] as String? ?? '—')
                                    .join(' ← '),
                              ),
                            ],
                            const Divider(height: 20),
                            _infoRow('إلى', '${ride['to_area'] ?? '—'}'),
                            const Divider(height: 20),
                            _infoRow('السائق', driverName?.isNotEmpty == true ? driverName! : 'جارٍ التعيين…'),
                            const Divider(height: 20),
                            _infoRow('الأجرة', '${ride['fare'] ?? 0} ج.م', highlight: true),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
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
                                title: const Text('إلغاء الرحلة؟'),
                                content: const Text('هل أنت متأكد إنك عايز تلغي الرحلة دي؟'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('تراجع')),
                                  TextButton(
                                    onPressed: () => Navigator.of(context).pop(true),
                                    child: const Text('إلغاء الرحلة', style: TextStyle(color: AppColors.error)),
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
                          child: const Text('إلغاء الرحلة'),
                        ),
                      if (widget.isDriverView && !isCancelled && status != 'completed' && status != 'pending')
                        _DriverStepButton(status: status, busy: _advancing, onTap: () => _advance(status)),
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
            color: highlight ? AppColors.success : Colors.black87,
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
  const _DriverStepButton({required this.status, required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'accepted' => ('📍 وصلت لنقطة الانطلاق', AppColors.primaryLight),
      'arrived' => ('✓ الراكب صعد، ابدأ الرحلة', AppColors.primary),
      _ => ('✓ وصلنا للوجهة — إنهاء الرحلة', AppColors.success),
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
class _LiveMapSection extends StatelessWidget {
  final RideRepository rideRepo;
  final String driverPhone;
  final Map<String, dynamic> ride;
  const _LiveMapSection({required this.rideRepo, required this.driverPhone, required this.ride});

  double? _num(dynamic v) => v == null ? null : (v as num).toDouble();

  @override
  Widget build(BuildContext context) {
    final fromLat = _num(ride['from_lat']);
    final fromLng = _num(ride['from_lng']);
    final toLat = _num(ride['to_lat']);
    final toLng = _num(ride['to_lng']);
    if (fromLat == null || fromLng == null || toLat == null || toLng == null) return const SizedBox.shrink();
    final origin = LatLng(fromLat, fromLng);
    final destination = LatLng(toLat, toLng);

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: rideRepo.watchDriverLocation(driverPhone),
      builder: (context, snap) {
        final loc = (snap.data != null && snap.data!.isNotEmpty) ? snap.data!.first : null;
        final driverLat = _num(loc?['lat']);
        final driverLng = _num(loc?['lng']);
        final driverHeading = _num(loc?['heading']);
        final driverPos = (driverLat != null && driverLng != null) ? LatLng(driverLat, driverLng) : null;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              decoration: BoxDecoration(
                color: AppColors.cardTint,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4))],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(14, 10, 14, 6),
                    child: Row(
                      children: [
                        Text('🚖', style: TextStyle(fontSize: 14)),
                        SizedBox(width: 6),
                        Text('السائق على الخريطة الآن', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
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
                    label: const Text('افتح في Google Maps'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => shareLocationOnWhatsApp(),
                    icon: const Icon(Icons.share_location_outlined),
                    label: const Text('شارك موقعك'),
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
        final bg = done || active ? AppColors.primary : Colors.white;
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
                step.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: done || active ? Colors.black87 : AppColors.textFaint,
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

    const categoryLabels = {'sedan': 'سيدان', 'suv': 'SUV / كروز', 'van': 'ميكروباص'};
    final carLine = [
      categoryLabels[vehicleCategory] ?? vehicleCategory,
      vehicleColor,
      vehicleModel,
      if (vehicleYear != null) '$vehicleYear',
    ].where((s) => s != null && s.isNotEmpty).join(' — ');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardTint,
        borderRadius: BorderRadius.circular(16),
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
                      (name != null && name.isNotEmpty) ? name : (fallbackName ?? 'السائق'),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.black87),
                    ),
                    if (carLine.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(carLine, style: const TextStyle(fontSize: 12, color: AppColors.textFaint, fontWeight: FontWeight.w700)),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      (regNumber != null && regNumber.isNotEmpty) ? '🚘 $regNumber' : '🚘 رقم اللوحة غير مسجّل',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: (regNumber != null && regNumber.isNotEmpty) ? Colors.black87 : AppColors.textFaint,
                      ),
                    ),
                    if (driverPhone != null && driverPhone!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      TrustBadge(
                        future: RatingsRepository().driverTrustBadge(driverPhone!),
                        trustedLabel: 'سائق موثوق',
                      ),
                    ],
                  ],
                ),
              ),
              if (driverPhone != null && driverPhone!.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(12)),
                  child: IconButton(
                    onPressed: () => callPhone(driverPhone!),
                    icon: const Icon(Icons.call, color: AppColors.success),
                    tooltip: 'اتصل بالسائق',
                  ),
                ),
            ],
          ),
          if (hasAc || isClean) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              children: [
                if (hasAc) _badge('❄️ مكيّفة'),
                if (isClean) _badge('🧼 نظيفة'),
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

class _CustomerCard extends StatelessWidget {
  final String? name;
  final String phone;
  const _CustomerCard({required this.name, required this.phone});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardTint,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.primaryLight,
            child: Text('🧑', style: TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              (name != null && name!.isNotEmpty) ? name! : 'العميل',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.black87),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(left: 6),
            decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(12)),
            child: IconButton(
              onPressed: () => callPhone(phone),
              icon: const Icon(Icons.call, color: AppColors.success),
              tooltip: 'اتصل بالعميل',
            ),
          ),
          Container(
            decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(12)),
            child: IconButton(
              onPressed: () => openWhatsApp(phone),
              icon: const Icon(Icons.chat, color: AppColors.success),
              tooltip: 'واتساب',
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
        const SnackBar(content: Text('تعذّر رفض العرض، حاول تاني')),
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
            color: AppColors.cardTint,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Text('🤝', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text('عروض أسعار السائقين', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
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
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'بنستنى سائقين يقدّموا أسعارهم… هتظهر هنا أول ما توصل',
                    style: TextStyle(fontSize: 12, color: AppColors.textFaint),
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
                      color: const Color(0xFFF7FAF9),
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
                                (name != null && name.isNotEmpty) ? name : 'سائق',
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
                                    : const Text('رفض', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
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
                                    : const Text('قبول', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
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
                  'السائق متوقع يوصل الساعة ${arTime(deadline)} (خلال حوالي ${etaMinutes!.round()} دقيقة)',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: Colors.black87),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'يرجى التواجد عند نقطة الانطلاق في الموعد — تأخير السائق أكتر من 5 دقايق بيحمّله غرامة 20 ج.م، فبلاش نتأخر عليه 🙏',
            style: TextStyle(fontSize: 11, color: AppColors.textFaint, height: 1.4),
          ),
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
      'completed' => ('وصل طلبك بنجاح', '🎉 مكتمل', AppColors.success),
      'in_progress' => ('السائق في الطريق إليك', '🛣️ في الطريق', AppColors.primary),
      'arrived' => ('السائق بانتظارك في نقطة الانطلاق', '📍 وصل', AppColors.primary),
      'accepted' => ('السائق في طريقه لاستلامك', '🚗 مقبولة', AppColors.primary),
      _ => ('بانتظار سائق يقبل الرحلة', '📋 جديدة', AppColors.textFaint),
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
            decoration: BoxDecoration(color: AppColors.cardTint, borderRadius: BorderRadius.circular(999)),
            child: Text(badge, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: badgeColor)),
          ),
        ],
      ),
    );
  }
}
