// Ported 1:1 from src/utils/password.ts.

final RegExp _onlyAlphanumeric = RegExp(r'^[A-Za-z0-9]+$');
final RegExp _hasUpper = RegExp(r'[A-Z]');
final RegExp _hasLower = RegExp(r'[a-z]');
final RegExp _hasDigit = RegExp(r'[0-9]');
const int _minLength = 8;

const String passwordHint =
    'كلمة المرور: 8 أحرف على الأقل، تحتوي على حرف كبير وحرف صغير ورقم، بدون مسافات أو رموز.';

/// Returns null when valid, or an Arabic error message otherwise.
String? validatePassword(String pw) {
  if (pw.length < _minLength) {
    return 'كلمة المرور يجب أن تكون $_minLength أحرف على الأقل.';
  }
  if (!_onlyAlphanumeric.hasMatch(pw)) {
    return 'لا يُسمح بالمسافات أو الرموز — استخدم حروفاً وأرقاماً فقط.';
  }
  if (!_hasUpper.hasMatch(pw)) {
    return 'يجب أن تحتوي كلمة المرور على حرف كبير واحد على الأقل (A-Z).';
  }
  if (!_hasLower.hasMatch(pw)) {
    return 'يجب أن تحتوي كلمة المرور على حرف صغير واحد على الأقل (a-z).';
  }
  if (!_hasDigit.hasMatch(pw)) {
    return 'يجب أن تحتوي كلمة المرور على رقم واحد على الأقل.';
  }
  return null;
}
