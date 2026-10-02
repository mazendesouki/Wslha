// demand_hotspots_screen.dart — driver-facing "مناطق الطلب الساخنة" map
// (db/security-107-demand-hotspots.sql). Kept as its own file per the
// established parallel-batch pattern (see i18n.dart's merge comment).
const Map<String, Map<String, String>> batchMStrings = {
  'driver_home_hotspots_tooltip': {'ar': '🔥 مناطق الطلب الساخنة', 'en': '🔥 Demand hotspots'},
  'hotspots_appbar_title': {'ar': '🔥 مناطق الطلب الساخنة', 'en': '🔥 Demand hotspots'},
  'hotspots_subtitle': {
    'ar': 'الدوائر الأكبر والأغمق فيها طلبات أكتر مستنية سواق — آخر 45 دقيقة',
    'en': 'Bigger, darker circles mean more waiting requests — last 45 minutes',
  },
  'hotspots_empty': {'ar': 'مفيش طلبات مستنية سواق دلوقتي', 'en': 'No requests waiting for a driver right now'},
  'hotspots_error': {'ar': 'تعذّر تحميل البيانات، حاول تاني', 'en': 'Could not load the data — try again'},
  'hotspots_legend_rides': {'ar': 'رحلات', 'en': 'rides'},
  'hotspots_legend_orders': {'ar': 'طلبات توصيل', 'en': 'delivery orders'},
  'hotspots_refresh_tooltip': {'ar': 'تحديث', 'en': 'Refresh'},
};
