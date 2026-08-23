// ─────────────────────────────────────────────────────────────
// Unified account-creation validation — single source of truth.
// Used by every signup flow (customer / driver / merchant) so the
// same protections apply to all users:
//   • reject random / garbage data (names, phones, passwords)
//   • enforce correct, well-formed information
//   • canonical phone format (local 01XXXXXXXXX) for reliable
//     duplicate detection across roles
//   • a default avatar for every new account
// The driver & merchant pages run `is:inline` scripts and cannot
// import this module — they embed the SAME rules inline. Keep the
// two in sync if you change a rule here.
// ─────────────────────────────────────────────────────────────

import { isEgyptianMobile, normalizeEgyptianPhone } from './phone';
import { validatePassword } from './password';

export { isEgyptianMobile, normalizeEgyptianPhone, validatePassword };

// ── Full name ────────────────────────────────────────────────
// Rejects garbage: digits/symbols, single words, 1-char parts,
// a single repeated character ("اااا"), or absurd lengths.
const NAME_ALLOWED = /^[A-Za-z؀-ۿݐ-ݿ ]+$/; // Latin + Arabic letters + space

export function validateFullName(input: string): { valid: boolean; message: string } {
  const name = (input || '').trim().replace(/\s+/g, ' ');
  if (name.length < 4)  return { valid: false, message: 'أدخل الاسم الكامل (4 أحرف على الأقل).' };
  if (name.length > 50) return { valid: false, message: 'الاسم طويل جداً (50 حرفاً كحد أقصى).' };
  if (!NAME_ALLOWED.test(name))
    return { valid: false, message: 'الاسم يجب أن يحتوي على حروف فقط — بدون أرقام أو رموز.' };
  const words = name.split(' ').filter(Boolean);
  if (words.length < 2) return { valid: false, message: 'أدخل الاسم الكامل (اسمان على الأقل).' };
  if (words.some(w => w.length < 2))
    return { valid: false, message: 'كل جزء من الاسم يجب أن يكون حرفين على الأقل.' };
  if (words.some(w => /^(.)\1+$/.test(w)))
    return { valid: false, message: 'الاسم غير صالح، يرجى إدخال اسمك الحقيقي.' };
  return { valid: true, message: '' };
}

// ── Username ─────────────────────────────────────────────────
export function validateUsername(input: string): { valid: boolean; message: string } {
  const u = (input || '').trim();
  if (u.length < 3 || u.length > 20)
    return { valid: false, message: 'اسم المستخدم من 3 إلى 20 حرفاً.' };
  if (!/^[a-zA-Z0-9_.]+$/.test(u))
    return { valid: false, message: 'اسم المستخدم: أحرف إنجليزية وأرقام و _ . فقط.' };
  return { valid: true, message: '' };
}

// ── Email (optional field, validated only when present) ──────
export function validateEmail(input: string): { valid: boolean; message: string } {
  const e = (input || '').trim();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e))
    return { valid: false, message: 'يرجى إدخال بريد إلكتروني صحيح.' };
  return { valid: true, message: '' };
}

// ── National ID (Egyptian, 14 digits) ───────────────────────
// First digit = century (2=1900s, 3=2000s+), followed by a real
// YYMMDD birth date — rejects random 14-digit strings, not just
// wrong-length ones. Must match the driver/merchant rules exactly.
export function isValidEgyptianNationalId(id: string): boolean {
  if (!/^[23]\d{13}$/.test(id)) return false;
  const century = id[0] === '2' ? 1900 : 2000;
  const year  = century + parseInt(id.slice(1, 3), 10);
  const month = parseInt(id.slice(3, 5), 10);
  const day   = parseInt(id.slice(5, 7), 10);
  if (month < 1 || month > 12) return false;
  const daysInMonth = new Date(year, month, 0).getDate();
  return day >= 1 && day <= daysInMonth;
}

// Valid, non-expired date (YYYY-MM-DD, today or later).
export function isFutureDate(v: string): boolean {
  if (!v) return false;
  const d = new Date(v);
  if (isNaN(d.getTime())) return false;
  const today = new Date(); today.setHours(0, 0, 0, 0);
  return d >= today;
}

// ── Phone ────────────────────────────────────────────────────
// Canonical = local 01XXXXXXXXX. Returns '' when invalid.
export function canonicalPhone(input: string): string {
  const v = normalizeEgyptianPhone(input);
  return isEgyptianMobile(v) ? v : '';
}

// Supabase `or=` filter matching BOTH the local (01…) and legacy
// international (+201…) form so a number can't be duplicated by
// switching formats between roles.
export function phoneOrFilter(localPhone: string): string {
  const intl = '+2' + localPhone;
  return `or=(phone.eq.${encodeURIComponent(localPhone)},phone.eq.${encodeURIComponent(intl)})`;
}

// ── Default avatar ───────────────────────────────────────────
// Deterministic SVG data-URI built from the user's initials so
// every account has an image even without an upload.
const AVATAR_GRADIENTS = [
  ['#4F46E5', '#6D5DF6'], ['#16A34A', '#0EA5A0'], ['#F59E0B', '#EF4444'],
  ['#8B5CF6', '#EC4899'], ['#0EA5E9', '#22C55E'], ['#F43F5E', '#FB923C'],
];

export function defaultAvatar(name: string): string {
  const clean = (name || '؟').trim();
  const parts = clean.split(/\s+/).filter(Boolean);
  const initials = (parts[0]?.[0] || '؟') + (parts[1]?.[0] || '');
  let hash = 0;
  for (let i = 0; i < clean.length; i++) hash = (hash * 31 + clean.charCodeAt(i)) >>> 0;
  const [c1, c2] = AVATAR_GRADIENTS[hash % AVATAR_GRADIENTS.length];
  const svg =
    `<svg xmlns="http://www.w3.org/2000/svg" width="120" height="120" viewBox="0 0 120 120">` +
    `<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">` +
    `<stop offset="0" stop-color="${c1}"/><stop offset="1" stop-color="${c2}"/></linearGradient></defs>` +
    `<rect width="120" height="120" rx="60" fill="url(#g)"/>` +
    `<text x="60" y="60" dy=".36em" text-anchor="middle" fill="#fff" ` +
    `font-family="Cairo,Segoe UI,sans-serif" font-size="48" font-weight="800">${initials}</text></svg>`;
  return 'data:image/svg+xml;utf8,' + encodeURIComponent(svg);
}
