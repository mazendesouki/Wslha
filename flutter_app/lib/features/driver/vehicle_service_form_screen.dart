import 'package:flutter/material.dart';
import '../../core/theme.dart';
import 'vehicle_service_confirmation_screen.dart';
import 'vehicle_service_repository.dart';
import 'vehicle_service_shared.dart';

/// Step 2 of the "سجّل عملية" flow — a dedicated full-page form per
/// service type (not a shared bottom sheet). Handles both creating a new
/// entry (initialType fixed by the type-selection screen) and editing an
/// existing one (existingLog provided, type switchable as before).
///
/// On a successful NEW entry, this screen is replaced by
/// VehicleServiceConfirmationScreen (step 3) rather than just popping —
/// an edit just pops back to wherever it was opened from, since editing
/// isn't the "new entry" flow the confirmation screen celebrates.
class VehicleServiceFormScreen extends StatefulWidget {
  final VehicleServiceRepository repo;
  final String driverPhone;
  final String? initialType;
  final VehicleServiceLog? existingLog;
  const VehicleServiceFormScreen({super.key, required this.repo, required this.driverPhone, this.initialType, this.existingLog});

  @override
  State<VehicleServiceFormScreen> createState() => _VehicleServiceFormScreenState();
}

class _VehicleServiceFormScreenState extends State<VehicleServiceFormScreen> {
  late String _type;
  late final TextEditingController _customLabelCtrl;
  late final TextEditingController _costCtrl;
  late final TextEditingController _odometerCtrl;
  late final TextEditingController _fuelLitersCtrl;
  late final TextEditingController _pricePerLiterCtrl;
  late final TextEditingController _quantityCtrl;
  late final TextEditingController _unitPriceCtrl;
  late final TextEditingController _laborCostCtrl;
  late final TextEditingController _filterCostCtrl;
  late final TextEditingController _serviceCenterCtrl;
  late final TextEditingController _notesCtrl;
  late DateTime _date;
  bool _submitting = false;
  bool _changedFilterToo = false;
  String? _error;
  late Future<List<MaintenanceCatalogItem>> _catalogFuture;
  String? _selectedMaintenanceItem;

  bool get _editing => widget.existingLog != null;

  @override
  void initState() {
    super.initState();
    final log = widget.existingLog;
    _type = log?.serviceType ?? widget.initialType ?? 'maintenance';
    _customLabelCtrl = TextEditingController(text: log?.customLabel ?? '');
    _costCtrl = TextEditingController(text: log?.cost?.toStringAsFixed(2) ?? '');
    _odometerCtrl = TextEditingController(text: log?.odometerKm?.toStringAsFixed(0) ?? '');
    _fuelLitersCtrl = TextEditingController(text: log?.fuelLiters?.toStringAsFixed(1) ?? '');
    _pricePerLiterCtrl = TextEditingController(text: log?.pricePerLiter?.toStringAsFixed(2) ?? '');
    _quantityCtrl = TextEditingController(text: formatVehicleServiceQuantity(log?.quantity));
    _unitPriceCtrl = TextEditingController(text: log?.unitPrice?.toStringAsFixed(2) ?? '');
    _laborCostCtrl = TextEditingController();
    _filterCostCtrl = TextEditingController();
    _serviceCenterCtrl = TextEditingController(text: log?.serviceCenter ?? '');
    _notesCtrl = TextEditingController(text: log?.notes ?? '');
    _date = log?.performedAt ?? DateTime.now();
    _selectedMaintenanceItem = (log?.maintenanceItems?.isNotEmpty ?? false) ? log!.maintenanceItems!.first : null;
    _catalogFuture = widget.repo.listMaintenanceCatalog();
    for (final c in [_fuelLitersCtrl, _pricePerLiterCtrl, _quantityCtrl, _unitPriceCtrl, _laborCostCtrl, _filterCostCtrl]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _customLabelCtrl.dispose();
    _costCtrl.dispose();
    _odometerCtrl.dispose();
    _fuelLitersCtrl.dispose();
    _pricePerLiterCtrl.dispose();
    _quantityCtrl.dispose();
    _unitPriceCtrl.dispose();
    _laborCostCtrl.dispose();
    _filterCostCtrl.dispose();
    _serviceCenterCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  double? get _computedFuelTotal {
    final price = double.tryParse(_pricePerLiterCtrl.text.trim());
    final liters = double.tryParse(_fuelLitersCtrl.text.trim());
    if (price == null || liters == null) return null;
    return price * liters;
  }

  double? get _computedQuantityTotal {
    final price = double.tryParse(_unitPriceCtrl.text.trim());
    final qty = double.tryParse(_quantityCtrl.text.trim());
    if (price == null || qty == null) return null;
    return price * qty;
  }

  /// For 'oil' specifically: base oil cost + labor cost (filter cost is
  /// excluded — it's saved as its own separate maintenance entry so it
  /// correctly feeds the oil_filter due-tracking, same one-entry-per-item
  /// rule the rest of the screen already follows).
  double? get _computedOilPrimaryTotal {
    final base = _computedQuantityTotal;
    final labor = double.tryParse(_laborCostCtrl.text.trim()) ?? 0;
    if (base == null) return null;
    return base + labor;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 3)),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (_type == 'other' && _customLabelCtrl.text.trim().isEmpty) {
      setState(() => _error = 'اكتب اسم الخدمة');
      return;
    }
    if (_type == 'maintenance' && _selectedMaintenanceItem == null) {
      setState(() => _error = 'اختار العنصر اللي تمت صيانته');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });

