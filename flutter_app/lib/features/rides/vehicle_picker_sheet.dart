import 'package:flutter/material.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../shared/widgets/selectable_pill.dart';
import 'vehicle_catalog.dart';

class VehiclePickerResult {
  final String modelId;
  final int year;
  const VehiclePickerResult(this.modelId, this.year);
}

const int _minVehicleYear = 2015;
const List<String> _categoryOrder = ['sedan', 'suv', 'van'];

/// Opens the car picker (db/security-180) — only models at least one
/// approved driver actually has registered, grouped by category, each
/// showing its own live fare ([fareFor], which the caller closes over its
/// own distance/zone/quality-tier/surge state so this sheet never has to
/// re-implement fare_calculator.dart's formula). Returns null if dismissed
/// without confirming, or if [models] is empty (nothing to pick).
Future<VehiclePickerResult?> showVehiclePickerSheet(
  BuildContext context, {
  required List<VehicleModel> models,
  required String? initialModelId,
  required int initialYear,
  required int Function(VehicleModel model, int year) fareFor,
}) {
  return showModalBottomSheet<VehiclePickerResult>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (sheetContext) => _VehiclePickerSheet(
      models: models,
      initialModelId: initialModelId,
      initialYear: initialYear,
      fareFor: fareFor,
    ),
  );
}

class _VehiclePickerSheet extends StatefulWidget {
  final List<VehicleModel> models;
  final String? initialModelId;
  final int initialYear;
  final int Function(VehicleModel model, int year) fareFor;
  const _VehiclePickerSheet({required this.models, required this.initialModelId, required this.initialYear, required this.fareFor});

  @override
  State<_VehiclePickerSheet> createState() => _VehiclePickerSheetState();
}

class _VehiclePickerSheetState extends State<_VehiclePickerSheet> {
  late String _category;
  late String? _modelId;
  late int _year;

  List<String> get _availableCategories => _categoryOrder.where((c) => widget.models.any((v) => v.category == c)).toList();

  @override
  void initState() {
    super.initState();
    _modelId = widget.initialModelId;
    _year = widget.initialYear;
    final selected = findVehicleById(widget.models, _modelId);
    final categories = _availableCategories;
    _category = selected?.category ?? (categories.isNotEmpty ? categories.first : 'sedan');
  }

  @override
  Widget build(BuildContext context) {
    if (widget.models.isEmpty) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.tr('rides_vehicle_none_available'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(context.tr('rides_vehicle_empty_state'), style: TextStyle(fontSize: 12.5, color: AppColors.textFaint, height: 1.4), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.tr('rides_vehicle_picker_done'))),
              ),
            ],
          ),
        ),
      );
    }

    final models = widget.models.where((v) => v.category == _category).toList();
    final maxYear = DateTime.now().year;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Text(context.tr('rides_vehicle_picker_title'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Wrap(
                spacing: 6,
                children: [
                  for (final cat in _availableCategories)
                    SelectablePill(
                      label: vehicleCategoryLabels[cat]!,
                      selected: _category == cat,
                      onTap: () => setState(() => _category = cat),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text('${context.tr('rides_vehicle_year_label')}: $_year', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: _year > _minVehicleYear ? () => setState(() => _year--) : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: _year < maxYear ? () => setState(() => _year++) : null,
                  ),
                ],
              ),
            ),
            const Divider(height: 20),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.45),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: models.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final model = models[i];
                  final selected = model.id == _modelId;
                  final fare = widget.fareFor(model, _year);
                  return ListTile(
                    onTap: () => setState(() => _modelId = model.id),
                    leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: selected ? AppColors.primary : context.borderColor),
                    title: Text(model.name, style: TextStyle(fontWeight: selected ? FontWeight.w900 : FontWeight.w600, fontSize: 13.5)),
                    trailing: Text('$fare ج.م', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, color: selected ? AppColors.primary : context.bodyText)),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _modelId == null ? null : () => Navigator.of(context).pop(VehiclePickerResult(_modelId!, _year)),
                  child: Text(context.tr('rides_vehicle_picker_done')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
