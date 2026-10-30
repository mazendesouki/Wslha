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

/// Service types priced as (unit price × quantity) with an auto-computed
/// total, same calculation pattern as fuel — just with a generic
/// quantity/unit_price pair instead of fuel's dedicated liters/price-per-
/// liter columns. maintenance/inspection/other stay flat-cost (no single
/// natural unit applies to all of them).
class _QuantityUnitConfig {
  final String quantityLabel;
  final String unitPriceLabel;
  final String quantitySuffix;
  final String unitPriceSuffix;
  const _QuantityUnitConfig({
    required this.quantityLabel,
    required this.unitPriceLabel,
    required this.quantitySuffix,
    required this.unitPriceSuffix,
  });
}

/// Fallback labels for _LogCard (which has no catalog fetch of its own) —
/// mirrors db/security-142's seeded maintenance_catalog_items. An item_key
/// not found here (e.g. a future admin-added item) just shows its raw key.
const Map<String, String> _maintenanceItemLabels = {
  'oil_filter': 'تغيير فلتر الزيت',
  'air_filter': 'فلتر الهواء',
  'fuel_filter': 'فلتر البنزين',
  'spark_plugs': 'البوجيهات',
  'brake_pads': 'تيل الفرامل',
  'brake_fluid': 'زيت الفرامل',
  'timing_belt': 'سير الكاتينة/التايمنج',
  'battery': 'البطارية',
  'coolant': 'سائل التبريد',
  'transmission_fluid': 'زيت الجير',
  'shock_absorbers': 'المساعدين (الكاتم)',
};

/// One short "what it is / why it matters" + a practical tip — shown
/// inline under the selected service/item in the add-log sheet, so the
/// driver sees guidance right when it's relevant instead of a separate
/// reference page.
class _ServiceGuidance {
  final String description;
  final String tip;
  const _ServiceGuidance({required this.description, required this.tip});
}

const Map<String, _ServiceGuidance> _serviceTypeGuidance = {
  'fuel': _ServiceGuidance(
    description: 'سجّل سعر اللتر وعدد اللترات بدل التكلفة الكلية — كده التطبيق يحسبلك معدل الاستهلاك أوتوماتيك.',
    tip: 'سجّل عداد الكيلومترات مع كل تعبئة — من غيره معدل الاستهلاك ما يتحسبش صح.',
  ),
  'tire': _ServiceGuidance(
    description: 'الكاوتش بيتأثر بالتحميل والسرعة وحالة الطرق، مش بس بعدد الكيلومترات.',
    tip: 'افحص ضغط الهواء بانتظام وراقب علامات التآكل غير المتساوي — ممكن تدل على مشكلة في الكمبيوتر أو الفرامل.',
  ),
  'oil': _ServiceGuidance(
    description: 'زيت المحرك بيفقد كفاءته مع الوقت حتى لو العربية واقفة — غيّره على الفترة الموصى بيها حتى لو مشيت كيلومترات قليلة.',
    tip: 'اختار النوع المناسب لموديل عربيتك، ومتأخرش عن الموعد عشان ميأثرش على عمر المحرك.',
  ),
  'inspection': _ServiceGuidance(
    description: 'فحص دوري شامل للمحرك بيكشف مشاكل بسيطة قبل ما تبقى كبيرة ومكلفة.',
    tip: 'لو سمعت صوت غريب أو حسيت بأداء مختلف، متأجلش الفحص.',
  ),
  'other': _ServiceGuidance(
    description: 'لأي خدمة مش موجودة في القايمة — اكتب اسمها بوضوح عشان تقدر تتابعها بسهولة بعدين.',
    tip: 'لو الخدمة دي بتتكرر معاك، يستاهل توضيح اسمها بشكل ثابت كل مرة عشان تبقى سهلة التتبع.',
  ),
};