    final isFuel = _type == 'fuel';
    final isOil = _type == 'oil';
    final quantityConfig = vehicleServiceQuantityUnitConfigs[_type];
    final usesFlatCost = !isFuel && quantityConfig == null;
    final odometer = double.tryParse(_odometerCtrl.text.trim());
    final serviceCenter = _serviceCenterCtrl.text.trim().isEmpty ? null : _serviceCenterCtrl.text.trim();
    final notes = _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();

    final String? error;
    if (_editing) {
      error = await widget.repo.updateLog(
        driverPhone: widget.driverPhone,
        logId: widget.existingLog!.id,
        serviceType: _type,
        customLabel: _type == 'other' ? _customLabelCtrl.text.trim() : null,
        cost: usesFlatCost
            ? double.tryParse(_costCtrl.text.trim())
            : (isOil ? _computedOilPrimaryTotal ?? double.tryParse(_costCtrl.text.trim()) : null),
        odometerKm: odometer,
        fuelLiters: isFuel ? double.tryParse(_fuelLitersCtrl.text.trim()) : null,
        pricePerLiter: isFuel ? double.tryParse(_pricePerLiterCtrl.text.trim()) : null,
        quantity: quantityConfig != null ? double.tryParse(_quantityCtrl.text.trim()) : null,
        unitPrice: quantityConfig != null ? double.tryParse(_unitPriceCtrl.text.trim()) : null,
        maintenanceItems: _type == 'maintenance' && _selectedMaintenanceItem != null ? [_selectedMaintenanceItem!] : null,
        serviceCenter: serviceCenter,
        notes: notes,
        performedAt: _date,
      );
    } else {
      error = await widget.repo.logService(
        driverPhone: widget.driverPhone,
        serviceType: _type,
        customLabel: _type == 'other' ? _customLabelCtrl.text.trim() : null,
        cost: usesFlatCost
            ? double.tryParse(_costCtrl.text.trim())
            : (isOil ? _computedOilPrimaryTotal ?? double.tryParse(_costCtrl.text.trim()) : null),
        odometerKm: odometer,
        fuelLiters: isFuel ? double.tryParse(_fuelLitersCtrl.text.trim()) : null,
        pricePerLiter: isFuel ? double.tryParse(_pricePerLiterCtrl.text.trim()) : null,
        quantity: quantityConfig != null ? double.tryParse(_quantityCtrl.text.trim()) : null,
        unitPrice: quantityConfig != null ? double.tryParse(_unitPriceCtrl.text.trim()) : null,
        maintenanceItems: _type == 'maintenance' && _selectedMaintenanceItem != null ? [_selectedMaintenanceItem!] : null,
        serviceCenter: serviceCenter,
        notes: notes,
        performedAt: _date,
      );

      // Bundled "also changed the oil filter" — rather than cramming a
      // second item into the oil row (the DB/due-tracking model is one
      // maintenance item per entry, deliberately, per the earlier driver
      // feedback this screen already follows), silently log a SECOND,
      // genuine maintenance entry for oil_filter so it correctly feeds
      // get_maintenance_due_status — same date/odometer/service center,
      // its own cost.
      if (error == null && isOil && _changedFilterToo) {
        final filterCost = double.tryParse(_filterCostCtrl.text.trim());
        await widget.repo.logService(
          driverPhone: widget.driverPhone,
          serviceType: 'maintenance',
          odometerKm: odometer,
          maintenanceItems: const ['oil_filter'],
          cost: filterCost,
          serviceCenter: serviceCenter,
          notes: 'اتسجّل تلقائيًا مع تغيير الزيت',
          performedAt: _date,
        );
      }
    }

