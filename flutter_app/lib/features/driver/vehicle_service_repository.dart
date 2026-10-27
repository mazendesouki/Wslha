import '../../core/supabase_client.dart';

/// One log entry covering any kind of vehicle service — maintenance, fuel,
/// tire, oil, inspection, or a driver-defined "other" kind (customLabel).
/// Mirrors db/security-134-vehicle-service-logs.sql's vehicle_service_logs
/// row shape.
class VehicleServiceLog {
  final String id;
  final String serviceType;
  final String? customLabel;
  final double? cost;
  final double? odometerKm;
  final double? fuelLiters;
  final String? notes;
  final DateTime performedAt;

  VehicleServiceLog({
    required this.id,
    required this.serviceType,
    this.customLabel,
    this.cost,
    this.odometerKm,
    this.fuelLiters,
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
        notes: r['notes'] as String?,
        performedAt: DateTime.parse(r['performed_at'] as String),
      );
}

/// "خدمات المركبات" — db/security-134-vehicle-service-logs.sql. A driver's
/// own service history/file (item 6), covering maintenance/fuel/tire/oil/
/// inspection logging (items 1-5) plus a driver-defined "other" kind
/// (item 7's "add further services").
class VehicleServiceRepository {
  Future<List<VehicleServiceLog>> listMine(String driverPhone, {String? serviceType}) async {
    final rows = await sb.rpc('list_my_vehicle_service_logs', params: {
      'p_driver_phone': driverPhone,
      'p_service_type': serviceType,
    });
    return (rows as List).map((r) => VehicleServiceLog.fromRow(r as Map<String, dynamic>)).toList();
  }

  /// Returns an error message on failure, null on success — same
  /// convention as DriverRepository.submitPriceOffer.
  Future<String?> logService({
    required String driverPhone,
    required String serviceType,
    String? customLabel,
    double? cost,
    double? odometerKm,
    double? fuelLiters,
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
        'p_notes': notes,
        'p_performed_at': (performedAt ?? DateTime.now()).toIso8601String(),
      });
      return null;
    } catch (e) {
      return 'تعذّر حفظ السجل، حاول مرة أخرى.';
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
}
