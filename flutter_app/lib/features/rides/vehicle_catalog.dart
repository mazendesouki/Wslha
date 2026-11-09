// A vehicle model available for the customer to pick when booking a local/
// external ride (db/security-180's get_available_vehicle_models()) — only
// models at least one currently-approved driver has actually registered,
// fetched live via RideRepository.fetchAvailableVehicleModels(). This file
// used to carry a static 29-model catalog mirroring public.vehicle_rates
// directly; that let a customer pick/price a car nobody on the road
// actually has, so the list is now always the real, live, driver-backed
// one instead.

class VehicleModel {
  final String id;
  final String name;
  final String category; // sedan | suv | van
  final double kmPerLiter;
  const VehicleModel({required this.id, required this.name, required this.category, required this.kmPerLiter});
}

const Map<String, String> vehicleCategoryLabels = {
  'sedan': '🚗 سيدان',
  'suv': '🚙 SUV / كروز',
  'van': '🚐 ميكروباص',
};

VehicleModel? findVehicleById(List<VehicleModel> models, String? id) {
  if (id == null) return null;
  for (final v in models) {
    if (v.id == id) return v;
  }
  return null;
}
