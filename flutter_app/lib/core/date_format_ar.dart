/// Explicit صباحًا/مساءً (AM/PM) date-time formatting — independent of the
/// device's 24-hour system setting. `TimeOfDay.format(context)` silently
/// follows `MediaQuery.alwaysUse24HourFormat`, so on a phone set to 24-hour
/// time an airport flight time like "2:30 م" renders as a bare "14:30" with
/// no AM/PM marker at all — exactly what makes a departure/arrival time
/// ambiguous on the driver's acceptance card and the customer's booking
/// invoice. These helpers always spell out ص/م regardless of that setting.
library;

const List<String> _arMonths = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

/// e.g. "2:05 م"
String arTime(DateTime dt) {
  final t = dt.toLocal();
  final period = t.hour >= 12 ? 'م' : 'ص';
  final hour12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final minute = t.minute.toString().padLeft(2, '0');
  return '$hour12:$minute $period';
}

/// e.g. "30 أغسطس 2026"
String arDate(DateTime dt) {
  final t = dt.toLocal();
  return '${t.day} ${_arMonths[t.month - 1]} ${t.year}';
}

/// e.g. "30 أغسطس 2026 — 2:05 م"
String arDateTime(DateTime dt) => '${arDate(dt)} — ${arTime(dt)}';
