import 'dart:math' as math;

// Ported 1:1 from src/data/rides.ts.
const double baseFare = 25;
const double ratePerKm = 12;
const double roadFactor = 1.35;
const double minFare = 35;

double haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLng = (lng2 - lng1) * math.pi / 180;
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(lat1 * math.pi / 180) * math.cos(lat2 * math.pi / 180) * math.pow(math.sin(dLng / 2), 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

int fareForDistance(double straightKm) {
  final road = straightKm * roadFactor;
  final raw = baseFare + road * ratePerKm;
  return (math.max(raw, minFare) / 5).ceil() * 5;
}

int etaMinutes(double straightKm) {
  return ((straightKm * roadFactor) / 40 * 60).ceil(); // 40 km/h avg
}
