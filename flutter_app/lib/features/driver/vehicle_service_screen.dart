import 'package:flutter/material.dart';
import '../../core/theme.dart';
import 'vehicle_service_repository.dart';

const Map<String, String> _serviceTypeLabels = {
  'maintenance': '🛠️ صيانة دورية',
  'fuel': '⛽ وقود',
  'tire': '🛞 كاوتش',
  'oil': '🛢️ زيت',
  'inspection': '🔍 فحص المحرك',
  'other': '➕ خدمة تانية',
};

/// "خدمات المركبات" — سجل/ملف صيانة العربية: صيانة دورية، وقود (سعر
/// اللتر + معدل الاستهلاك محسوب تلقائيًا)، كاوتش، زيت، فحص المحرك، وأي
/// خدمة تانية السائق يحددها بنفسه. See db/security-134/137.
class VehicleServiceScreen extends StatefulWidget {
  final String driverPhone;
  const VehicleServiceScreen({super.key, required this.driverPhone});

  @override
  State<VehicleServiceScreen> createState() => _VehicleServiceScreenState();
}

class _VehicleServiceScreenState extends State<VehicleServiceScreen> {
  final _repo = VehicleServiceRepository();
  late Future<List<VehicleServiceLog>> _future;
  late Future<List<VehicleServiceLog>> _fuelFuture;
  double? _tankCapacity;
  String? _filter;

  @override
  void initState() {
    super.initState();
    _load();
    _loadFuelSummary();
    _repo.getFuelTankCapacity(widget.driverPhone).then((v) {
      if (mounted) setState(() => _tankCapacity = v);
    });
  }

  void _load() {
    _future = _repo.listMine(widget.driverPhone, serviceType: _filter);
  }

  void _loadFuelSummary() {
    _fuelFuture = _repo.listMine(widget.driverPhone, serviceType: 'fuel');
  }

  Future<void> _refresh() async {
    setState(() {
      _load();
      _loadFuelSummary();
    });
    await Future.wait([_future, _fuelFuture]);
  }

