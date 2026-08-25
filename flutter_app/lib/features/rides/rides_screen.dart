import 'package:flutter/material.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import 'address_field.dart';
import 'fare_calculator.dart' as fare_calc;
import 'places_service.dart';
import 'ride_repository.dart';
import 'ride_tracking_screen.dart';

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
  bool _negotiable = false;
  bool _submitting = false;
  UserSession? _session;

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
    return _isExternal ? fare_calc.externalFareForDistance(_roadKm) : fare_calc.fareForDistance(_straightKm, toArea: _filledPoints.last.name);
  }

  int get _eta => _straightKm > 0 ? fare_calc.etaMinutes(_straightKm) : 0;

  bool get _hasMultiStop => _filledPoints.length > 2;

  @override
  void initState() {
    super.initState();
    SessionStore.load().then((s) => setState(() => _session = s));
  }

  Future<void> _submit() async {
    final points = _filledPoints;
    if (points.length < 2 || _session == null) return;
    setState(() => _submitting = true);

    final destination = points.last;
    final waypoints = points.sublist(1, points.length - 1); // between origin and final destination

    final ride = await _rideRepo.createRide(
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
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (ride == null || ride['id'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر إرسال الطلب، حاول مجدداً')),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RideTrackingScreen(rideId: ride['id'].toString())),
    );
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
    final ready = _filledPoints.length >= 2 && _session != null && !_submitting;

    return Scaffold(
      appBar: AppBar(title: const Text('مشاوير دمياط')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AddressField(
                label: 'من',
                hint: 'نقطة الانطلاق',
                showLocationButton: true,
                onSelected: (r) => setState(() => _from = r),
              ),
              const SizedBox(height: 16),
              for (var i = 0; i < _stops.length; i++) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: AddressField(
                        key: ValueKey('stop-$i-${_stops.length}'),
                        label: _stopLabel(i),
                        hint: i == _stops.length - 1 ? 'الوجهة' : 'وين تحب تقف؟',
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
                const SizedBox(height: 12),
              ],
              if (_stops.length < _maxStops)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _addStop,
                    icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                    label: const Text('إضافة نقطة توقف (مشوار متعدد)'),
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('عدد الركاب', style: TextStyle(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                    onPressed: _passengers > 1 ? () => setState(() => _passengers--) : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('$_passengers', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                  IconButton(
                    onPressed: _passengers < 4 ? () => setState(() => _passengers++) : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('طريقة الدفع', style: TextStyle(fontWeight: FontWeight.w700)),
              RadioListTile<String>(
                value: 'cash',
                groupValue: _payment,
                onChanged: (v) => setState(() => _payment = v!),
                title: const Text('💵 كاش عند الاستلام'),
                dense: true,
              ),
              RadioListTile<String>(
                value: 'wallet',
                groupValue: _payment,
                onChanged: (v) => setState(() => _payment = v!),
                title: const Text('📱 فودافون كاش / إنستاباي'),
                dense: true,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _negotiable,
                onChanged: (v) => setState(() => _negotiable = v),
                contentPadding: EdgeInsets.zero,
                dense: true,
                activeThumbColor: AppColors.primary,
                title: const Text('🤝 اطلب بسعر تفاوضي', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text(
                  'السائقين يقدّموا أسعارهم وانت تختار — بدل السعر الثابت',
                  style: TextStyle(fontSize: 11, color: AppColors.textFaint),
                ),
              ),
              const SizedBox(height: 12),
              if (_straightKm > 0)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(14),
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
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: ready ? _submit : null,
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(_negotiable ? '🤝 اطلب عروض أسعار من السائقين' : '🚖 اطلب مشوارك الآن'),
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
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primary)),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
      ],
    );
  }
}
