// Ported 1:1 from src/utils/phone.ts — keep both in sync if the format
// rules ever change (same validation the Supabase RPCs assume).

final RegExp _egMobile = RegExp(r'^01[0125][0-9]{8}$');

/// Strips spaces/dashes/parentheses and converts +20 / 0020 / 20 country
/// codes to the local 01XXXXXXXXX form.
String normalizeEgyptianPhone(String input) {
  var v = input.replaceAll(RegExp(r'[\s\-()]'), '');
  if (v.startsWith('+20')) {
    v = '0${v.substring(3)}';
  } else if (v.startsWith('0020')) {
    v = '0${v.substring(4)}';
  } else if (v.startsWith('20') && v.length == 12) {
    v = '0${v.substring(2)}';
  }
  return v;
}

bool isEgyptianMobile(String input) {
  return _egMobile.hasMatch(normalizeEgyptianPhone(input));
}

/// The web app stores orders/rides under whichever phone format the
/// customer happened to submit with (+20... or 0...) — queries there use
/// `or=(customer_phone.eq.<intl>,customer_phone.eq.<local>)` to catch both.
/// This derives the +20 form from the normalized local one.
String toIntlEgyptianPhone(String input) {
  final local = normalizeEgyptianPhone(input);
  return local.startsWith('0') ? '+20${local.substring(1)}' : local;
}

const String egPhoneError =
    'يرجى إدخال رقم جوال مصري صحيح: 11 رقمًا يبدأ بـ 010 أو 011 أو 012 أو 015.';
