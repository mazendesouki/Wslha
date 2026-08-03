import 'dart:math' as math;

// Ported 1:1 from rides.astro's fareFor()/tieredKm()/resolveZone(), which is
// the formula actually enforced server-side by guard_ride_fare() (see
// db/rides-vehicle-pricing.sql) — NOT the older flat base+perKm formula this
// file used to have, which drifted from what the server actually charges
// (customer would see one quote, then the server-side guard trigger would
// silently recompute and overwrite it with a different fare). This app
// doesn't offer a vehicle-category picker on the regular rides screen (only
// airport does), so it always books as the same sedan/2022 default the
// server falls back to when vehicle_model/vehicle_year are omitted.
const double baseFare = 25;
const double minFare = 40;
const double roadFactor = 1.35;
const double _sedanRatePerKm = 8; // TRIP_RATES.local.sedan
const double _defaultYearMult = 1.035; // yearMultiplier(2022) — the server's fallback year

class _FareZone {
  final double factor;
  final double surcharge;
  final List<String> keywords;
  const _FareZone(this.factor, this.surcharge, this.keywords);
}

// Mirrors FARE_ZONES in src/data/airports.ts.
const List<_FareZone> _fareZones = [
  _FareZone(1.15, 10, ['رأس البر', 'راس البر']),
  _FareZone(1.10, 15, ['فارسكور', 'الزرقا', 'كفر البطيخ', 'الروضة', 'كفر سعد', 'ميت أبو غالب', 'عزبة البرج', 'الرحامنة', 'السرو']),
  _FareZone(1.05, 10, ['الصناعية', 'ميناء', 'الميناء', 'شطا']),
];

_FareZone _resolveZone(String? destName) {
  if (destName == null || destName.isEmpty) return const _FareZone(1, 0, []);
  for (final z in _fareZones) {
    if (z.keywords.any((k) => destName.contains(k))) return z;
  }
  return const _FareZone(1, 0, []);
}

double _tieredKm(double km) {
  final t1 = math.min(km, 3);
  final t2 = math.min(math.max(km - 3, 0), 7); // 10 - 3
  final t3 = math.max(km - 10, 0);
  return t1 * 1.15 + t2 * 1.0 + t3 * 0.9;
}

double haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLng = (lng2 - lng1) * math.pi / 180;
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(lat1 * math.pi / 180) * math.cos(lat2 * math.pi / 180) * math.pow(math.sin(dLng / 2), 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// [straightKm] is the haversine distance; road distance (× roadFactor) is
/// what the tiered meter actually runs on, same as the web.
int fareForDistance(double straightKm, {String? toArea}) {
  final roadKm = straightKm * roadFactor;
  final zone = _resolveZone(toArea);
  final effRate = _sedanRatePerKm * _defaultYearMult;
  final raw = (baseFare + _tieredKm(roadKm) * effRate) * zone.factor + zone.surcharge;
  return (math.max(raw, minFare) / 5).ceil() * 5;
}

int etaMinutes(double straightKm) {
  return ((straightKm * roadFactor) / 40 * 60).ceil(); // 40 km/h avg
}
