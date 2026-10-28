import '../../core/supabase_client.dart';

/// One log entry covering any kind of vehicle service — maintenance, fuel,
/// tire, oil, inspection, or a driver-defined "other" kind (customLabel).
/// Mirrors db/security-134/137's vehicle_service_logs row shape.
class VehicleServiceLog {
  final String id;
  final String serviceType;
  final String? customLabel;
  final double? cost;
  final double? odometerKm;
  final double? fuelLiters;
  final double? pricePerLiter;
  final String? notes;
  final DateTime performedAt;

  VehicleServiceLog({
    required this.id,
    required this.serviceType,
    this.customLabel,
    this.cost,
    this.odometerKm,
    this.fuelLiters,
    this.pricePerLiter,
    this.notes,
    required this.performedAt,
  });

  factory VehicleServiceLog.fromRow(Map<String, dynamic> r) => VehicleServiceLog(
        id: r['id'].toString(),
        serviceType: r['service_type'] as String,
        customLabel: r['custom_label'] as String?,
        cost: (r['cost'] as num?)?.toDouble(),
        odometerKm: (r['odometer_km'] as num?)?.toDouble(),
        fuelLiters: (r['fuel_liters'] as num?)?.toDouble(),
        pricePerLiter: (r['price_per_liter'] as num?)?.toDouble(),
        notes: r['notes'] as String?,
        performedAt: DateTime.parse(r['performed_at'] as String),
      );
}

/// "خدمات المركبات" — db/security-134/137-vehicle-service-logs.sql. A
/// driver's own service history/file (item 6), covering maintenance/fuel/
/// tire/oil/inspection logging (items 1-5) plus a driver-defined "other"
/// kind (item 7's "add further services"), editing existing entries, and
/// a per-driver fuel tank capacity used for the consumption summary.
class VehicleServiceRepository {
  Future<List<VehicleServiceLog>> listMine(String driverPhone, {String? serviceType}) async {
    final rows = await sb.rpc('list_my_vehicle_service_logs', params: {
      'p_driver_phone': driverPhone,
      'p_service_type': serviceType,
    });
    return (rows as List).map((r) => VehicleServiceLog.fromRow(r as Map<String, dynamic>)).toList();
  }

  /// Returns an error message on failure, null on success — same
  /// convention as DriverRepository.submitPriceOffer. When [pricePerLiter]
  /// and [fuelLiters] are both given and [cost] is left null, the server
  /// computes cost = pricePerLiter * fuelLiters.
  Future<String?> logService({
    required String driverPhone,
    required String serviceType,
    String? customLabel,
    double? cost,
    double? odometerKm,
    double? fuelLiters,
    double? pricePerLiter,
    String? notes,
    DateTime? performedAt,
  }) async {
    try {
      await sb.rpc('log_vehicle_service', params: {
        'p_driver_phone': driverPhone,
        'p_service_type': serviceType,
        'p_custom_label': customLabel,
        'p_cost': cost,
        'p_odometer_km': odometerKm,
        'p_fuel_liters': fuelLiters,
        'p_price_per_liter': pricePerLiter,
        'p_notes': notes,
        'p_performed_at': (performedAt ?? DateTime.now()).toIso8601String(),
      });
      return null;
    } catch (e) {
      return 'تعذّر حفظ السجل، حاول مرة أخرى.';
    }
  }

  /// Same shape/contract as [logService], but edits an existing entry the
  /// driver already owns instead of creating a new one.
  Future<String?> updateLog({
    required String driverPhone,
    required String logId,
    required String serviceType,
    String? customLabel,
    double? cost,
    double? odometerKm,
    double? fuelLiters,
    double? pricePerLiter,
    String? notes,
    DateTime? performedAt,
  }) async {
    try {
      await sb.rpc('update_vehicle_service_log', params: {
        'p_driver_phone': driverPhone,
        'p_log_id': logId,
        'p_service_type': serviceType,
        'p_custom_label': customLabel,
        'p_cost': cost,
        'p_odometer_km': odometerKm,
        'p_fuel_liters': fuelLiters,
        'p_price_per_liter': pricePerLiter,
        'p_notes': notes,
        'p_performed_at': (performedAt ?? DateTime.now()).toIso8601String(),
      });
      return null;
    } catch (e) {
      return 'تعذّر حفظ التعديل، حاول مرة أخرى.';
    }
  }

  Future<bool> deleteLog(String driverPhone, String logId) async {
    try {
      final ok = await sb.rpc('delete_my_vehicle_service_log', params: {
        'p_driver_phone': driverPhone,
        'p_log_id': logId,
      });
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  Future<double?> getFuelTankCapacity(String driverPhone) async {
    try {
      final v = await sb.rpc('get_my_fuel_tank_capacity', params: {'p_driver_phone': driverPhone});
      return (v as num?)?.toDouble();
    } catch (_) {
      return null;
    }
  }

  Future<bool> setFuelTankCapacity(String driverPhone, double capacityLiters) async {
    try {
      final ok = await sb.rpc('set_my_fuel_tank_capacity', params: {
        'p_driver_phone': driverPhone,
        'p_capacity_liters': capacityLiters,
      });
      return ok == true;
    } catch (_) {
      return false;
    }
  }
}
