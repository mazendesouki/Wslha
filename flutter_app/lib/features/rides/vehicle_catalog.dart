// Mirrors public.vehicle_rates (db/security-179-vehicle-model-fuel-pricing
// .sql) — same 29 models, same category, same km_per_liter. Keep both in
// sync the way airport_fare.dart's knownAirports mirrors
// src/data/airports.ts's AIRPORTS: this is reference data for the picker +
// client-side fare preview, not the source of truth — guard_ride_fare()
// re-derives the real charged fare server-side from whatever vehicle_model
// id actually gets sent.

class VehicleModel {
  final String id;
  final String name;
  final String category; // sedan | suv | van
  final double kmPerLiter;
  const VehicleModel({required this.id, required this.name, required this.category, required this.kmPerLiter});
}

const List<VehicleModel> vehicleCatalog = [
  // sedan
  VehicleModel(id: 'mg5', name: 'إم جي 5', category: 'sedan', kmPerLiter: 15.5),
  VehicleModel(id: 'bmw3', name: 'بي إم دبليو الفئة 3', category: 'sedan', kmPerLiter: 12.5),
  VehicleModel(id: 'peugeot301', name: 'بيجو 301', category: 'sedan', kmPerLiter: 16.0),
  VehicleModel(id: 'corolla', name: 'تويوتا كورولا', category: 'sedan', kmPerLiter: 16.5),
  VehicleModel(id: 'logan', name: 'رينو لوجان', category: 'sedan', kmPerLiter: 15.5),
  VehicleModel(id: 'octavia', name: 'سكودا أوكتافيا', category: 'sedan', kmPerLiter: 14.0),
  VehicleModel(id: 'optra', name: 'شيفروليه أوبترا', category: 'sedan', kmPerLiter: 13.5),
  VehicleModel(id: 'fiattipo', name: 'فيات تيبو', category: 'sedan', kmPerLiter: 15.0),
  VehicleModel(id: 'cerato', name: 'كيا سيراتو', category: 'sedan', kmPerLiter: 14.5),
  VehicleModel(id: 'mercc', name: 'مرسيدس الفئة C', category: 'sedan', kmPerLiter: 11.5),
  VehicleModel(id: 'sunny', name: 'نيسان صني', category: 'sedan', kmPerLiter: 16.0),
  VehicleModel(id: 'elantra', name: 'هيونداي إلنترا', category: 'sedan', kmPerLiter: 15.0),
  // suv
  VehicleModel(id: 'mgzs', name: 'إم جي ZS', category: 'suv', kmPerLiter: 13.0),
  VehicleModel(id: 'landcruiser', name: 'تويوتا لاند كروزر', category: 'suv', kmPerLiter: 6.5),
  VehicleModel(id: 'grandcherokee', name: 'جيب جراند شيروكي', category: 'suv', kmPerLiter: 8.0),
  VehicleModel(id: 'compass', name: 'جيب كومباس', category: 'suv', kmPerLiter: 11.0),
  VehicleModel(id: 'tiggo8', name: 'شيري تيجو 8', category: 'suv', kmPerLiter: 9.5),
  VehicleModel(id: 'sportage', name: 'كيا سبورتاج', category: 'suv', kmPerLiter: 11.5),
  VehicleModel(id: 'pajero', name: 'ميتسوبيشي باجيرو', category: 'suv', kmPerLiter: 8.5),
  VehicleModel(id: 'xtrail', name: 'نيسان إكس تريل', category: 'suv', kmPerLiter: 11.0),
  VehicleModel(id: 'patrol', name: 'نيسان باترول', category: 'suv', kmPerLiter: 6.0),
  VehicleModel(id: 'tucson', name: 'هيونداي توسان', category: 'suv', kmPerLiter: 11.5),
  VehicleModel(id: 'creta', name: 'هيونداي كريتا', category: 'suv', kmPerLiter: 13.5),
  // van
  VehicleModel(id: 'traveller', name: 'بيجو ترافيلر', category: 'van', kmPerLiter: 9.5),
  VehicleModel(id: 'hiace', name: 'تويوتا هاي إيس', category: 'van', kmPerLiter: 9.0),
  VehicleModel(id: 'carnival', name: 'كيا كارنيفال', category: 'van', kmPerLiter: 10.0),
  VehicleModel(id: 'sprinter', name: 'مرسيدس سبرينتر', category: 'van', kmPerLiter: 8.5),
  VehicleModel(id: 'xpander', name: 'ميتسوبيشي إكسباندر', category: 'van', kmPerLiter: 13.5),
  VehicleModel(id: 'h1', name: 'هيونداي H1', category: 'van', kmPerLiter: 9.5),
];

VehicleModel? vehicleById(String? id) {
  if (id == null) return null;
  for (final v in vehicleCatalog) {
    if (v.id == id) return v;
  }
  return null;
}

const Map<String, String> vehicleCategoryLabels = {
  'sedan': '🚗 سيدان',
  'suv': '🚙 SUV / كروز',
  'van': '🚐 ميكروباص',
};
