import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/password_utils.dart';
import '../../core/phone_utils.dart';
import '../../core/theme.dart';
import 'otp_auth_repository.dart';
import 'password_reset_repository.dart';

/// "نسيت كلمة المرور؟" — the same email-code flow login.astro's forgot-
/// password step already uses on the web (reset_password RPC, unaffected
/// by the Twilio billing issue since it was always email-based via
/// Resend), now reachable from every native app's login screen too.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _repo = PasswordResetRepository();
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _password2Ctrl = TextEditingController();
  bool _codeSent = false;
  bool _loading = false;
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    _passwordCtrl.dispose();
    _password2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final phone = _phoneCtrl.text.trim();
    if (!isEgyptianMobile(phone)) {
      setState(() => _error = egPhoneError);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _repo.sendResetCode(phone);
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _loading = false;
      });
    } on OtpSendFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = switch (e.reason) {
          'not_found' => context.tr('forgot_password_not_found'),
          'no_email' => context.tr('forgot_password_no_email'),
          _ => context.tr('forgot_password_send_failed'),
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.tr('forgot_password_send_failed');
      });
    }
  }

  Future<void> _reset() async {
    if (_codeCtrl.text.trim().length < 4) {
      setState(() => _error = context.tr('otp_login_code_required'));
      return;
    }
    final pwError = validatePassword(_passwordCtrl.text);
    if (pwError != null) {
      setState(() => _error = pwError);
      return;
    }
    if (_passwordCtrl.text != _password2Ctrl.text) {
      setState(() => _error = context.tr('forgot_password_mismatch'));
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ok = await _repo.resetPassword(_phoneCtrl.text.trim(), _codeCtrl.text, _passwordCtrl.text);
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _loading = false;
          _error = context.tr('forgot_password_bad_code');
        });
        return;
      }
      setState(() {
        _loading = false;
        _done = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.tr('forgot_password_send_failed');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('forgot_password_title'))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_done) ...[
                const Icon(Icons.check_circle, color: AppColors.success, size: 56),
                const SizedBox(height: 16),
                Text(
                  context.tr('forgot_password_done'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(_phoneCtrl.text.trim()),
                  child: Text(context.tr('forgot_password_back_to_login')),
                ),
              ] else ...[
                Text(
                  _codeSent ? context.tr('otp_login_enter_code_subtitle') : context.tr('otp_login_enter_phone_subtitle'),
                  style: const TextStyle(fontSize: 13, color: AppColors.textFaint, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 20),
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: Text(_error!, style: const TextStyle(color: AppColors.error)),
                  ),
                  const SizedBox(height: 16),
                ],
                if (!_codeSent) ...[
                  TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(labelText: context.tr('otp_login_phone_label'), hintText: '01XXXXXXXXX'),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _loading ? null : _sendCode,
                    child: _loading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(context.tr('otp_login_send_code_button')),
                  ),
                ] else ...[
                  Text(_phoneCtrl.text.trim(), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _codeCtrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(fontSize: 22, letterSpacing: 6, fontWeight: FontWeight.w900),
                    decoration: InputDecoration(labelText: context.tr('otp_login_code_label')),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordCtrl,
                    obscureText: true,
                    decoration: InputDecoration(labelText: context.tr('forgot_password_new_password')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password2Ctrl,
                    obscureText: true,
                    decoration: InputDecoration(labelText: context.tr('forgot_password_confirm_password')),
                  ),
                  const SizedBox(height: 6),
                  Text(passwordHint, style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _loading ? null : _reset,
                    child: _loading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(context.tr('forgot_password_submit')),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _loading ? null : () => setState(() => _codeSent = false),
                    child: Text(context.tr('otp_login_change_phone')),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
