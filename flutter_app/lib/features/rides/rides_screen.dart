import 'package:flutter/material.dart';
import '../../core/feature_flags.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../shared/widgets/selectable_pill.dart';
import '../airport/airport_fare.dart' show qualityLabels, qualityMultiplier;
import '../coupons/coupon_field.dart';
import '../coupons/coupon_repository.dart';
import 'address_field.dart';
import 'fare_calculator.dart' as fare_calc;
import 'places_service.dart';
import 'ride_repository.dart';
import 'ride_tracking_screen.dart';
import 'scheduled_rides_screen.dart';

const int _maxStops = 3;

class RidesScreen extends StatefulWidget {
  const RidesScreen({super.key});

  @override
  State<RidesScreen> createState() => _RidesScreenState();
}

class _RidesScreenState extends State<RidesScreen> {
  final _rideRepo = RideRepository();

  PlaceResult? _from;
  // Sequential stops — the last non-null one is the ride's real
  // destination; any before it are intermediate waypoints (e.g. an errand
  // stop) passed to createRide as `stops`.
  final List<PlaceResult?> _stops = [null];
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

  double get _roadKm => _straightKm * fare_calc.roadFactor;
  bool get _isExternal => _roadKm > 0 && fare_calc.isExternalTrip(_roadKm);
  int get _fare {
    if (_straightKm <= 0) return 0;
    return _isExternal
        ? fare_calc.externalFareForDistance(_roadKm, qualityTier: _qualityTier, surgeMultiplier: _surgeMult)
        : fare_calc.fareForDistance(_straightKm, toArea: _filledPoints.last.name, qualityTier: _qualityTier, surgeMultiplier: _surgeMult);
  }

  int get _eta => _straightKm > 0 ? fare_calc.etaMinutes(_straightKm) : 0;

  bool get _hasMultiStop => _filledPoints.length > 2;

  @override
  void initState() {
    super.initState();
    SessionStore.load().then((s) => setState(() => _session = s));
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
        SnackBar(content: Text('تعذّر إرسال الطلب: $e'), backgroundColor: AppColors.error, duration: const Duration(seconds: 6)),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _submitting = false);

    final rideId = ride?['id']?.toString();
    if (rideId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر إرسال الطلب، حاول مجدداً')),
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
            SnackBar(content: Text('🎟️ اتضاف ${credited.toStringAsFixed(0)} ج.م لمحفظتك من كود الخصم')),
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
        SnackBar(content: Text('✅ اتحجزت رحلتك ليوم ${at.day}/${at.month} الساعة ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}')),
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
        const SnackBar(content: Text('لازم الميعاد يكون بعد نص ساعة على الأقل من دلوقتي')),
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
    if (index == _stops.length - 1) return _stops.length > 1 ? 'الوجهة النهائية' : 'إلى';
    return 'نقطة توقف ${index + 1}';
  }

