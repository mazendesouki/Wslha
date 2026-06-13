// Egyptian mobile number validation.
// Valid format: 11 digits, starts with 01, operator digit is 0/1/2/5
//   010… Vodafone · 011… Etisalat (WE) · 012… Orange · 015… WE
const EG_MOBILE = /^01[0125][0-9]{8}$/;

// Normalize common input variants to the local 01XXXXXXXXX form:
// strips spaces/dashes/parentheses and converts +20 / 0020 / 20 country codes.
export function normalizeEgyptianPhone(input: string): string {
  let v = (input || '').replace(/[\s\-()]/g, '');
  if (v.startsWith('+20'))       v = '0' + v.slice(3);
  else if (v.startsWith('0020')) v = '0' + v.slice(4);
  else if (v.startsWith('20') && v.length === 12) v = '0' + v.slice(2);
  return v;
}

export function isEgyptianMobile(input: string): boolean {
  return EG_MOBILE.test(normalizeEgyptianPhone(input));
}

export const EG_PHONE_ERROR =
  'يرجى إدخال رقم جوال مصري صحيح: 11 رقمًا يبدأ بـ 010 أو 011 أو 012 أو 015.';
