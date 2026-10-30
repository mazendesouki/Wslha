import 'package:flutter/material.dart';
import '../../core/theme.dart';

/// Shared across every "خدمات المركبة" screen (list, type selection, form,
/// confirmation, detail, monthly report, summary) — kept in one place so
/// none of them drift out of sync with each other.
const Map<String, String> vehicleServiceTypeLabels = {
  'maintenance': '🛠️ صيانة دورية',
  'fuel': '⛽ وقود',
  'tire': '🛞 كاوتش',
  'oil': '🛢️ زيت',
  'inspection': '🔍 فحص المحرك',
  'other': '➕ خدمة تانية',
};

/// Mirrors db/security-142's seeded maintenance_catalog_items. An
/// item_key not found here (e.g. a future admin-added item) just shows
/// its raw key — screens with their own catalog fetch (the form) use the
/// live label_ar instead; this is only the fallback for screens that
/// display a log entry without re-fetching the whole catalog.
const Map<String, String> vehicleMaintenanceItemLabels = {
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
  'ac_filter': 'فلتر التكييف',
};

/// Service types priced as (unit price × quantity) with an auto-computed
/// total, same calculation pattern as fuel — just with a generic
/// quantity/unit_price pair instead of fuel's dedicated liters/price-per-
/// liter columns. maintenance/inspection/other stay flat-cost (no single
/// natural unit applies to all of them).
class VehicleServiceQuantityUnitConfig {
  final String quantityLabel;
  final String unitPriceLabel;
  final String quantitySuffix;
  final String unitPriceSuffix;
  const VehicleServiceQuantityUnitConfig({
    required this.quantityLabel,
    required this.unitPriceLabel,
    required this.quantitySuffix,
    required this.unitPriceSuffix,
  });
}

const Map<String, VehicleServiceQuantityUnitConfig> vehicleServiceQuantityUnitConfigs = {
  'oil': VehicleServiceQuantityUnitConfig(
    quantityLabel: 'عدد اللترات',
    unitPriceLabel: 'سعر اللتر (ج.م)',
    quantitySuffix: 'لتر',
    unitPriceSuffix: 'ج.م/لتر',
  ),
  'tire': VehicleServiceQuantityUnitConfig(
    quantityLabel: 'العدد',
    unitPriceLabel: 'سعر الكاوتش الواحد (ج.م)',
    quantitySuffix: 'كاوتش',
    unitPriceSuffix: 'ج.م/كاوتش',
  ),
};

String formatVehicleServiceQuantity(double? q) {
  if (q == null) return '';
  return q % 1 == 0 ? q.toStringAsFixed(0) : q.toStringAsFixed(1);
}

/// One short "what it is / why it matters" + a practical tip — shown
/// inline under the selected service/item, so the driver sees guidance
/// right when it's relevant instead of a separate reference page.
class VehicleServiceGuidance {
  final String description;
  final String tip;
  const VehicleServiceGuidance({required this.description, required this.tip});
}

const Map<String, VehicleServiceGuidance> vehicleServiceTypeGuidance = {
  'fuel': VehicleServiceGuidance(
    description: 'سجّل سعر اللتر وعدد اللترات بدل التكلفة الكلية — كده التطبيق يحسبلك معدل الاستهلاك أوتوماتيك.',
    tip: 'سجّل عداد الكيلومترات مع كل تعبئة — من غيره معدل الاستهلاك ما يتحسبش صح.',
  ),
  'tire': VehicleServiceGuidance(
    description: 'الكاوتش بيتأثر بالتحميل والسرعة وحالة الطرق، مش بس بعدد الكيلومترات.',
    tip: 'افحص ضغط الهواء بانتظام وراقب علامات التآكل غير المتساوي — ممكن تدل على مشكلة في الكمبيوتر أو الفرامل.',
  ),
  'oil': VehicleServiceGuidance(
    description: 'زيت المحرك بيفقد كفاءته مع الوقت حتى لو العربية واقفة — غيّره على الفترة الموصى بيها حتى لو مشيت كيلومترات قليلة.',
    tip: 'اختار النوع المناسب لموديل عربيتك، ومتأخرش عن الموعد عشان ميأثرش على عمر المحرك.',
  ),
  'inspection': VehicleServiceGuidance(
    description: 'فحص دوري شامل للمحرك بيكشف مشاكل بسيطة قبل ما تبقى كبيرة ومكلفة.',
    tip: 'لو سمعت صوت غريب أو حسيت بأداء مختلف، متأجلش الفحص.',
  ),
  'other': VehicleServiceGuidance(
    description: 'لأي خدمة مش موجودة في القايمة — اكتب اسمها بوضوح عشان تقدر تتابعها بسهولة بعدين.',
    tip: 'لو الخدمة دي بتتكرر معاك، يستاهل توضيح اسمها بشكل ثابت كل مرة عشان تبقى سهلة التتبع.',
  ),
};

