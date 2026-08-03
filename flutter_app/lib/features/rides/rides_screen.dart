import 'package:flutter/material.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import 'address_field.dart';
import 'fare_calculator.dart' as fare_calc;
import 'places_service.dart';
import 'ride_repository.dart';
import 'ride_tracking_screen.dart';

class RidesScreen extends StatefulWidget {
  const RidesScreen({super.key});

  @override
  State<RidesScreen> createState() => _RidesScreenState();
}

class _RidesScreenState extends State<RidesScreen> {
  final _rideRepo = RideRepository();

  PlaceResult? _from;
  PlaceResult? _to;
  int _passengers = 1;
  String _payment = 'cash';
  bool _submitting = false;
  UserSession? _session;

  double get _straightKm {
    if (_from == null || _to == null) return 0;
    return fare_calc.haversineKm(_from!.lat, _from!.lng, _to!.lat, _to!.lng);
  }

  double get _roadKm => _straightKm * fare_calc.roadFactor;
  int get _fare => _straightKm > 0 ? fare_calc.fareForDistance(_straightKm, toArea: _to?.name) : 0;
  int get _eta => _straightKm > 0 ? fare_calc.etaMinutes(_straightKm) : 0;

  @override
  void initState() {
    super.initState();
    SessionStore.load().then((s) => setState(() => _session = s));
  }

  Future<void> _submit() async {
    if (_from == null || _to == null || _session == null) return;
    setState(() => _submitting = true);

    final ride = await _rideRepo.createRide(
      customerPhone: _session!.phone,
      customerName: _session!.name,
      fromArea: _from!.name,
      fromLat: _from!.lat,
      fromLng: _from!.lng,
      toArea: _to!.name,
      toLat: _to!.lat,
      toLng: _to!.lng,
      distanceKm: _roadKm,
      fare: _fare,
      etaMinutes: _eta,
      passengers: _passengers,
      payment: _payment,
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

  @override
  Widget build(BuildContext context) {
    final ready = _from != null && _to != null && _session != null && !_submitting;

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
              AddressField(
                label: 'إلى',
                hint: 'الوجهة',
                onSelected: (r) => setState(() => _to = r),
              ),
              const SizedBox(height: 20),
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
              const SizedBox(height: 12),
              if (_straightKm > 0)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _statColumn('${(_roadKm).toStringAsFixed(1)} كم', 'المسافة'),
                      _statColumn('$_eta دقيقة', 'الوقت المتوقع'),
                      _statColumn('$_fare ج.م', 'الأجرة'),
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
                    : const Text('🚖 اطلب مشوارك الآن'),
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
