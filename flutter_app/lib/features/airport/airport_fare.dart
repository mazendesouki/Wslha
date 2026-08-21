// Ported 1:1 from src/data/airports.ts — keep both in sync (also mirrored in
// db/rides-vehicle-pricing.sql per that file's own warning comments).

import '../../core/pricing_settings.dart';

class RegisteredVehicle {
  final String id; // category|name
  final String category; // sedan | suv | van
  final String name;
  final int yearFrom;
  final int yearTo;
  RegisteredVehicle({
    required this.id,
    required this.category,
    required this.name,
    required this.yearFrom,
    required this.yearTo,
  });
}

const Map<String, String> categoryLabels = {
  'sedan': '🚗 سيدان',
  'suv': '🚙 SUV / كروز',
  'van': '🚐 ميكروباص',
};

/// App-only preference on top of the base category+year price (not yet
/// mirrored on the web or enforced server-side — same trust model as the
/// rest of airport pricing today). Percentages are a starting point, not a
/// confirmed business number — adjust freely.
const Map<String, String> qualityLabels = {
  'regular': 'عادية',
  'clean': '🧼 نظيفة',
  'ac': '❄️ مكيّفة',
  'modern': '✨ موديل حديث',
};

const Map<String, double> qualityMultiplier = {
  'regular': 1.0,
  'clean': 1.08,
  'ac': 1.12,
  'modern': 1.20,
};

/// TRIP_RATES.airport — sedan/SUV/van per-km rate before the year
/// adjustment. Admin-configurable (PricingSettings) — airport rides have
/// no server-side fare recompute, so this IS the real charged rate, not
/// just a preview.
double _airportRatePerKmBase(String category) {
  switch (category) {
    case 'suv':
      return PricingSettings.airportRateSuv;
    case 'van':
      return PricingSettings.airportRateVan;
    default:
      return PricingSettings.airportRateSedan;
  }
}

/// yearMultiplier() — 2021 baseline (×1.0), ±3.5%/year, clamped 0.8–1.35.
double yearMultiplier(int year) {
  final raw = 1 + (year - 2021) * 0.035;
  final clamped = raw.clamp(0.8, 1.35);
  return (clamped * 1000).roundToDouble() / 1000;
}

double airportRatePerKm(String category, int year) {
  return _airportRatePerKmBase(category) * yearMultiplier(year);
}

double get airportBaseFee => PricingSettings.airportBaseFee;
double get airportMinFare => PricingSettings.airportMinFare; // ج.م — الحد الأدنى لأي رحلة مطار

/// fareForVehicle() — base + distance × effective rate, rounded up to 50,
/// floored at airportMinFare.
int fareForVehicle(double distanceKm, String category, int year) {
  final raw = airportBaseFee + distanceKm * airportRatePerKm(category, year);
  final rounded = (raw / 50).ceil() * 50;
  return rounded < airportMinFare ? airportMinFare.round() : rounded;
}

const int extraBagFee = 25;
const int companionFee = 500; // ج.م per returning companion (round trip)
const int waitPickupFree = 15;
const int waitPickupPer15 = 30;
const int waitAirportFree = 30;
const int waitAirportPer30 = 40;

int waitPickupFeeFor(int minutes) {
  if (minutes <= waitPickupFree) return 0;
  return ((minutes - waitPickupFree) / 15).floor() * waitPickupPer15;
}

int waitAirportFeeFor(int minutes) {
  if (minutes <= waitAirportFree) return 0;
  return ((minutes - waitAirportFree) / 30).floor() * waitAirportPer30;
}

/// VEHICLE_TYPES — per-category free bag allowance + capacity, for the UI.
class VehicleCategoryInfo {
  final String category;
  final String icon;
  final String desc;
  final int maxTravelers;
  final int freeBags;
  final int maxBags;
  const VehicleCategoryInfo({
    required this.category,
    required this.icon,
    required this.desc,
    required this.maxTravelers,
    required this.freeBags,
    required this.maxBags,
  });
}

const Map<String, VehicleCategoryInfo> vehicleCategoryInfo = {
  'sedan': VehicleCategoryInfo(
    category: 'sedan', icon: '🚗', desc: 'تويوتا / هيونداي',
    maxTravelers: 3, freeBags: 2, maxBags: 2,
  ),
  'suv': VehicleCategoryInfo(
    category: 'suv', icon: '🚙', desc: 'لاند كروزر / باترول',
    maxTravelers: 6, freeBags: 4, maxBags: 6,
  ),
  'van': VehicleCategoryInfo(
    category: 'van', icon: '🚐', desc: 'H1 / سبرينتر',
    maxTravelers: 10, freeBags: 8, maxBags: 20,
  ),
};

/// Fixed reference point (Damietta) used for the straight-line distance
/// estimate to the chosen airport — same fallback approach rides_screen.dart
/// uses (haversine × road factor) instead of a live Distance Matrix API call,
/// avoiding another Google API scope requirement for this pass.
const double damiettaLat = 31.418;
const double damiettaLng = 31.814;