const Map<String, _ServiceGuidance> _maintenanceItemGuidance = {
  'oil_filter': _ServiceGuidance(
    description: 'فلتر الزيت بيمنع الشوائب من الوصول للمحرك — فلتر متسخ بيقلل كفاءة التزييت.',
    tip: 'غيّره مع كل تغيير زيت — متأخرش عنه.',
  ),
  'air_filter': _ServiceGuidance(
    description: 'فلتر الهواء بيأثر على كفاءة احتراق الوقود واستهلاك البنزين.',
    tip: 'فلتر متسخ بيزوّد استهلاك الوقود ويقلل قوة المحرك.',
  ),
  'fuel_filter': _ServiceGuidance(
    description: 'فلتر البنزين بيمنع الشوائب من الوصول لنظام الحقن.',
    tip: 'إهماله ممكن يسبب تقطيع في أداء المحرك أو صعوبة في التشغيل.',
  ),
  'spark_plugs': _ServiceGuidance(
    description: 'البوجيهات مسؤولة عن إشعال خليط الوقود والهواء جوه المحرك.',
    tip: 'بوجيهات قديمة بتسبب استهلاك وقود أعلى وتقطيع في أداء المحرك.',
  ),
  'brake_pads': _ServiceGuidance(
    description: 'تيل الفرامل من أهم عناصر الأمان في العربية.',
    tip: 'لو سمعت صوت صرير عند الفرملة، افحصه فورًا — ده عنصر حرج.',
  ),
  'brake_fluid': _ServiceGuidance(
    description: 'زيت الفرامل بينقل الضغط من الدواسة للفرامل — تدهوره بيضعف كفاءة الفرملة.',
    tip: 'لازم يتغيّر بالفترة حتى لو مشيتش كيلومترات كتير، لأنه بيمتص رطوبة مع الوقت.',
  ),
  'timing_belt': _ServiceGuidance(
    description: 'سير الكاتينة/التايمنج بينظّم حركة المحرك — قطعه المفاجئ ممكن يسبب تلف كبير جدًا في المحرك.',
    tip: 'متأخرش عن موعده أبدًا — ده من أخطر عناصر الصيانة لو اتجاهل.',
  ),
  'battery': _ServiceGuidance(
    description: 'البطارية بتضعف مع الوقت حتى لو العربية بتتستخدم بانتظام.',
    tip: 'لو لاحظت صعوبة في بدء التشغيل، افحص البطارية قبل ما تقف تمامًا.',
  ),
  'coolant': _ServiceGuidance(
    description: 'سائل التبريد بيمنع المحرك من السخونة الزايدة.',
    tip: 'لو عداد الحرارة بيرتفع كتير، افحص مستوى السائل فورًا.',
  ),
  'transmission_fluid': _ServiceGuidance(
    description: 'زيت الجير بيحافظ على سلاسة نقل الحركة بين الجير والمحرك.',
    tip: 'إهماله بيسبب صعوبة في تغيير السرعات بمرور الوقت.',
  ),
  'shock_absorbers': _ServiceGuidance(
    description: 'المساعدين (الكاتم) بيحافظوا على ثبات العربية والتحكم فيها.',
    tip: 'لو حسيت العربية بترتج كتير في المطبات، افحصهم.',
  ),
};

/// Inline "what it is / why it matters" card shown right under the
/// selected service or maintenance item — see the _serviceTypeGuidance/
/// _maintenanceItemGuidance maps above for the content itself.
class _GuidanceCard extends StatelessWidget {
  final _ServiceGuidance guidance;
  final String? importance; // 'critical' | 'important' — maintenance items only
  final String? intervalText;
  const _GuidanceCard({required this.guidance, this.importance, this.intervalText});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (importance != null || intervalText != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (importance != null)
                    Text(
                      importance == 'critical' ? '‼️ عنصر حرج' : 'ℹ️ عنصر مهم',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: importance == 'critical' ? AppColors.error : AppColors.primary,
                      ),
                    ),
                  if (intervalText != null)
                    Text(intervalText!, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint)),
                ],
              ),
            ),
          Text('💡 ${guidance.description}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, height: 1.5)),
          const SizedBox(height: 6),
          Text('👁️ ${guidance.tip}', style: const TextStyle(fontSize: 12, color: AppColors.textFaint, height: 1.5)),
        ],
      ),
    );
  }
}

