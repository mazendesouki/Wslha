// Marketplace شحن-نوع selector + "add listing" in-app link (db/security-94
// -marketplace-shipment-type.sql) — kept as its own file per the
// established parallel-batch pattern (see i18n.dart's merge comment).
const Map<String, Map<String, String>> batchKStrings = {
  // marketplace_list_screen.dart
  'marketplace_list_add_listing': {'ar': 'أضف إعلاناً', 'en': 'Add a listing'},

  // Delivery request bottom sheet — shipment type
  'marketplace_delivery_shipment_type_label': {'ar': 'نوع الشحنة', 'en': 'Shipment type'},
  'marketplace_delivery_error_shipment_type': {'ar': 'اختر نوع الشحنة', 'en': 'Choose the shipment type'},
};