// ─── Timeline (رحلتك) — ported from airport.astro's live schedule preview ──
const Map<String, int> checkinBufferMinutes = {'domestic': 120, 'international': 180};
const int safetyMarginMinutes = 20;
const Map<String, int> arrivalBufferMinutes = {'domestic': 20, 'international': 45};
const int driverArrivalBeforeLandingMinutes = 15;
// Airline check-in desks typically close ~1h before departure — airport.astro
// shows this as a distinct "آخر موعد للتسجيل" step; not one of the named
// exported constants in airports.ts, so this is a best-effort match to the
// timing shown there rather than a verified shared constant.
const int checkinDeskClosesBeforeFlightMinutes = 60;

class TimelineStep {
  final String icon;
  final String label;
  final String sub;
  final DateTime time;
  const TimelineStep({required this.icon, required this.label, required this.sub, required this.time});
}

/// Builds the same event sequence airport.astro's sidebar timeline shows,
/// for whichever direction is selected.
List<TimelineStep> buildTimeline({
  required String direction, // departure | arrival
  required String tripType, // international | domestic
  required DateTime flightTime,
  required int driveMinutes,
}) {
  final buffer = checkinBufferMinutes[tripType] ?? checkinBufferMinutes['international']!;

  if (direction == 'departure') {
    final airportArrival = flightTime.subtract(Duration(minutes: buffer));
    final pickupDeparture = airportArrival.subtract(Duration(minutes: driveMinutes + safetyMarginMinutes));
    final checkinDeadline = flightTime.subtract(const Duration(minutes: checkinDeskClosesBeforeFlightMinutes));
    return [
      TimelineStep(icon: '🚗', label: 'وصول السائق للاستلام', sub: 'موعد وصول السائق للاستلام', time: pickupDeparture),
      TimelineStep(icon: '⏳', label: 'المغادرة من نقطة البداية', sub: 'زمن الطريق ~$driveMinutes دقيقة + هامش أمان', time: pickupDeparture),
      TimelineStep(icon: '📍', label: 'الوصول إلى المطار', sub: 'قبل الإقلاع بـ ${(buffer / 60).round()} ساعة', time: airportArrival),
      TimelineStep(icon: '🎫', label: 'آخر موعد للتسجيل', sub: 'آخر موعد لتسليم الأمتعة عند الكاونتر', time: checkinDeadline),
      TimelineStep(icon: '🛫', label: 'إقلاع الطائرة', sub: '', time: flightTime),
    ];
  }

  return buildArrivalTimeline(flightTime: flightTime, tripType: tripType, driveMinutes: driveMinutes);
}

List<TimelineStep> buildArrivalTimeline({
  required DateTime flightTime,
  required String tripType,
  required int driveMinutes,
}) {
  final arrivalBuf = arrivalBufferMinutes[tripType] ?? arrivalBufferMinutes['international']!;
  final driverAtAirport = flightTime.subtract(Duration(minutes: driverArrivalBeforeLandingMinutes));
  final passengerReady = flightTime.add(Duration(minutes: arrivalBuf));
  final homeArrival = passengerReady.add(Duration(minutes: driveMinutes + safetyMarginMinutes));
  return [
    TimelineStep(icon: '🛬', label: 'هبوط الطائرة', sub: '', time: flightTime),
    TimelineStep(icon: '🚗', label: 'وصول السائق للمطار', sub: 'قبل الهبوط بـ $driverArrivalBeforeLandingMinutes دقيقة', time: driverAtAirport),
    TimelineStep(icon: '🛄', label: 'جاهزية المسافر', sub: 'بعد إنهاء إجراءات الجوازات والأمتعة', time: passengerReady),
    TimelineStep(icon: '📍', label: 'المغادرة من المطار', sub: 'زمن الطريق ~$driveMinutes دقيقة + هامش أمان', time: passengerReady),
    TimelineStep(icon: '🏠', label: 'الوصول للوجهة', sub: '', time: homeArrival),
  ];
}

/// The single most actionable moment for a driver looking at an airport
/// job — when they need to be at the pickup point (departure) or at the
/// airport (arrival) — read straight from a `rides` row's persisted
/// flight_time/airport_direction/airport_trip_type (see
/// db/security-32-airport-flight-time.sql). Returns null if the ride
/// isn't an airport booking or predates those columns.
DateTime? primaryPickupTime(Map<String, dynamic> ride) {
  final rawFlightTime = ride['flight_time'];
  if (rawFlightTime == null) return null;
  final flightTime = DateTime.tryParse(rawFlightTime.toString())?.toLocal();
  if (flightTime == null) return null;
  final direction = ride['airport_direction'] as String? ?? 'departure';
  final tripType = ride['airport_trip_type'] as String? ?? 'international';
  final driveMinutes = (ride['eta_minutes'] as num?)?.toInt() ?? 30;
  final steps = buildTimeline(direction: direction, tripType: tripType, flightTime: flightTime, driveMinutes: driveMinutes);
  return steps.first.time;
}