    if (!mounted) return;
    if (error != null) {
      setState(() {
        _submitting = false;
        _error = error;
      });
      return;
    }

    if (_editing) {
      Navigator.of(context).pop(true);
      return;
    }

    final totalCost = usesFlatCost
        ? double.tryParse(_costCtrl.text.trim())
        : (isFuel ? _computedFuelTotal : (isOil ? _computedOilPrimaryTotal : _computedQuantityTotal));
    final filterCost = isOil && _changedFilterToo ? double.tryParse(_filterCostCtrl.text.trim()) : null;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => VehicleServiceConfirmationScreen(
          repo: widget.repo,
          driverPhone: widget.driverPhone,
          serviceType: _type,
          maintenanceItemKey: _type == 'maintenance' ? _selectedMaintenanceItem : null,
          customLabel: _type == 'other' ? _customLabelCtrl.text.trim() : null,
          cost: (totalCost ?? 0) + (filterCost ?? 0),
          serviceCenter: serviceCenter,
          performedAt: _date,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _date;
    final dateStr = '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
    final isFuel = _type == 'fuel';
    final isOil = _type == 'oil';
    final quantityConfig = vehicleServiceQuantityUnitConfigs[_type];
    final computedTotal = isFuel
        ? _computedFuelTotal
        : (isOil ? _computedOilPrimaryTotal : (quantityConfig != null ? _computedQuantityTotal : null));

    return Scaffold(
      backgroundColor: context.mutedSurface,
      appBar: AppBar(title: Text(_editing ? '✏️ تعديل العملية' : vehicleServiceTypeLabels[_type] ?? 'نموذج الخدمة')),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
                ),
                const SizedBox(height: 12),
              ],
              if (_editing) ...[
                // Editing can still switch the type (matches the old
                // sheet's behavior) — a new entry's type is fixed by
                // whichever card was tapped on the selection screen.
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in vehicleServiceTypeLabels.entries)
                      ChoiceChip(
                        label: Text(e.value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _type == e.key ? Colors.white : null)),
                        selected: _type == e.key,
                        selectedColor: AppColors.primary,
                        onSelected: (_) => setState(() => _type = e.key),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
              ],
              if (_type == 'other') ...[
                TextField(controller: _customLabelCtrl, decoration: const InputDecoration(labelText: 'اسم الخدمة')),
                const SizedBox(height: 10),
              ],
              if (isFuel) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _pricePerLiterCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'سعر اللتر (ج.م)'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _fuelLitersCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'عدد اللترات'),
                      ),
                    ),
                  ],
                ),
                if (computedTotal != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(8)),
                    child: Text('💰 الإجمالي: ${computedTotal.toStringAsFixed(2)} ج.م', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  ),
                ],
                const SizedBox(height: 10),
                TextField(
                  controller: _odometerCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'عداد الكيلومترات'),
                ),
                VehicleServiceGuidanceCard(guidance: vehicleServiceTypeGuidance['fuel']!),
              ] else if (isOil) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _unitPriceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(labelText: quantityConfig!.unitPriceLabel),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _quantityCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(labelText: quantityConfig.quantityLabel),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _laborCostCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'أجرة العمل (ج.م، اختياري)'),
                ),
                if (!_editing) ...[
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _changedFilterToo,
                    onChanged: (v) => setState(() => _changedFilterToo = v),
                    title: const Text('تم تغيير فلتر الزيت أيضًا', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    activeTrackColor: AppColors.primary,
                  ),
                  if (_changedFilterToo) ...[
                    TextField(
                      controller: _filterCostCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'تكلفة الفلتر (ج.م)'),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
                if (computedTotal != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      '💰 الإجمالي: ${(computedTotal + (_changedFilterToo ? (double.tryParse(_filterCostCtrl.text.trim()) ?? 0) : 0)).toStringAsFixed(2)} ج.م',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                TextField(
                  controller: _odometerCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'عداد الكيلومترات'),
                ),
                VehicleServiceGuidanceCard(guidance: vehicleServiceTypeGuidance['oil']!),
              ] else if (quantityConfig != null) ...[
                // Same calculation pattern as fuel (price_per_liter ×
                // fuel_liters) but with a generic quantity/unit_price pair
                // — tire: count. See db/security-140.
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _unitPriceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(labelText: quantityConfig.unitPriceLabel),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _quantityCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(labelText: quantityConfig.quantityLabel),
                      ),
                    ),
                  ],
                ),
                if (computedTotal != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(8)),
                    child: Text('💰 الإجمالي: ${computedTotal.toStringAsFixed(2)} ج.م', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  ),
                ],
                const SizedBox(height: 10),
                TextField(
                  controller: _odometerCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'عداد الكيلومترات'),
                ),
                VehicleServiceGuidanceCard(guidance: vehicleServiceTypeGuidance[_type]!),
              ] else if (_type == 'maintenance') ...[
                // Pick EXACTLY ONE catalog item per log entry — a visit
                // covering several items gets logged as several entries,
                // each with its own real cost.
                const Text('العنصر اللي تمت صيانته', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                FutureBuilder<List<MaintenanceCatalogItem>>(
                  future: _catalogFuture,
                  builder: (context, snap) {
                    final items = snap.data ?? const [];
                    if (items.isEmpty) return const SizedBox.shrink();
                    MaintenanceCatalogItem? selectedCatalogItem;
                    for (final item in items) {
                      if (item.itemKey == _selectedMaintenanceItem) selectedCatalogItem = item;
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final item in items)
                              ChoiceChip(
                                label: Text(item.labelAr, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _selectedMaintenanceItem == item.itemKey ? Colors.white : null)),
                                selected: _selectedMaintenanceItem == item.itemKey,
                                selectedColor: AppColors.primary,
                                onSelected: (_) => setState(() => _selectedMaintenanceItem = item.itemKey),
                              ),
                          ],
                        ),
                        if (selectedCatalogItem != null && vehicleMaintenanceItemGuidance[selectedCatalogItem.itemKey] != null)
                          VehicleServiceGuidanceCard(
                            guidance: vehicleMaintenanceItemGuidance[selectedCatalogItem.itemKey]!,
                            importance: selectedCatalogItem.importance,
                            intervalText: selectedCatalogItem.intervalKm != null
                                ? 'كل ${selectedCatalogItem.intervalKm!.toStringAsFixed(0)} كم'
                                : null,
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _costCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'التكلفة (ج.م)'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _odometerCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'عداد الكيلومترات'),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _costCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'التكلفة (ج.م)'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _odometerCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'عداد الكيلومترات'),
                      ),
                    ),
                  ],
                ),
                if (vehicleServiceTypeGuidance[_type] != null) VehicleServiceGuidanceCard(guidance: vehicleServiceTypeGuidance[_type]!),
              ],
              const SizedBox(height: 10),
              TextField(controller: _serviceCenterCtrl, decoration: const InputDecoration(labelText: 'مركز/ورشة الصيانة (اختياري)')),
              const SizedBox(height: 10),
              TextField(controller: _notesCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)')),
              const SizedBox(height: 10),
              InkWell(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(border: Border.all(color: context.borderColor), borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 16, color: AppColors.textFaint),
                      const SizedBox(width: 8),
                      Text('تاريخ العملية: $dateStr', style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_editing ? 'حفظ التعديل' : 'حفظ'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
