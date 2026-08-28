import 'package:flutter/material.dart';
import '../../core/date_format_ar.dart';
import '../../core/phone_utils.dart';
import '../../core/pricing_settings.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../rides/address_field.dart';
import '../rides/fare_calculator.dart' as fare_calc;
import '../rides/places_service.dart';
import 'airport_booking_confirmation_screen.dart';
import 'airport_fare.dart' as fare;
import 'airport_repository.dart';

/// Ported from airport.astro — same fields, same fare formula
/// (db/rides-vehicle-pricing.sql / src/data/airports.ts), same real-driver
/// vehicle catalog, and the same "رحلتك" trip-summary card (route + live
/// timeline + price breakdown) shown before booking. Distance/drive-time
/// are estimated via haversine × road factor (same fallback
/// rides_screen.dart uses) instead of a live Distance Matrix call.
class AirportScreen extends StatefulWidget {
  const AirportScreen({super.key});

  @override
  State<AirportScreen> createState() => _AirportScreenState();
}

class _AirportScreenState extends State<AirportScreen> {
  final _repo = AirportRepository();

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
    super.dispose();
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

  double get _roadKm => _straightKm * fare_calc.roadFactor;

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
      setState(() => _error = 'يرجى إدخال اسم المسافر.');
      return;
    }
    if (!isEgyptianMobile(phone)) {
      setState(() => _error = egPhoneError);
      return;
    }
    if (_from == null) {
      setState(() => _error = _direction == 'departure' ? 'يرجى اختيار نقطة الانطلاق.' : 'يرجى اختيار وجهتك.');
      return;
    }
    if (_airport == null) {
      setState(() => _error = 'يرجى اختيار المطار.');
      return;
    }
    if (_flightTime == null) {
      setState(() => _error = 'يرجى تحديد تاريخ ووقت الرحلة.');
      return;
    }
    if (_selectedVehicle == null) {
      setState(() => _error = 'لا توجد سيارات مسجّلة متاحة حاليًا.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final directionLabel = _direction == 'departure' ? 'مغادر من مصر' : 'قادم إلى مصر';
      final tripLabel = _tripType == 'international' ? 'دولية' : 'محلية';
      final notes = [
        '🛫 توصيل مطار — $directionLabel ($tripLabel)',
        '🚘 ${fare.categoryLabels[_category]} ${_selectedVehicle!.name} $_selectedYear',
        if (_quality != 'regular') '⭐ الخدمة المطلوبة: ${fare.qualityLabels[_quality]}',
        if (_companions > 0) '👥 مرافقين رايح جاي: $_companions',
        if (_bags > 0) '🧳 شنط: $_bags',
        if (_airlineCtrl.text.trim().isNotEmpty) '✈️ شركة الطيران: ${_airlineCtrl.text.trim()}',
        if (_flightNoCtrl.text.trim().isNotEmpty) '🎫 رقم الرحلة: ${_flightNoCtrl.text.trim()}',
        if (_terminalCtrl.text.trim().isNotEmpty) '🏁 الصالة: ${_terminalCtrl.text.trim()}',
        if (_flightCountryCtrl.text.trim().isNotEmpty) '🌍 الدولة: ${_flightCountryCtrl.text.trim()}',
        if (_addressCtrl.text.trim().isNotEmpty) '📍 العنوان بالتفصيل: ${_addressCtrl.text.trim()}',
        '🕐 وقت ${_direction == "departure" ? "الإقلاع" : "الهبوط"}: ${arDateTime(_flightTime!)}',
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
          _error = 'تعذّر إرسال الطلب، حاول مرة أخرى.';
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
        _error = 'تعذّر إرسال الطلب: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final catInfo = fare.vehicleCategoryInfo[_category];
    final maxTravelers = catInfo?.maxTravelers ?? 3;
    final maxBags = catInfo?.maxBags ?? 2;

    return Scaffold(
      appBar: AppBar(title: const Text('توصيل المطار')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('1', 'نوع الرحلة'),
          _sectionCard([
            _radioRow('اتجاه الرحلة', _direction, {
              'departure': '🛫 مغادر من مصر',
              'arrival': '🛬 قادم إلى مصر',
            }, (v) => setState(() => _direction = v)),
            const SizedBox(height: 10),
            _radioRow('نوع الرحلة', _tripType, {
              'international': '✈️ دولية (3 ساعات)',
              'domestic': '🛫 محلية (ساعتان)',
            }, (v) => setState(() => _tripType = v)),
            const SizedBox(height: 8),
            Text(
              _tripType == 'international'
                  ? 'ℹ️ دولية: للرحلات خارج مصر — بيحسب وصولك المطار قبل الإقلاع بـ 3 ساعات (وقت تسجيل وجوازات أطول)، وبعد الهبوط بيدي 45 دقيقة لإجراءات الجوازات والجمارك.'
                  : 'ℹ️ محلية: لرحلات داخل مصر — بيحسب وصولك المطار قبل الإقلاع بساعتين بس، وبعد الهبوط 20 دقيقة فقط (من غير جوازات/جمارك).',
              style: const TextStyle(fontSize: 11, color: AppColors.primaryDark, fontWeight: FontWeight.w600),
            ),
          ]),
          const SizedBox(height: 18),

          _sectionTitle('2', 'اختيار السيارة'),
          _sectionCard([
            if (_loadingVehicles)
              const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
            else if (_vehicles.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('لا توجد سيارات مسجّلة متاحة حاليًا.', style: TextStyle(color: AppColors.error, fontSize: 12)),
              )
            else ...[
              Wrap(
                spacing: 8,
                children: fare.vehicleCategoryInfo.keys
                    .where((cat) => _vehicles.any((v) => v.category == cat))
                    .map((cat) => ChoiceChip(
                          label: Text('${fare.vehicleCategoryInfo[cat]!.icon} ${fare.categoryLabels[cat]!.replaceAll(RegExp(r'^[^ ]+ '), '')}'),
                          selected: _category == cat,
                          onSelected: (_) => _onCategoryChanged(cat),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<fare.RegisteredVehicle>(
                initialValue: _selectedVehicle,
                decoration: const InputDecoration(labelText: 'الماركة والموديل'),
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
                  decoration: const InputDecoration(labelText: 'سنة الصنع'),
                  items: [for (var y = _selectedVehicle!.yearTo; y >= _selectedVehicle!.yearFrom; y--) y]
                      .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                      .toList(),
                  onChanged: (y) => setState(() => _selectedYear = y ?? _selectedYear),
                ),
              const SizedBox(height: 14),
              const Text('مستوى الخدمة المطلوب', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: fare.qualityLabels.keys
                    .map((q) => ChoiceChip(
                          label: Text(
                            '${fare.qualityLabels[q]}'
                            '${q == 'regular' ? '' : ' (+${(((fare.qualityMultiplier[q] ?? 1) - 1) * 100).round()}%)'}',
                          ),
                          selected: _quality == q,
                          onSelected: (_) => setState(() => _quality = q),
                        ))
                    .toList(),
              ),
            ],
          ]),
          const SizedBox(height: 18),

          _sectionTitle('3', 'نقطة البداية والوصول'),
          _sectionCard([
            AddressField(
              label: _direction == 'departure' ? 'نقطة البداية (منطقتك)' : 'وجهتك (منطقتك)',
              hint: 'اكتب منطقتك أو حيّك في دمياط...',
              showLocationButton: true,
              onSelected: (r) => setState(() => _from = r),
            ),
            const SizedBox(height: 12),
            AddressField(
              label: _direction == 'departure' ? 'المطار (نقطة النهاية)' : 'المطار (نقطة البداية)',
              hint: 'ابحث باسم المطار: مطار القاهرة، مطار شرم الشيخ...',
              placesTypes: 'airport',
              onSelected: (r) => setState(() => _airport = r),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _addressCtrl,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'عنوان الاستلام بالتفصيل (اختياري)', hintText: 'الحي، الشارع، رقم المبنى، علامة مميزة...'),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickFlightTime,
              child: InputDecorator(
                decoration: InputDecoration(labelText: _direction == 'departure' ? 'تاريخ ووقت إقلاع الطائرة' : 'تاريخ ووقت هبوط الطائرة'),
                child: Text(
                  _flightTime == null ? 'اختر التاريخ والوقت' : arDateTime(_flightTime!),
                  style: TextStyle(color: _flightTime == null ? AppColors.textFaint : Colors.black87),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 18),

          _sectionTitle('4', 'الركاب والأمتعة'),
          _sectionCard([
            _stepperRow('عدد المسافرين', _passengers, 1, maxTravelers, (v) => setState(() => _passengers = v)),
            _stepperRow('مرافق رايح جاي (${fare.companionFee} ج.م/فرد)', _companions, 0, 9, (v) => setState(() => _companions = v)),
            _stepperRow('شنط كبيرة (تُسجَّل في الطائرة)', _bags, 0, maxBags, (v) => setState(() => _bags = v)),
          ]),
          const SizedBox(height: 18),

          _sectionTitle('5', 'أوقات الانتظار'),
          _sectionCard([
            DropdownButtonFormField<int>(
              initialValue: _waitPickupMin,
              decoration: const InputDecoration(labelText: 'انتظار السائق عند الاستلام'),
              items: const [
                DropdownMenuItem(value: 0, child: Text('بدون انتظار')),
                DropdownMenuItem(value: 15, child: Text('15 دقيقة مجانًا')),
                DropdownMenuItem(value: 30, child: Text('30 دقيقة (+30 ج.م)')),
                DropdownMenuItem(value: 45, child: Text('45 دقيقة (+60 ج.م)')),
                DropdownMenuItem(value: 60, child: Text('ساعة كاملة (+90 ج.م)')),
              ],
              onChanged: (v) => setState(() => _waitPickupMin = v ?? 0),
            ),
            if (_direction != 'arrival') ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                initialValue: _waitAirportMin,
                decoration: const InputDecoration(labelText: 'انتظار السائق في ساحة المطار'),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('بدون انتظار')),
                  DropdownMenuItem(value: 30, child: Text('30 دقيقة مجانًا')),
                  DropdownMenuItem(value: 60, child: Text('ساعة (+40 ج.م)')),
                  DropdownMenuItem(value: 90, child: Text('ساعة ونص (+80 ج.م)')),
                ],
                onChanged: (v) => setState(() => _waitAirportMin = v ?? 0),
              ),
            ],
          ]),
          const SizedBox(height: 18),

          _sectionTitle('6', 'بيانات الطيران (اختياري)'),
          _sectionCard([
            TextField(controller: _airlineCtrl, decoration: const InputDecoration(labelText: 'شركة الطيران', hintText: 'مثال: مصر للطيران')),
            const SizedBox(height: 10),
            TextField(controller: _flightNoCtrl, decoration: const InputDecoration(labelText: 'رقم الرحلة', hintText: 'MS 712')),
            const SizedBox(height: 10),
            TextField(controller: _terminalCtrl, decoration: const InputDecoration(labelText: 'رقم الصالة / المبنى', hintText: 'مثال: مبنى 2')),
            const SizedBox(height: 10),
            TextField(
              controller: _flightCountryCtrl,
              decoration: InputDecoration(labelText: _direction == 'departure' ? 'مسافر إلى (الدولة)' : 'قادم من (الدولة)', hintText: 'مثال: السعودية'),
            ),
          ]),
          const SizedBox(height: 18),

          _sectionTitle('7', 'بيانات المسافر'),
          _sectionCard([
            TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'اسم المسافر')),
            const SizedBox(height: 10),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(labelText: 'رقم الجوال', hintText: '01xxxxxxxxx'),
            ),
          ]),
          const SizedBox(height: 20),

          if (_roadKm > 0 && _flightTime != null)
            _tripSummaryCard()
          else ...[
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFFEF2F2), border: Border.all(color: const Color(0xFFFCA5A5)), borderRadius: BorderRadius.circular(10)),
                  child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
                ),
              ),
            OutlinedButton(
              onPressed: _submitting ? null : _submit,
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              child: const Text('تأكيد الحجز ←'),
            ),
            const SizedBox(height: 6),
            const Text('كمّل اختيار المطار وتاريخ الرحلة عشان يظهر الجدول الزمني والسعر', style: TextStyle(fontSize: 11, color: AppColors.textFaint), textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }

  /// Matches airport.astro's "رحلتك" sidebar: route header, live timeline,
  /// price breakdown table, total, error box, and the confirm button.
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
        color: AppColors.cardTint,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppColors.primaryDark, AppColors.primary])),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('رحلتك', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
                const SizedBox(height: 4),
                Text(
                  '${_from?.name ?? "—"} ← ${_airport?.name ?? "—"}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < steps.length; i++) _timelineRow(steps[i], isLast: i == steps.length - 1),
                const Divider(height: 24),
                _fareLine('المسافة', '${_roadKm.toStringAsFixed(0)} كم', isText: true),
                _fareLine('سعر المسافة', '$_baseFare ج.م', isText: true),
                _fareLine('السيارة', vehicleLabel, isText: true),
                if (_extraBagsFee > 0) _fareLine('شنط إضافية', '$_extraBagsFee ج.م', isText: true),
                if (_companionsFee > 0) _fareLine('مرافق رايح جاي', '$_companionsFee ج.م', isText: true),
                if (_waitPickupFee > 0) _fareLine('انتظار عند الاستلام', '$_waitPickupFee ج.م', isText: true),
                if (_waitAirportFee > 0) _fareLine('انتظار في ساحة المطار', '$_waitAirportFee ج.م', isText: true),
                const Divider(height: 24),
                _fareLine('الإجمالي', '$_total ج.م', bold: true),
                const SizedBox(height: 16),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFFFEF2F2), border: Border.all(color: const Color(0xFFFCA5A5)), borderRadius: BorderRadius.circular(10)),
                      child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
                    ),
                  ),
                ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: _submitting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('تأكيد الحجز ←'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'سعر ثابت حسب المسافة — الدفع نقدًا أو إلكترونيًا',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, color: AppColors.textFaint),
                ),
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
                  Text('$dateStr في $timeStr', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: AppColors.primary)),
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

  String _weekday(int w) => const ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'][w - 1];
  String _month(int m) => const [
        'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
        'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
      ][m - 1];

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
  Widget _sectionCard(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.cardTint, borderRadius: BorderRadius.circular(16)),
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
        Wrap(
          spacing: 8,
          children: options.entries
              .map((e) => ChoiceChip(label: Text(e.value), selected: value == e.key, onSelected: (_) => onChanged(e.key)))
              .toList(),
        ),
      ],
    );
  }

  Widget _stepperRow(String label, int value, int min, int max, ValueChanged<int> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
          IconButton(onPressed: value > min ? () => onChanged(value - 1) : null, icon: const Icon(Icons.remove_circle_outline)),
          Text('$value', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          IconButton(onPressed: value < max ? () => onChanged(value + 1) : null, icon: const Icon(Icons.add_circle_outline)),
        ],
      ),
    );
  }
}