const Map<String, VehicleServiceGuidance> vehicleMaintenanceItemGuidance = {
  'oil_filter': VehicleServiceGuidance(
    description: 'فلتر الزيت بيمنع الشوائب من الوصول للمحرك — فلتر متسخ بيقلل كفاءة التزييت.',
    tip: 'غيّره مع كل تغيير زيت — متأخرش عنه.',
  ),
  'air_filter': VehicleServiceGuidance(
    description: 'فلتر الهواء بيأثر على كفاءة احتراق الوقود واستهلاك البنزين.',
    tip: 'فلتر متسخ بيزوّد استهلاك الوقود ويقلل قوة المحرك.',
  ),
  'fuel_filter': VehicleServiceGuidance(
    description: 'فلتر البنزين بيمنع الشوائب من الوصول لنظام الحقن.',
    tip: 'إهماله ممكن يسبب تقطيع في أداء المحرك أو صعوبة في التشغيل.',
  ),
  'spark_plugs': VehicleServiceGuidance(
    description: 'البوجيهات مسؤولة عن إشعال خليط الوقود والهواء جوه المحرك.',
    tip: 'بوجيهات قديمة بتسبب استهلاك وقود أعلى وتقطيع في أداء المحرك.',
  ),
  'brake_pads': VehicleServiceGuidance(
    description: 'تيل الفرامل من أهم عناصر الأمان في العربية.',
    tip: 'لو سمعت صوت صرير عند الفرملة، افحصه فورًا — ده عنصر حرج.',
  ),
  'brake_fluid': VehicleServiceGuidance(
    description: 'زيت الفرامل بينقل الضغط من الدواسة للفرامل — تدهوره بيضعف كفاءة الفرملة.',
    tip: 'لازم يتغيّر بالفترة حتى لو مشيتش كيلومترات كتير، لأنه بيمتص رطوبة مع الوقت.',
  ),
  'timing_belt': VehicleServiceGuidance(
    description: 'سير الكاتينة/التايمنج بينظّم حركة المحرك — قطعه المفاجئ ممكن يسبب تلف كبير جدًا في المحرك.',
    tip: 'متأخرش عن موعده أبدًا — ده من أخطر عناصر الصيانة لو اتجاهل.',
  ),
  'battery': VehicleServiceGuidance(
    description: 'البطارية بتضعف مع الوقت حتى لو العربية بتتستخدم بانتظام.',
    tip: 'لو لاحظت صعوبة في بدء التشغيل، افحص البطارية قبل ما تقف تمامًا.',
  ),
  'coolant': VehicleServiceGuidance(
    description: 'سائل التبريد بيمنع المحرك من السخونة الزايدة.',
    tip: 'لو عداد الحرارة بيرتفع كتير، افحص مستوى السائل فورًا.',
  ),
  'transmission_fluid': VehicleServiceGuidance(
    description: 'زيت الجير بيحافظ على سلاسة نقل الحركة بين الجير والمحرك.',
    tip: 'إهماله بيسبب صعوبة في تغيير السرعات بمرور الوقت.',
  ),
  'shock_absorbers': VehicleServiceGuidance(
    description: 'المساعدين (الكاتم) بيحافظوا على ثبات العربية والتحكم فيها.',
    tip: 'لو حسيت العربية بترتج كتير في المطبات، افحصهم.',
  ),
  'ac_filter': VehicleServiceGuidance(
    description: 'فلتر التكييف بيأثر على جودة الهواء جوه العربية وكفاءة التبريد.',
    tip: 'فلتر متسخ بيضعف التبريد وبيدي ريحة مش حلوة — غيّره بانتظام خصوصًا في الصيف.',
  ),
};

/// Inline "what it is / why it matters" card shown right under the
/// selected service or maintenance item.
class VehicleServiceGuidanceCard extends StatelessWidget {
  final VehicleServiceGuidance guidance;
  final String? importance; // 'critical' | 'important' — maintenance items only
  final String? intervalText;
  const VehicleServiceGuidanceCard({super.key, required this.guidance, this.importance, this.intervalText});

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

/// Icon shown per service type on the type-selection screen and
/// elsewhere a bigger visual marker is useful than the emoji-in-label.
const Map<String, IconData> vehicleServiceTypeIcons = {
  'maintenance': Icons.build_rounded,
  'fuel': Icons.local_gas_station_rounded,
  'tire': Icons.circle_outlined,
  'oil': Icons.opacity_rounded,
  'inspection': Icons.search_rounded,
  'other': Icons.add_circle_outline_rounded,
};