  Future<void> _openSheet({VehicleServiceLog? existingLog}) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddServiceLogSheet(repo: _repo, driverPhone: widget.driverPhone, existingLog: existingLog),
    );
    if (changed == true) await _refresh();
  }

  Future<void> _editTankCapacity() async {
    final ctrl = TextEditingController(text: _tankCapacity?.toStringAsFixed(0) ?? '');
    final value = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('⛽ سعة خزان الوقود'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'السعة باللتر'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(double.tryParse(ctrl.text.trim())),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (value == null || value <= 0) return;
    final ok = await _repo.setFuelTankCapacity(widget.driverPhone, value);
    if (!mounted) return;
    if (ok) {
      setState(() => _tankCapacity = value);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذّر حفظ سعة الخزان')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.mutedSurface,
      appBar: AppBar(title: const Text('🔧 خدمات المركبة')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openSheet(),
        icon: const Icon(Icons.add),
        label: const Text('سجّل عملية'),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            FutureBuilder<List<VehicleServiceLog>>(
              future: _fuelFuture,
              builder: (context, snap) => _FuelSummaryCard(
                logs: snap.data ?? const [],
                tankCapacity: _tankCapacity,
                onEditCapacity: _editTankCapacity,
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                children: [
                  _filterChip(null, 'الكل'),
                  for (final e in _serviceTypeLabels.entries) _filterChip(e.key, e.value),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: FutureBuilder<List<VehicleServiceLog>>(
                  future: _future,
                  builder: (context, snap) {
                    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                    final logs = snap.data!;
                    if (logs.isEmpty) {
                      return ListView(
                        children: const [
                          SizedBox(height: 80),
                          Center(
                            child: Text('مفيش سجلات لسه — اضغط "سجّل عملية" عشان تضيف أول عملية',
                                textAlign: TextAlign.center, style: TextStyle(color: AppColors.textFaint)),
                          ),
                        ],
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                      itemCount: logs.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _LogCard(log: logs[i], onTap: () => _openSheet(existingLog: logs[i])),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String? type, String label) {
    final selected = _filter == type;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: selected ? Colors.white : null)),
        selected: selected,
        selectedColor: AppColors.primary,
        onSelected: (_) => setState(() {
          _filter = type;
          _load();
        }),
      ),
    );
  }
}

/// Average consumption (km/liter) computed from odometer deltas between
/// consecutive fill-ups — the standard "full-to-full" method — plus
/// running totals, shown above the list regardless of the active filter.
class _FuelSummaryCard extends StatelessWidget {
  final List<VehicleServiceLog> logs;
  final double? tankCapacity;
  final VoidCallback onEditCapacity;
  const _FuelSummaryCard({required this.logs, required this.tankCapacity, required this.onEditCapacity});

  @override
  Widget build(BuildContext context) {
    final withOdometer = logs.where((l) => l.odometerKm != null && l.fuelLiters != null && l.fuelLiters! > 0).toList()
      ..sort((a, b) => a.odometerKm!.compareTo(b.odometerKm!));

    double kmSum = 0, literSum = 0;
    for (var i = 1; i < withOdometer.length; i++) {
      final deltaKm = withOdometer[i].odometerKm! - withOdometer[i - 1].odometerKm!;
      if (deltaKm > 0) {
        kmSum += deltaKm;
        literSum += withOdometer[i].fuelLiters!;
      }
    }
    final avgKmPerLiter = literSum > 0 ? kmSum / literSum : null;
    final totalCost = logs.fold<double>(0, (s, l) => s + (l.cost ?? 0));
    final totalLiters = logs.fold<double>(0, (s, l) => s + (l.fuelLiters ?? 0));

    if (logs.isEmpty && tankCapacity == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: Text('⛽ ملخص الوقود', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13))),
              InkWell(
                onTap: onEditCapacity,
                child: Row(
                  children: [
                    Text(
                      tankCapacity != null ? 'سعة الخزان: ${tankCapacity!.toStringAsFixed(0)} لتر' : 'حدّد سعة الخزان',
                      style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 2),
                    const Icon(Icons.edit, size: 13, color: AppColors.primary),
                  ],
                ),
              ),
            ],
          ),
          if (logs.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                Text(
                  avgKmPerLiter != null ? 'معدل الاستهلاك: ${avgKmPerLiter.toStringAsFixed(1)} كم/لتر' : 'معدل الاستهلاك: محتاج تعبئتين على الأقل',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                Text('إجمالي الإنفاق: ${totalCost.toStringAsFixed(0)} ج.م', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                Text('إجمالي اللترات: ${totalLiters.toStringAsFixed(1)} لتر', style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LogCard extends StatelessWidget {
  final VehicleServiceLog log;
  final VoidCallback onTap;
  const _LogCard({required this.log, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final label = log.serviceType == 'other' && log.customLabel != null
        ? '➕ ${log.customLabel}'
        : _serviceTypeLabels[log.serviceType] ?? log.serviceType;
    final d = log.performedAt.toLocal();
    final dateStr = '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14))),
                Text(dateStr, style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_left, size: 18, color: AppColors.textFaint),
              ],
            ),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                if (log.cost != null) Text('💰 ${log.cost!.toStringAsFixed(0)} ج.م', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                if (log.odometerKm != null) Text('🧭 ${log.odometerKm!.toStringAsFixed(0)} كم', style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
                if (log.fuelLiters != null) Text('⛽ ${log.fuelLiters!.toStringAsFixed(1)} لتر', style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
                if (log.pricePerLiter != null) Text('(${log.pricePerLiter!.toStringAsFixed(2)} ج.م/لتر)', style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
              ],
            ),
            if (log.notes != null && log.notes!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(log.notes!, style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
            ],
          ],
        ),
      ),
    );
  }
}

class _AddServiceLogSheet extends StatefulWidget {
  final VehicleServiceRepository repo;
  final String driverPhone;
  final VehicleServiceLog? existingLog;
  const _AddServiceLogSheet({required this.repo, required this.driverPhone, this.existingLog});

  @override
  State<_AddServiceLogSheet> createState() => _AddServiceLogSheetState();
}

class _AddServiceLogSheetState extends State<_AddServiceLogSheet> {
  late String _type;
  late final TextEditingController _customLabelCtrl;
  late final TextEditingController _costCtrl;
  late final TextEditingController _odometerCtrl;
  late final TextEditingController _fuelLitersCtrl;
  late final TextEditingController _pricePerLiterCtrl;
  late final TextEditingController _notesCtrl;
  late DateTime _date;
  bool _submitting = false;
  bool _deleting = false;
  String? _error;

  bool get _editing => widget.existingLog != null;

  @override
  void initState() {
    super.initState();
    final log = widget.existingLog;
    _type = log?.serviceType ?? 'maintenance';
    _customLabelCtrl = TextEditingController(text: log?.customLabel ?? '');
    _costCtrl = TextEditingController(text: log?.cost?.toStringAsFixed(2) ?? '');
    _odometerCtrl = TextEditingController(text: log?.odometerKm?.toStringAsFixed(0) ?? '');
    _fuelLitersCtrl = TextEditingController(text: log?.fuelLiters?.toStringAsFixed(1) ?? '');
    _pricePerLiterCtrl = TextEditingController(text: log?.pricePerLiter?.toStringAsFixed(2) ?? '');
    _notesCtrl = TextEditingController(text: log?.notes ?? '');
    _date = log?.performedAt ?? DateTime.now();
    for (final c in [_fuelLitersCtrl, _pricePerLiterCtrl]) {
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
    _notesCtrl.dispose();
    super.dispose();
  }

  double? get _computedFuelTotal {
    final price = double.tryParse(_pricePerLiterCtrl.text.trim());
    final liters = double.tryParse(_fuelLitersCtrl.text.trim());
    if (price == null || liters == null) return null;
    return price * liters;
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
    setState(() {
      _submitting = true;
      _error = null;
    });

    final isFuel = _type == 'fuel';
    final String? error;
    if (_editing) {
      error = await widget.repo.updateLog(
        driverPhone: widget.driverPhone,
        logId: widget.existingLog!.id,
        serviceType: _type,
        customLabel: _type == 'other' ? _customLabelCtrl.text.trim() : null,
        cost: isFuel ? null : double.tryParse(_costCtrl.text.trim()),
        odometerKm: double.tryParse(_odometerCtrl.text.trim()),
        fuelLiters: isFuel ? double.tryParse(_fuelLitersCtrl.text.trim()) : null,
        pricePerLiter: isFuel ? double.tryParse(_pricePerLiterCtrl.text.trim()) : null,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        performedAt: _date,
      );
    } else {
      error = await widget.repo.logService(
        driverPhone: widget.driverPhone,
        serviceType: _type,
        customLabel: _type == 'other' ? _customLabelCtrl.text.trim() : null,
        cost: isFuel ? null : double.tryParse(_costCtrl.text.trim()),
        odometerKm: double.tryParse(_odometerCtrl.text.trim()),
        fuelLiters: isFuel ? double.tryParse(_fuelLitersCtrl.text.trim()) : null,
        pricePerLiter: isFuel ? double.tryParse(_pricePerLiterCtrl.text.trim()) : null,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        performedAt: _date,
      );
    }
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _submitting = false;
        _error = error;
      });
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف السجل؟'),
        content: const Text('مش هينفع ترجع فيه بعد الحذف.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('حذف', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _deleting = true);
    final ok = await widget.repo.deleteLog(widget.driverPhone, widget.existingLog!.id);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _deleting = false;
        _error = 'تعذّر الحذف، حاول مرة أخرى.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _date;
    final dateStr = '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
    final isFuel = _type == 'fuel';
    final computedTotal = _computedFuelTotal;
    final busy = _submitting || _deleting;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          decoration: BoxDecoration(color: context.surfaceColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: context.borderColor, borderRadius: BorderRadius.circular(999))),
                ),
                Text(_editing ? '✏️ تعديل العملية' : '🔧 سجّل عملية جديدة', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(height: 16),
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                    child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
                  ),
                  const SizedBox(height: 12),
                ],
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in _serviceTypeLabels.entries)
                      ChoiceChip(
                        label: Text(e.value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _type == e.key ? Colors.white : null)),
                        selected: _type == e.key,
                        selectedColor: AppColors.primary,
                        onSelected: (_) => setState(() => _type = e.key),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
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
                ],
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
                  onPressed: busy ? null : _submit,
                  child: _submitting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_editing ? 'حفظ التعديل' : 'حفظ'),
                ),
                if (_editing) ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: busy ? null : _delete,
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.error, side: const BorderSide(color: AppColors.error)),
                    child: _deleting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.error))
                        : const Text('🗑️ حذف السجل'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
