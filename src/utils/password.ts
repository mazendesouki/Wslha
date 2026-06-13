// Password policy: at least 8 chars, 1 uppercase, 1 lowercase, alphanumeric only (no spaces/symbols)
const ONLY_ALPHANUMERIC = /^[A-Za-z0-9]+$/;
const HAS_UPPER        = /[A-Z]/;
const HAS_LOWER        = /[a-z]/;
const HAS_DIGIT        = /[0-9]/;
const MIN_LENGTH       = 8;

export interface PasswordError {
  valid: false;
  message: string;
}
export interface PasswordOk {
  valid: true;
}
export type PasswordResult = PasswordOk | PasswordError;

export function validatePassword(pw: string): PasswordResult {
  if (pw.length < MIN_LENGTH)
    return { valid: false, message: `كلمة المرور يجب أن تكون ${MIN_LENGTH} أحرف على الأقل.` };
  if (!ONLY_ALPHANUMERIC.test(pw))
    return { valid: false, message: 'لا يُسمح بالمسافات أو الرموز — استخدم حروفاً وأرقاماً فقط.' };
  if (!HAS_UPPER.test(pw))
    return { valid: false, message: 'يجب أن تحتوي كلمة المرور على حرف كبير واحد على الأقل (A-Z).' };
  if (!HAS_LOWER.test(pw))
    return { valid: false, message: 'يجب أن تحتوي كلمة المرور على حرف صغير واحد على الأقل (a-z).' };
  if (!HAS_DIGIT.test(pw))
    return { valid: false, message: 'يجب أن تحتوي كلمة المرور على رقم واحد على الأقل.' };
  return { valid: true };
}

export const PASSWORD_HINT =
  'كلمة المرور: 8 أحرف على الأقل، تحتوي على حرف كبير وحرف صغير ورقم، بدون مسافات أو رموز.';