String _formatQuantity(double? q) {
  if (q == null) return '';
  return q % 1 == 0 ? q.toStringAsFixed(0) : q.toStringAsFixed(1);
}

const Map<String, _QuantityUnitConfig> _quantityUnitConfigs = {
  'oil': _QuantityUnitConfig(
    quantityLabel: 'عدد اللترات',
    unitPriceLabel: 'سعر اللتر (ج.م)',
    quantitySuffix: 'لتر',
    unitPriceSuffix: 'ج.م/لتر',
  ),
  'tire': _QuantityUnitConfig(
    quantityLabel: 'العدد',
    unitPriceLabel: 'سعر الكاوتش الواحد (ج.م)',
    quantitySuffix: 'كاوتش',
    unitPriceSuffix: 'ج.م/كاوتش',
  ),
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
  late Future<List<MaintenanceDueStatus>> _maintenanceDueFuture;
  double? _tankCapacity;
  String? _filter;

  @override
  void initState() {
    super.initState();
    _load();
    _loadFuelSummary();
    _loadMaintenanceDue();
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

  void _loadMaintenanceDue() {
    _maintenanceDueFuture = _repo.getMaintenanceDueStatus(widget.driverPhone);
  }

  Future<void> _refresh() async {
    setState(() {
      _load();
      _loadFuelSummary();
      _loadMaintenanceDue();
    });
    await Future.wait([_future, _fuelFuture, _maintenanceDueFuture]);
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
            FutureBuilder<List<MaintenanceDueStatus>>(
              future: _maintenanceDueFuture,
              builder: (context, snap) => _MaintenanceDueCard(items: snap.data ?? const []),
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

/// Shows which periodic-maintenance catalog items (db/security-142) are
/// overdue or due soon, computed server-side from km since each item was
/// last logged against the driver's latest known odometer reading.
/// Collapses to nothing once everything is ok/never-tracked-yet, so it
/// doesn't take space when there's nothing actionable.
class _MaintenanceDueCard extends StatelessWidget {
  final List<MaintenanceDueStatus> items;
  const _MaintenanceDueCard({required this.items});

  @override
  Widget build(BuildContext context) {
    final due = items.where((i) => i.status == 'overdue' || i.status == 'due_soon').toList()
      ..sort((a, b) {
        if (a.status != b.status) return a.status == 'overdue' ? -1 : 1;
        if (a.importance != b.importance) return a.importance == 'critical' ? -1 : 1;
        return 0;
      });
    if (due.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('🛠️ صيانة مطلوبة', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final i in due)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: i.status == 'overdue' ? AppColors.error.withValues(alpha: 0.15) : const Color(0xFFFFEDD5),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${i.status == 'overdue' ? '⛔' : '⏰'} ${i.labelAr}${i.importance == 'critical' ? ' ‼️' : ''}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: i.status == 'overdue' ? AppColors.error : const Color(0xFFB45309),
                    ),
                  ),
                ),
            ],
          ),
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
                if (log.quantity != null)
                  Text(
                    '${_formatQuantity(log.quantity)} ${_quantityUnitConfigs[log.serviceType]?.quantitySuffix ?? ''}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textFaint),
                  ),
                if (log.unitPrice != null)
                  Text(
                    '(${log.unitPrice!.toStringAsFixed(2)} ${_quantityUnitConfigs[log.serviceType]?.unitPriceSuffix ?? 'ج.م'})',
                    style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
                  ),
              ],
            ),
            if (log.maintenanceItems != null && log.maintenanceItems!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final key in log.maintenanceItems!)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(999)),
                      child: Text(_maintenanceItemLabels[key] ?? key, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary)),
                    ),
                ],
              ),
            ],
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
  late final TextEditingController _quantityCtrl;
  late final TextEditingController _unitPriceCtrl;
  late final TextEditingController _notesCtrl;
  late DateTime _date;
  bool _submitting = false;
  bool _deleting = false;
  String? _error;
  late Future<List<MaintenanceCatalogItem>> _catalogFuture;
  String? _selectedMaintenanceItem;

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
    _quantityCtrl = TextEditingController(text: _formatQuantity(log?.quantity));
    _unitPriceCtrl = TextEditingController(text: log?.unitPrice?.toStringAsFixed(2) ?? '');
    _notesCtrl = TextEditingController(text: log?.notes ?? '');
    _date = log?.performedAt ?? DateTime.now();
    _selectedMaintenanceItem = (log?.maintenanceItems?.isNotEmpty ?? false) ? log!.maintenanceItems!.first : null;
    _catalogFuture = widget.repo.listMaintenanceCatalog();
    for (final c in [_fuelLitersCtrl, _pricePerLiterCtrl, _quantityCtrl, _unitPriceCtrl]) {
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
    final quantityConfig = _quantityUnitConfigs[_type];
    final usesFlatCost = !isFuel && quantityConfig == null;
    final String? error;
    if (_editing) {
      error = await widget.repo.updateLog(
        driverPhone: widget.driverPhone,
        logId: widget.existingLog!.id,
        serviceType: _type,
        customLabel: _type == 'other' ? _customLabelCtrl.text.trim() : null,
        cost: usesFlatCost ? double.tryParse(_costCtrl.text.trim()) : null,
        odometerKm: double.tryParse(_odometerCtrl.text.trim()),
        fuelLiters: isFuel ? double.tryParse(_fuelLitersCtrl.text.trim()) : null,
        pricePerLiter: isFuel ? double.tryParse(_pricePerLiterCtrl.text.trim()) : null,
        quantity: quantityConfig != null ? double.tryParse(_quantityCtrl.text.trim()) : null,
        unitPrice: quantityConfig != null ? double.tryParse(_unitPriceCtrl.text.trim()) : null,
        maintenanceItems: _type == 'maintenance' && _selectedMaintenanceItem != null ? [_selectedMaintenanceItem!] : null,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        performedAt: _date,
      );
    } else {
      error = await widget.repo.logService(
        driverPhone: widget.driverPhone,
        serviceType: _type,
        customLabel: _type == 'other' ? _customLabelCtrl.text.trim() : null,
        cost: usesFlatCost ? double.tryParse(_costCtrl.text.trim()) : null,
        odometerKm: double.tryParse(_odometerCtrl.text.trim()),
        fuelLiters: isFuel ? double.tryParse(_fuelLitersCtrl.text.trim()) : null,
        pricePerLiter: isFuel ? double.tryParse(_pricePerLiterCtrl.text.trim()) : null,
        quantity: quantityConfig != null ? double.tryParse(_quantityCtrl.text.trim()) : null,
        unitPrice: quantityConfig != null ? double.tryParse(_unitPriceCtrl.text.trim()) : null,
        maintenanceItems: _type == 'maintenance' && _selectedMaintenanceItem != null ? [_selectedMaintenanceItem!] : null,
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
    final quantityConfig = _quantityUnitConfigs[_type];
    final computedTotal = isFuel ? _computedFuelTotal : (quantityConfig != null ? _computedQuantityTotal : null);
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
                  _GuidanceCard(guidance: _serviceTypeGuidance['fuel']!),
                ] else if (quantityConfig != null) ...[
                  // Same calculation pattern as fuel (price_per_liter ×
                  // fuel_liters) but with a generic quantity/unit_price pair
                  // — oil: liters, tire: count. See db/security-140.
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
                  _GuidanceCard(guidance: _serviceTypeGuidance[_type]!),
                ] else if (_type == 'maintenance') ...[
                  // Pick EXACTLY ONE catalog item (db/security-142) per log
                  // entry — a visit covering several items gets logged as
                  // several entries, each with its own real cost, instead
                  // of lumping them under one shared total (explicit driver
                  // feedback: the old multi-select UI made it impossible to
                  // tell items apart or track their individual prices).
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
                          if (selectedCatalogItem != null && _maintenanceItemGuidance[selectedCatalogItem.itemKey] != null)
                            _GuidanceCard(
                              guidance: _maintenanceItemGuidance[selectedCatalogItem.itemKey]!,
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
                  if (_serviceTypeGuidance[_type] != null) _GuidanceCard(guidance: _serviceTypeGuidance[_type]!),
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
