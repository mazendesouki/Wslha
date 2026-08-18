import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/flavor.dart';
import '../../core/push.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import 'auth_repository.dart';
import 'driver_merchant_register_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  final FlavorConfig config;
  const LoginScreen({super.key, required this.config});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _authRepo = AuthRepository();

  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await _authRepo.login(_phoneController.text, _passwordController.text);

    if (!mounted) return;
    setState(() => _loading = false);

    switch (result) {
      case LoginSuccess(:final session):
        // This build only accepts one role (customer/driver/merchant app —
        // separate installs, not one app that branches after login).
        if (session.role != widget.config.allowedRole) {
          setState(() => _error = widget.config.wrongRoleMessage);
          return;
        }
        await SessionStore.save(session);
        unawaited(PushRegistrar.registerForSession(session)); // fire-and-forget
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
      case LoginFailure(:final reason):
        setState(() {
          _error = switch (reason) {
            'not_found' => 'لا يوجد حساب بهذا الرقم.',
            'bad_password' => 'كلمة المرور غير صحيحة.',
            _ => 'تعذّر الاتصال، تحقق من الإنترنت وحاول مجدداً.',
          };
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCustomerApp = widget.config.flavor == AppFlavor.customer;

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF9),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Brand header — same mark as the app icon/splash, so the
              // login screen reads as a continuation of the same moment
              // instead of a plain form bolted onto the app.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 36, 24, 40),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primaryDark, AppColors.primary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.only(bottomLeft: Radius.circular(32), bottomRight: Radius.circular(32)),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 6))],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.asset('assets/branding/logo.png', fit: BoxFit.cover),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.config.appTitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'تسجيل الدخول',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Colors.white70, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
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
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(labelText: 'رقم الجوال', hintText: '01xxxxxxxxx'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'أدخل رقم الجوال' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'كلمة المرور'),
                    validator: (v) => (v == null || v.isEmpty) ? 'أدخل كلمة المرور' : null,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('دخول'),
                  ),
                  const SizedBox(height: 16),
                  if (isCustomerApp)
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const RegisterScreen()),
                      ),
                      child: const Text('ليس لديك حساب؟ سجّل الآن'),
                    )
                  else
                    // Account creation (name/phone/password/city, +
                    // personal photo for drivers) happens natively —
                    // DriverMerchantRegisterScreen. The rest of the KYC
                    // (documents, vehicle/store info, admin review) still
                    // only exists on the website, which that screen links
                    // out to once the account step is done.
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => DriverMerchantRegisterScreen(flavor: widget.config.flavor),
                          ),
                        ),
                        child: Text(
                          widget.config.flavor == AppFlavor.driver
                              ? '📝 سجّل كسائق الآن'
                              : '📝 سجّل كتاجر الآن',
                        ),
                      ),
                    ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
