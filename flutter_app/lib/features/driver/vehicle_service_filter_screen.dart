import 'package:flutter/material.dart';
import '../../core/theme.dart';
import 'vehicle_service_shared.dart';

/// What VehicleServiceFilterScreen hands back when the driver taps
/// "تطبيق" — [serviceType] null means "كل الأنواع".
class VehicleServiceFilterResult {
  final String? serviceType;
  final int year;
  final int month;
  const VehicleServiceFilterResult({required this.serviceType, required this.year, required this.month});
}

const List<String> _filterArabicMonthNames = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

/// Dedicated filter screen (service type + year + month dropdowns, then
/// "تطبيق") for the monthly report — an alternative entry point to the
/// prev/next month arrows already on that screen.
class VehicleServiceFilterScreen extends StatefulWidget {
  final String? initialType;
  final int initialYear;
  final int initialMonth;
  const VehicleServiceFilterScreen({super.key, this.initialType, required this.initialYear, required this.initialMonth});

  @override
  State<VehicleServiceFilterScreen> createState() => _VehicleServiceFilterScreenState();
}

class _VehicleServiceFilterScreenState extends State<VehicleServiceFilterScreen> {
  late String? _type;
  late int _year;
  late int _month;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    _year = widget.initialYear;
    _month = widget.initialMonth;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final years = [for (var y = now.year; y >= now.year - 3; y--) y];

    return Scaffold(
      backgroundColor: context.mutedSurface,
      appBar: AppBar(title: const Text('تصفية السجل')),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('نوع الخدمة', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String?>(
                initialValue: _type,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem(value: null, child: Text('كل الأنواع')),
                  for (final e in vehicleServiceTypeLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _type = v),
              ),
              const SizedBox(height: 18),
              const Text('السنة', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              DropdownButtonFormField<int>(
                initialValue: _year,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: [for (final y in years) DropdownMenuItem(value: y, child: Text('$y'))],
                onChanged: (v) => setState(() => _year = v ?? _year),
              ),
              const SizedBox(height: 18),
              const Text('الشهر', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              DropdownButtonFormField<int>(
                initialValue: _month,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: [for (var m = 1; m <= 12; m++) DropdownMenuItem(value: m, child: Text(_filterArabicMonthNames[m - 1]))],
                onChanged: (v) => setState(() => _month = v ?? _month),
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(VehicleServiceFilterResult(serviceType: _type, year: _year, month: _month)),
                child: const Text('تطبيق'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
