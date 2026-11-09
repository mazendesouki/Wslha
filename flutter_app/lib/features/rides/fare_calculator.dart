import 'dart:math' as math;
import '../../core/pricing_settings.dart';
import '../airport/airport_fare.dart' show qualityMultiplier;

// Ported 1:1 from rides.astro's fareFor()/tieredKm()/resolveZone(), which is
// the formula actually enforced server-side by guard_ride_fare() (see
// db/rides-vehicle-pricing.sql) — NOT the older flat base+perKm formula this
// file used to have, which drifted from what the server actually charges
// (customer would see one quote, then the server-side guard trigger would
// silently recompute and overwrite it with a different fare). rides_screen
// .dart now offers a real vehicle picker (db/security-179) — category/year/
// kmPerLiter below reflect whatever car is actually selected there; a
// caller that never passes them still gets the old sedan/2022/no-fuel-cost
// default, matching the server's own fallback for a null vehicle_model.
//
// baseFare/minFare/sedan rate are admin-configurable (PricingSettings) —
// this is only a client-side preview, guard_ride_fare() re-enforces the
// real numbers server-side regardless of what this shows.
double get baseFare => PricingSettings.localBaseFee;
double get minFare => PricingSettings.localMinFare;
const double roadFactor = 1.35;

// db/security-179: real per-model category + fuel-efficiency pricing, now
// that rides_screen.dart offers a vehicle picker instead of always booking
// as the sedan/2022 default. Mirrors guard_ride_fare()'s own category rate
// lookup and fuel-cost term exactly, so this preview never disagrees with
// what actually gets charged at insert.
double _localRatePerKm(String category) {
  switch (category) {
    case 'suv':
      return PricingSettings.localRateSuv;
    case 'van':
      return PricingSettings.localRateVan;
    default:
      return PricingSettings.localRateSedan;
  }
}

double _externalRatePerKmFor(String category) {
  switch (category) {
    case 'suv':
      return PricingSettings.externalRateSuv;
    case 'van':
      return PricingSettings.externalRateVan;
    default:
      return PricingSettings.externalRateSedan;
  }
}

/// fare_cost = (trip_km ÷ km_per_liter) × fuel_price_per_liter — zero when
/// no vehicle is chosen yet, matching guard_ride_fare()'s own null-model
/// fallback (no vehicle_model → no fuel term).
double _fuelCost(double km, double? kmPerLiter) {
  if (kmPerLiter == null || kmPerLiter <= 0) return 0;
  return (km / kmPerLiter) * PricingSettings.fuelPricePerLiter;
}

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
/// what the tiered meter actually runs on, same as the web. [qualityTier]
/// ('regular'/'ac', matching airport_fare.dart's qualityMultiplier) must be
/// applied in the exact same order as guard_ride_fare() does server-side
/// (db/security-55-local-ride-ac-tier.sql) — before the min-fare floor, not
/// after — or this preview would silently disagree with what the customer
/// actually gets charged at insert.
/// [surgeMultiplier] mirrors current_surge_multiplier() (db/security-62) —
/// >1.0 only when dynamic_pricing_enabled is on and live demand/driver-
/// supply crosses a threshold. Combined with the tier multiplier the exact
/// same way (both floor and raw fare use the combined factor) so surge
/// stacks on top of the tier price rather than replacing it.
int fareForDistance(
  double straightKm, {
  String? toArea,
  String qualityTier = 'regular',
  double surgeMultiplier = 1.0,
  // Defaults match the server's own fallback (no vehicle chosen yet) —
  // sedan rate, year-2022 multiplier, zero fuel cost.
  String category = 'sedan',
  int year = 2022,
  double? kmPerLiter,
}) {
  final roadKm = straightKm * roadFactor;
  final zone = _resolveZone(toArea);
  final effRate = _localRatePerKm(category) * _yearMultiplier(year); // _yearMultiplier(2022) == _defaultYearMult
  final mult = (qualityMultiplier[qualityTier] ?? 1.0) * surgeMultiplier;
  // Fuel cost is added the same place guard_ride_fare() adds it server-side
  // (after the zone multiplication, outside the quality-tier multiplier —
  // that tier bump is a client-only preview today, not yet enforced
  // server-side for local/external rides, so it was never part of the
  // fuel term either).
  final fuelCost = _fuelCost(roadKm, kmPerLiter);
  final raw = ((baseFare + _tieredKm(roadKm) * effRate) * zone.factor + zone.surcharge) * mult + fuelCost;
  // The floor has to scale by the same multiplier too, not just the raw
  // fare — otherwise a short trip (very common; base_fee/rate are low
  // enough that most short local trips land below minFare) floors to the
  // exact same number regardless of tier, and picking "مكيّفة"/"نظيفة"/
  // "موديل حديث" over "عادية" looks like it does nothing to the price.
  return (math.max(raw, minFare * mult) / 5).ceil() * 5;
}

int etaMinutes(double straightKm) {
  return ((straightKm * roadFactor) / 40 * 60).ceil(); // 40 km/h avg
}

// ─── رحلة خارجية (خارج محافظة دمياط) ────────────────────────────────────
// This screen has no destination-governorate picker (unlike rides-external.
// astro), so ride_type is inferred from road distance instead of an
// explicit choice — a trip that's ever plausibly local (anywhere realistic
// within Damietta governorate) stays well under this, and anything genuinely
// headed to another governorate (Cairo, Alexandria, ...) clears it easily.
// Ported from src/data/airports.ts's externalFare()/EXTERNAL_BASE_FARE/
// EXTERNAL_MIN_FARE — a flatter formula than the local meter (no distance
// tiers or destination zones, since "outside the governorate" is all one
// rate band).
const double externalThresholdKm = 40;

const double _yearMultBaseline = 2021;

double _yearMultiplier(int year) {
  final raw = 1 + (year - _yearMultBaseline) * 0.035;
  return raw.clamp(0.8, 1.35);
}

bool isExternalTrip(double roadKm) => roadKm > externalThresholdKm;

int externalFareForDistance(
  double roadKm, {
  String qualityTier = 'regular',
  double surgeMultiplier = 1.0,
  String category = 'sedan',
  int year = 2022,
  double? kmPerLiter,
}) {
  final rate = _externalRatePerKmFor(category) * _yearMultiplier(year);
  final mult = (qualityMultiplier[qualityTier] ?? 1.0) * surgeMultiplier;
  final fuelCost = _fuelCost(roadKm, kmPerLiter);
  final raw = (PricingSettings.externalBaseFee + roadKm * rate) * mult + fuelCost;
  return (math.max(raw, PricingSettings.externalMinFare * mult) / 5).ceil() * 5;
}