  @override
  Widget build(BuildContext context) {
    if (_filledPoints.length >= 2) _maybeRefreshSurge();
    final ready = _filledPoints.length >= 2 && _session != null && !_submitting;

    return Scaffold(
      appBar: AppBar(
        title: const Text('مشاوير دمياط'),
        actions: [
          if (FeatureFlags.scheduledRidesEnabled && _session != null)
            IconButton(
              tooltip: 'رحلاتي المجدولة',
              icon: const Icon(Icons.event_available),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ScheduledRidesScreen(phone: _session!.phone)),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionLabel('📍 نقطة الانطلاق والوجهة'),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE9ECEB)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AddressField(
                      label: 'من',
                      hint: 'نقطة الانطلاق',
                      showLocationButton: true,
                      prefixIcon: Icons.trip_origin,
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
                              hint: i == _stops.length - 1 ? 'الوجهة' : 'وين تحب تقف؟',
                              prefixIcon: i == _stops.length - 1 ? Icons.flag_outlined : Icons.location_on_outlined,
                              onSelected: (r) => setState(() => _stops[i] = r),
                            ),
                          ),
                          if (_stops.length > 1)
                            IconButton(
                              icon: const Icon(Icons.close, color: AppColors.textFaint),
                              onPressed: () => _removeStop(i),
                              tooltip: 'حذف نقطة التوقف',
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
                          label: const Text('إضافة نقطة توقف (مشوار متعدد)', style: TextStyle(fontSize: 12)),
                        ),
                      ),
                    const Divider(height: 20),
                    Row(
                      children: [
                        const Icon(Icons.people_outline, size: 20, color: AppColors.textFaint),
                        const SizedBox(width: 8),
                        const Text('عدد الركاب', style: TextStyle(fontWeight: FontWeight.w700)),
                        const Spacer(),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: _passengers > 1 ? () => setState(() => _passengers--) : null,
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Text('$_passengers', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: _passengers < 4 ? () => setState(() => _passengers++) : null,
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _sectionLabel('⭐ نوع الخدمة والدفع'),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE9ECEB)),
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
                              label: '${qualityLabels[tier]!}'
                                  '${tier == 'regular' ? '' : ' (+${(((qualityMultiplier[tier] ?? 1) - 1) * 100).round()}%)'}',
                              selected: _qualityTier == tier,
                              onTap: () => setState(() => _qualityTier = tier),
                            ),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
                      child: Text(
                        'تغيير نوع الخدمة بعد بدء الرحلة يُعد مخالفة — الشركة والكابتن غير مسؤولين عن هذا الاختيار.',
                        style: TextStyle(fontSize: 9.5, color: AppColors.textFaint, height: 1.3),
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          SelectablePill(label: '💵 كاش عند الاستلام', selected: _payment == 'cash', onTap: () => setState(() => _payment = 'cash')),
                          SelectablePill(label: '📱 فودافون كاش / إنستاباي', selected: _payment == 'wallet', onTap: () => setState(() => _payment = 'wallet')),
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
                      title: const Text('🤝 اطلب بسعر تفاوضي', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      subtitle: const Text(
                        'السائقين يقدّموا أسعارهم وانت تختار',
                        style: TextStyle(fontSize: 10.5, color: AppColors.primaryDark, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (_straightKm > 0) ...[
                _sectionLabel('💰 ملخص الأجرة'),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE9ECEB)),
                  ),
                  child: Column(
                    children: [
                      if (_negotiable)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 10),
                          child: Text(
                            '🤝 وضع تفاوضي — الرقم اللي تحت ده تقديري بس، السعر النهائي هيكون حسب عرض السائق اللي هتختاره',
                            style: TextStyle(fontSize: 11, color: AppColors.primaryDark, fontWeight: FontWeight.w700),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      if (_isExternal)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 10),
                          child: Text(
                            '🛣️ رحلة خارج محافظة دمياط — سعر مختلف عن المشاوير الداخلية',
                            style: TextStyle(fontSize: 11, color: AppColors.primaryDark, fontWeight: FontWeight.w700),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      if (_surgeMult > 1)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            '🔥 الطلب مرتفع دلوقتي — السعر شمل زيادة مؤقتة ×${_surgeMult.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 11, color: AppColors.error, fontWeight: FontWeight.w800),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      if (_hasMultiStop)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            '🛑 مشوار متعدد النقاط (${_filledPoints.length - 1} محطة) — الأجرة إجمالي كل المراحل',
                            style: const TextStyle(fontSize: 11, color: AppColors.primaryDark, fontWeight: FontWeight.w700),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _statColumn('${(_roadKm).toStringAsFixed(1)} كم', 'المسافة'),
                          _statColumn('$_eta دقيقة', 'الوقت المتوقع'),
                          _statColumn('$_fare ج.م', 'الأجرة'),
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
                      color: _scheduledAt != null ? AppColors.primary.withValues(alpha: 0.08) : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _scheduledAt != null ? AppColors.primary : const Color(0xFFE9ECEB)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.event_available, size: 18, color: AppColors.primaryDark),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _scheduledAt == null
                                ? '🗓️ جدولة الرحلة لميعاد لاحق (اختياري)'
                                : 'مجدولة: ${_scheduledAt!.day}/${_scheduledAt!.month} — ${_scheduledAt!.hour.toString().padLeft(2, '0')}:${_scheduledAt!.minute.toString().padLeft(2, '0')}',
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
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: ready ? _submit : null,
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(_scheduledAt != null
                        ? '🗓️ جدولة المشوار'
                        : (_negotiable ? '🤝 اطلب عروض أسعار من السائقين' : '🚖 اطلب مشوارك الآن')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statColumn(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryDark)),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.primaryDark, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, right: 4),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
      );
}
