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
  final double? quantity;
  final double? unitPrice;
  final List<String>? maintenanceItems;
  final String? serviceCenter;
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
    this.quantity,
    this.unitPrice,
    this.maintenanceItems,
    this.serviceCenter,
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
        quantity: (r['quantity'] as num?)?.toDouble(),
        unitPrice: (r['unit_price'] as num?)?.toDouble(),
        maintenanceItems: (r['maintenance_items'] as List?)?.map((e) => e.toString()).toList(),
        serviceCenter: r['service_center'] as String?,
        notes: r['notes'] as String?,
        performedAt: DateTime.parse(r['performed_at'] as String),
      );
}

/// One row of db/security-151's get_my_vehicle_service_monthly_totals —
/// per-service-type cost/count subtotal for a single month.
class VehicleServiceMonthlyTotal {
  final String serviceType;
  final int entriesCount;
  final double totalCost;

  VehicleServiceMonthlyTotal({required this.serviceType, required this.entriesCount, required this.totalCost});

  factory VehicleServiceMonthlyTotal.fromRow(Map<String, dynamic> r) => VehicleServiceMonthlyTotal(
        serviceType: r['service_type'] as String,
        entriesCount: (r['entries_count'] as num).toInt(),
        totalCost: (r['total_cost'] as num?)?.toDouble() ?? 0,
      );
}

/// One row of db/security-151's get_my_vehicle_service_summary — a
/// lifetime rollup per distinct "service" (a specific maintenance catalog
/// item, a service type like fuel/oil/tire/inspection, or a custom "other"
/// label): how many times it was done, total spent, and when it was last
/// done. itemKey/serviceType/customLabel come back raw (no ready-made
/// label) so the UI can reuse the same label maps it already has.
class VehicleServiceSummaryRow {
  final String serviceType;
  final String? maintenanceItemKey;
  final String? customLabel;
  final int entriesCount;
  final double totalCost;
  final DateTime lastPerformedAt;

  VehicleServiceSummaryRow({
    required this.serviceType,
    this.maintenanceItemKey,
    this.customLabel,
    required this.entriesCount,
    required this.totalCost,
    required this.lastPerformedAt,
  });

  factory VehicleServiceSummaryRow.fromRow(Map<String, dynamic> r) => VehicleServiceSummaryRow(
        serviceType: r['service_type'] as String,
        maintenanceItemKey: r['maintenance_item_key'] as String?,
        customLabel: r['custom_label'] as String?,
        entriesCount: (r['entries_count'] as num).toInt(),
        totalCost: (r['total_cost'] as num?)?.toDouble() ?? 0,
        lastPerformedAt: DateTime.parse(r['last_performed_at'] as String),
      );
}

/// One standard periodic-maintenance item — db/security-142's
/// maintenance_catalog_items, admin-editable from the dashboard.
class MaintenanceCatalogItem {
  final String itemKey;
  final String labelAr;
  final String importance; // 'critical' | 'important'
  final double? intervalKm;

  MaintenanceCatalogItem({required this.itemKey, required this.labelAr, required this.importance, this.intervalKm});

  factory MaintenanceCatalogItem.fromRow(Map<String, dynamic> r) => MaintenanceCatalogItem(
        itemKey: r['item_key'] as String,
        labelAr: r['label_ar'] as String,
        importance: r['importance'] as String,
        intervalKm: (r['interval_km'] as num?)?.toDouble(),
      );
}

/// Due/overdue status for one catalog item, computed server-side from the
/// driver's own maintenance history + latest logged odometer reading.
class MaintenanceDueStatus {
  final String itemKey;
  final String labelAr;
  final String importance;
  final double? intervalKm;
  final double? kmSince;
  final String status; // 'overdue' | 'due_soon' | 'ok' | 'never_done'

  MaintenanceDueStatus({
    required this.itemKey,
    required this.labelAr,
    required this.importance,
    this.intervalKm,
    this.kmSince,
    required this.status,
  });

  factory MaintenanceDueStatus.fromRow(Map<String, dynamic> r) => MaintenanceDueStatus(
        itemKey: r['item_key'] as String,
        labelAr: r['label_ar'] as String,
        importance: r['importance'] as String,
        intervalKm: (r['interval_km'] as num?)?.toDouble(),
        kmSince: (r['km_since'] as num?)?.toDouble(),
        status: r['status'] as String,
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
  /// convention as DriverRepository.submitPriceOffer. When [cost] is left
  /// null, the server computes it: pricePerLiter * fuelLiters (fuel), else
  /// quantity * unitPrice (oil: liters, tire: count).
  Future<String?> logService({
    required String driverPhone,
    required String serviceType,
    String? customLabel,
    double? cost,
    double? odometerKm,
    double? fuelLiters,
    double? pricePerLiter,
    double? quantity,
    double? unitPrice,
    List<String>? maintenanceItems,
    String? serviceCenter,
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
        'p_quantity': quantity,
        'p_unit_price': unitPrice,
        'p_maintenance_items': maintenanceItems,
        'p_service_center': serviceCenter,
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
    double? quantity,
    double? unitPrice,
    List<String>? maintenanceItems,
    String? serviceCenter,
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
        'p_quantity': quantity,
        'p_unit_price': unitPrice,
        'p_maintenance_items': maintenanceItems,
        'p_service_center': serviceCenter,
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

  Future<List<MaintenanceCatalogItem>> listMaintenanceCatalog() async {
    try {
      final rows = await sb.rpc('list_maintenance_catalog');
      return (rows as List).map((r) => MaintenanceCatalogItem.fromRow(r as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<MaintenanceDueStatus>> getMaintenanceDueStatus(String driverPhone) async {
    try {
      final rows = await sb.rpc('get_maintenance_due_status', params: {'p_driver_phone': driverPhone});
      return (rows as List).map((r) => MaintenanceDueStatus.fromRow(r as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  /// All of a driver's entries for one calendar month — db/security-151's
  /// monthly report RPC. [month] is 1-12.
  Future<List<VehicleServiceLog>> listMonthlyReport(String driverPhone, int year, int month) async {
    final rows = await sb.rpc('get_my_vehicle_service_monthly_report', params: {
      'p_driver_phone': driverPhone,
      'p_year': year,
      'p_month': month,
    });
    return (rows as List).map((r) => VehicleServiceLog.fromRow(r as Map<String, dynamic>)).toList();
  }

  /// Per-service-type cost/count subtotal for one calendar month — the UI
  /// sums these for the month's grand total.
  Future<List<VehicleServiceMonthlyTotal>> getMonthlyTotals(String driverPhone, int year, int month) async {
    final rows = await sb.rpc('get_my_vehicle_service_monthly_totals', params: {
      'p_driver_phone': driverPhone,
      'p_year': year,
      'p_month': month,
    });
    return (rows as List).map((r) => VehicleServiceMonthlyTotal.fromRow(r as Map<String, dynamic>)).toList();
  }

  /// Lifetime per-service rollup (frequency, total cost, last performed
  /// date) — not limited to one month, covers the vehicle's whole history.
  Future<List<VehicleServiceSummaryRow>> getServiceSummary(String driverPhone) async {
    final rows = await sb.rpc('get_my_vehicle_service_summary', params: {'p_driver_phone': driverPhone});
    return (rows as List).map((r) => VehicleServiceSummaryRow.fromRow(r as Map<String, dynamic>)).toList();
  }
}
