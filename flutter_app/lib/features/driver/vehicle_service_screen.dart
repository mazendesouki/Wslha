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

/// "خدمات المركبات" — سجل/ملف صيانة العربية: صيانة دورية، وقود (مع حساب
/// التكلفة)، كاوتش، زيت، فحص المحرك، وأي خدمة تانية السائق يحددها بنفسه.
/// See db/security-134-vehicle-service-logs.sql.
class VehicleServiceScreen extends StatefulWidget {
  final String driverPhone;
  const VehicleServiceScreen({super.key, required this.driverPhone});

  @override
  State<VehicleServiceScreen> createState() => _VehicleServiceScreenState();
}

class _VehicleServiceScreenState extends State<VehicleServiceScreen> {
  final _repo = VehicleServiceRepository();
  late Future<List<VehicleServiceLog>> _future;
  String? _filter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = _repo.listMine(widget.driverPhone, serviceType: _filter);
  }

  Future<void> _refresh() async {
    setState(_load);
    await _future;
  }

  Future<void> _openAddSheet() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddServiceLogSheet(repo: _repo, driverPhone: widget.driverPhone),
    );
    if (saved == true) await _refresh();
  }

  Future<void> _delete(VehicleServiceLog log) async {
    final ok = await _repo.deleteLog(widget.driverPhone, log.id);
    if (!mounted) return;
    if (ok) {
      await _refresh();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذّر حذف السجل')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.mutedSurface,
      appBar: AppBar(title: const Text('🔧 خدمات المركبة')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddSheet,
        icon: const Icon(Icons.add),
        label: const Text('سجّل عملية'),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
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
                      itemBuilder: (context, i) => _LogCard(log: logs[i], onDelete: () => _delete(logs[i])),
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

class _LogCard extends StatelessWidget {
  final VehicleServiceLog log;
  final VoidCallback onDelete;
  const _LogCard({required this.log, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final label = log.serviceType == 'other' && log.customLabel != null
        ? '➕ ${log.customLabel}'
        : _serviceTypeLabels[log.serviceType] ?? log.serviceType;
    final d = log.performedAt.toLocal();
    final dateStr = '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

    return Container(
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
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.error),
                onPressed: onDelete,
              ),
            ],
          ),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              if (log.cost != null) Text('💰 ${log.cost!.toStringAsFixed(0)} ج.م', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              if (log.odometerKm != null) Text('🧭 ${log.odometerKm!.toStringAsFixed(0)} كم', style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
              if (log.fuelLiters != null) Text('⛽ ${log.fuelLiters!.toStringAsFixed(1)} لتر', style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
              if (log.cost != null && log.fuelLiters != null && log.fuelLiters! > 0)
                Text('(${(log.cost! / log.fuelLiters!).toStringAsFixed(2)} ج.م/لتر)', style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
            ],
          ),
          if (log.notes != null && log.notes!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(log.notes!, style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
          ],
        ],
      ),
    );
  }
}

class _AddServiceLogSheet extends StatefulWidget {
  final VehicleServiceRepository repo;
  final String driverPhone;
  const _AddServiceLogSheet({required this.repo, required this.driverPhone});

  @override
  State<_AddServiceLogSheet> createState() => _AddServiceLogSheetState();
}

class _AddServiceLogSheetState extends State<_AddServiceLogSheet> {
  String _type = 'maintenance';
  final _customLabelCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _odometerCtrl = TextEditingController();
  final _fuelLitersCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _customLabelCtrl.dispose();
    _costCtrl.dispose();
    _odometerCtrl.dispose();
    _fuelLitersCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
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
    final error = await widget.repo.logService(
      driverPhone: widget.driverPhone,
      serviceType: _type,
      customLabel: _type == 'other' ? _customLabelCtrl.text.trim() : null,
      cost: double.tryParse(_costCtrl.text.trim()),
      odometerKm: double.tryParse(_odometerCtrl.text.trim()),
      fuelLiters: _type == 'fuel' ? double.tryParse(_fuelLitersCtrl.text.trim()) : null,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      performedAt: _date,
    );
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

  @override
  Widget build(BuildContext context) {
    final d = _date;
    final dateStr = '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          decoration: BoxDecoration(color: context.surfaceColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: context.borderColor, borderRadius: BorderRadius.circular(999))),
              ),
              const Text('🔧 سجّل عملية جديدة', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
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
              if (_type == 'fuel') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _fuelLitersCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'عدد اللترات'),
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
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('حفظ'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
