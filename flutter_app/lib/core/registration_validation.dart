// Ported 1:1 from src/utils/validation.ts — keep both in sync if a rule
// changes (that file's own header notes the driver/merchant web pages
// already duplicate these rules inline for the same reason).

class ValidationResult {
  final bool valid;
  final String message;
  const ValidationResult(this.valid, this.message);
}

final RegExp _nameAllowed = RegExp(r'^[A-Za-z؀-ۿݐ-ݿ ]+$');

ValidationResult validateFullName(String input) {
  final name = input.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (name.length < 4) return const ValidationResult(false, 'أدخل الاسم الكامل (4 أحرف على الأقل).');
  if (name.length > 50) return const ValidationResult(false, 'الاسم طويل جداً (50 حرفاً كحد أقصى).');
  if (!_nameAllowed.hasMatch(name)) {
    return const ValidationResult(false, 'الاسم يجب أن يحتوي على حروف فقط — بدون أرقام أو رموز.');
  }
  final words = name.split(' ').where((w) => w.isNotEmpty).toList();
  if (words.length < 2) return const ValidationResult(false, 'أدخل الاسم الكامل (اسمان على الأقل).');
  if (words.any((w) => w.length < 2)) {
    return const ValidationResult(false, 'كل جزء من الاسم يجب أن يكون حرفين على الأقل.');
  }
  if (words.any((w) => RegExp(r'^(.)\1+$').hasMatch(w))) {
    return const ValidationResult(false, 'الاسم غير صالح، يرجى إدخال اسمك الحقيقي.');
  }
  return const ValidationResult(true, '');
}

final RegExp _usernameAllowed = RegExp(r'^[a-zA-Z0-9_.]+$');

ValidationResult validateUsername(String input) {
  final u = input.trim();
  if (u.length < 3 || u.length > 20) return const ValidationResult(false, 'اسم المستخدم من 3 إلى 20 حرفاً.');
  if (!_usernameAllowed.hasMatch(u)) {
    return const ValidationResult(false, 'اسم المستخدم: أحرف إنجليزية وأرقام و _ . فقط.');
  }
  return const ValidationResult(true, '');
}

final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

ValidationResult validateEmail(String input) {
  final e = input.trim();
  if (!_emailPattern.hasMatch(e)) return const ValidationResult(false, 'يرجى إدخال بريد إلكتروني صحيح.');
  return const ValidationResult(true, '');
}

/// First digit = century (2=1900s, 3=2000s+), followed by a real YYMMDD
/// birth date — rejects random 14-digit strings, not just wrong-length ones.
bool isValidEgyptianNationalId(String id) {
  if (!RegExp(r'^[23]\d{13}$').hasMatch(id)) return false;
  final century = id[0] == '2' ? 1900 : 2000;
  final year = century + int.parse(id.substring(1, 3));
  final month = int.parse(id.substring(3, 5));
  final day = int.parse(id.substring(5, 7));
  if (month < 1 || month > 12) return false;
  final daysInMonth = DateTime(year, month + 1, 0).day;
  return day >= 1 && day <= daysInMonth;
}

/// Valid, non-expired date — `v` must be today or later.
bool isFutureDateValue(DateTime? v) {
  if (v == null) return false;
  final today = DateTime.now();
  final todayMidnight = DateTime(today.year, today.month, today.day);
  return !v.isBefore(todayMidnight);
}

/// Same list register.astro's CITIES const uses.
const List<String> egyptianCities = ['دمياط الجديدة', 'دمياط', 'كفر سعد', 'فارسكور', 'منية النصر', 'رأس البر', 'الزرقا'];
