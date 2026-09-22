import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/flavor.dart';
import '../../core/i18n.dart';
import '../../core/phone_utils.dart';
import '../../core/push.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import 'otp_auth_repository.dart';

/// Phase 1 of the real-auth migration — real OTP login via Supabase Auth
/// (Twilio Verify), reachable as an alternative to the existing password
/// login rather than replacing it yet (see otp_auth_repository.dart).
class OtpLoginScreen extends StatefulWidget {
  final FlavorConfig config;
  const OtpLoginScreen({super.key, required this.config});

  @override
  State<OtpLoginScreen> createState() => _OtpLoginScreenState();
}

class _OtpLoginScreenState extends State<OtpLoginScreen> {
  final _repo = OtpAuthRepository();
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _codeSent = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    _nameCtrl.dispose();
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
      await _repo.sendCode(phone);
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.tr('otp_login_send_failed');
      });
    }
  }

  Future<void> _verify() async {
    if (_codeCtrl.text.trim().length < 4) {
      setState(() => _error = context.tr('otp_login_code_required'));
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = await _repo.verifyCode(_phoneCtrl.text.trim(), _codeCtrl.text, name: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim());
      if (!mounted) return;
      if (session.role != widget.config.allowedRole) {
        setState(() {
          _loading = false;
          _error = widget.config.wrongRoleMessage;
        });
        return;
      }
      await SessionStore.save(session, remember: true);
      unawaited(PushRegistrar.registerForSession(session));
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.tr('otp_login_verify_failed');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('otp_login_title'))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                const SizedBox(height: 12),
                TextField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(labelText: context.tr('otp_login_name_label_optional')),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _loading ? null : _verify,
                  child: _loading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(context.tr('otp_login_verify_button')),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _loading ? null : () => setState(() => _codeSent = false),
                  child: Text(context.tr('otp_login_change_phone')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
