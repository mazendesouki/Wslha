// Ported 1:1 from src/data/airports.ts — keep both in sync (also mirrored in
// db/rides-vehicle-pricing.sql per that file's own warning comments).

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

const double _suvMult = 1.3;
const double _vanMult = 1.4;

/// TRIP_RATES.airport — sedan/SUV/van per-km rate before the year adjustment.
double _airportRatePerKmBase(String category) {
  switch (category) {
    case 'suv':
      return (12 * _suvMult * 10).roundToDouble() / 10;
    case 'van':
      return (12 * _vanMult * 10).roundToDouble() / 10;
    default:
      return 12;
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

const int airportBaseFee = 300;

/// fareForVehicle() — base + distance × effective rate, rounded up to 50.
int fareForVehicle(double distanceKm, String category, int year) {
  final raw = airportBaseFee + distanceKm * airportRatePerKm(category, year);
  return (raw / 50).ceil() * 50;
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
