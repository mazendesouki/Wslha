import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/password_utils.dart';
import '../../core/phone_utils.dart';
import '../../core/registration_validation.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import 'auth_repository.dart';

enum _Avail { idle, checking, ok, taken }

/// Ported from src/pages/register.astro's 3-step wizard (identity → contact
/// → security) — the Flutter version used to be a flat 4-field form (name/
/// phone/password/confirm) that fell behind the website's real signup
/// requirements (username, national ID + expiry, email, city, live
/// availability checks). AuthRepository.register()/fieldExists() already
/// supported all of this server-side; only this screen needed catching up.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _authRepo = AuthRepository();

  final _nameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _nationalIdCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  DateTime? _nationalIdExpiry;
  String? _city;

  int _step = 1;
  static const _totalSteps = 3;
  bool _loading = false;
  String? _error;

  _Avail _usernameAvail = _Avail.idle;
  _Avail _phoneAvail = _Avail.idle;
  _Avail _nationalIdAvail = _Avail.idle;
  _Avail _emailAvail = _Avail.idle;

  Timer? _usernameDebounce;
  Timer? _phoneDebounce;
  Timer? _nationalIdDebounce;
  Timer? _emailDebounce;

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _phoneDebounce?.cancel();
    _nationalIdDebounce?.cancel();
    _emailDebounce?.cancel();
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    _phoneCtrl.dispose();
    _nationalIdCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkUsername() async {
    _usernameDebounce?.cancel();
    final v = _usernameCtrl.text.trim();
    if (v.length < 3) {
      setState(() => _usernameAvail = _Avail.idle);
      return;
    }
    if (!validateUsername(v).valid) {
      setState(() => _usernameAvail = _Avail.taken);
      return;
    }
    setState(() => _usernameAvail = _Avail.checking);
    _usernameDebounce = Timer(const Duration(milliseconds: 600), () async {
      final exists = await _authRepo.fieldExists('username', v);
      if (!mounted) return;
      setState(() => _usernameAvail = exists ? _Avail.taken : _Avail.ok);
    });
  }

  Future<void> _checkPhone() async {
    _phoneDebounce?.cancel();
    final v = _phoneCtrl.text.trim();
    if (v.isEmpty) {
      setState(() => _phoneAvail = _Avail.idle);
      return;
    }
    if (!isEgyptianMobile(v)) {
      setState(() => _phoneAvail = _Avail.taken);
      return;
    }
    setState(() => _phoneAvail = _Avail.checking);
    _phoneDebounce = Timer(const Duration(milliseconds: 600), () async {
      final exists = await _authRepo.fieldExists('phone', normalizeEgyptianPhone(v));
      if (!mounted) return;
      setState(() => _phoneAvail = exists ? _Avail.taken : _Avail.ok);
    });
  }

  Future<void> _checkNationalId() async {
    _nationalIdDebounce?.cancel();
    final v = _nationalIdCtrl.text.trim();
    if (v.isEmpty) {
      setState(() => _nationalIdAvail = _Avail.idle);
      return;
    }
    if (!isValidEgyptianNationalId(v)) {
      setState(() => _nationalIdAvail = _Avail.taken);
      return;
    }
    setState(() => _nationalIdAvail = _Avail.checking);
    _nationalIdDebounce = Timer(const Duration(milliseconds: 600), () async {
      final exists = await _authRepo.fieldExists('national_id', v);
      if (!mounted) return;
      setState(() => _nationalIdAvail = exists ? _Avail.taken : _Avail.ok);
    });
  }

  Future<void> _checkEmail() async {
    _emailDebounce?.cancel();
    final v = _emailCtrl.text.trim();
    if (v.isEmpty) {
      setState(() => _emailAvail = _Avail.idle);
      return;
    }
    if (!validateEmail(v).valid) {
      setState(() => _emailAvail = _Avail.taken);
      return;
    }
    setState(() => _emailAvail = _Avail.checking);
    _emailDebounce = Timer(const Duration(milliseconds: 600), () async {
      final exists = await _authRepo.fieldExists('email', v.toLowerCase());
      if (!mounted) return;
      setState(() => _emailAvail = exists ? _Avail.taken : _Avail.ok);
    });
  }

  // Availability checks below only re-validate FORMAT synchronously (no
  // staleness risk) — they deliberately don't gate on _xAvail == taken,
  // since that's set by a 600ms-debounced async check and can still read
  // stale from a moment ago (e.g. an incomplete national ID) even after the
  // field is now valid and unused. _Avail stays purely a live UI hint
  // (spinner/check/✗ icon); the real, fresh, authoritative duplicate check
  // happens in _submit()'s pre-insert fieldExists() calls.
  bool _validateStep1() {
    final nm = validateFullName(_nameCtrl.text);
    if (!nm.valid) return _fail(nm.message);
    if (!validateUsername(_usernameCtrl.text).valid) {
      return _fail('اسم المستخدم: أحرف إنجليزية وأرقام و _ . فقط (3-20 حرف).');
    }
    if (!isEgyptianMobile(_phoneCtrl.text.trim())) return _fail(egPhoneError);
    final natId = _nationalIdCtrl.text.trim();
    if (!isValidEgyptianNationalId(natId)) return _fail('رقم قومي غير صحيح — لازم يكون 14 رقم ويبدأ بـ 2 أو 3.');
    if (!isFutureDateValue(_nationalIdExpiry)) return _fail('البطاقة منتهية — أدخل تاريخاً سارياً لانتهاء البطاقة.');
    return true;
  }

  bool _validateStep2() {
    if (!validateEmail(_emailCtrl.text).valid) return _fail('يرجى إدخال بريد إلكتروني صحيح.');
    if (_city == null) return _fail('يرجى اختيار المدينة.');
    return true;
  }

  bool _fail(String msg) {
    setState(() => _error = msg);
    return false;
  }

  void _goNext() {
    final ok = _step == 1 ? _validateStep1() : _validateStep2();
    if (!ok) return;
    setState(() {
      _error = null;
      _step = (_step + 1).clamp(1, _totalSteps);
    });
  }

  void _goBack() {
    setState(() {
      _error = null;
      _step = (_step - 1).clamp(1, _totalSteps);
    });
  }

  Future<void> _pickNationalIdExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _nationalIdExpiry ?? now.add(const Duration(days: 365)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 20)),
    );
    if (picked != null) setState(() => _nationalIdExpiry = picked);
  }

  Future<void> _submit() async {
    if (_passwordCtrl.text != _confirmCtrl.text) {
      setState(() => _error = 'كلمتا المرور غير متطابقتين.');
      return;
    }
    final pwError = validatePassword(_passwordCtrl.text);
    if (pwError != null) {
      setState(() => _error = pwError);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final phone = normalizeEgyptianPhone(_phoneCtrl.text);
    final natId = _nationalIdCtrl.text.trim();
    final email = _emailCtrl.text.trim().toLowerCase();
    final username = _usernameCtrl.text.trim();

    // Final server-side check right before insert — same last-line-of-
    // defense pattern register.astro uses (debounced live checks above can
    // go stale between typing and submit).
    final results = await Future.wait([
      _authRepo.fieldExists('phone', phone),
      _authRepo.fieldExists('national_id', natId),
      _authRepo.fieldExists('email', email),
      _authRepo.fieldExists('username', username),
    ]);
    if (!mounted) return;
    if (results[0]) return _stopWith('هذا الرقم مسجّل بالفعل — سجّل الدخول بدلاً من ذلك.', step: 1);
    if (results[1]) return _stopWith('هذا الرقم القومي مسجّل بالفعل.', step: 1);
    if (results[2]) return _stopWith('هذا البريد الإلكتروني مسجّل بالفعل.', step: 2);
    if (results[3]) return _stopWith('اسم المستخدم محجوز، جرّب اسماً آخر.', step: 1);

    final failReason = await _authRepo.register(
      name: _nameCtrl.text.trim(),
      phone: phone,
      password: _passwordCtrl.text,
      username: username,
      email: email,
      city: _city,
      nationalId: natId,
      nationalIdExpiry: _nationalIdExpiry?.toIso8601String().substring(0, 10),
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (failReason != null) {
      setState(() => _error = failReason);
      return;
    }

    await SessionStore.save(UserSession(
      name: _nameCtrl.text.trim(),
      phone: phone,
      role: 'customer',
      city: _city,
      loginAt: DateTime.now().toIso8601String(),
    ));
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
  }

  void _stopWith(String message, {required int step}) {
    setState(() {
      _loading = false;
      _error = message;
      _step = step;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('حساب جديد — الخطوة $_step من $_totalSteps')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StepIndicator(step: _step, total: _totalSteps),
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
              if (_step == 1) _buildStep1(),
              if (_step == 2) _buildStep2(),
              if (_step == 3) _buildStep3(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('الخطوة ١ — هويتك', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: AppColors.primary)),
        const SizedBox(height: 4),
        const Text('عرّفنا بنفسك واختر اسم مستخدم مميّز', style: TextStyle(fontSize: 12, color: AppColors.textFaint)),
        const SizedBox(height: 16),
        TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'الاسم بالكامل')),
        const SizedBox(height: 16),
        TextField(
          controller: _usernameCtrl,
          textDirection: TextDirection.ltr,
          onChanged: (_) => _checkUsername(),
          decoration: InputDecoration(
            labelText: 'اسم المستخدم',
            helperText: 'أحرف إنجليزية وأرقام و _ . فقط (3-20 حرف)',
            suffixIcon: _availIcon(_usernameAvail),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          textDirection: TextDirection.ltr,
          onChanged: (_) => _checkPhone(),
          decoration: InputDecoration(labelText: 'رقم الجوال', hintText: '01xxxxxxxxx', suffixIcon: _availIcon(_phoneAvail)),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _nationalIdCtrl,
          keyboardType: TextInputType.number,
          textDirection: TextDirection.ltr,
          maxLength: 14,
          onChanged: (_) => _checkNationalId(),
          decoration: InputDecoration(
            labelText: 'الرقم القومي',
            helperText: '14 رقم ويبدأ بـ 2 أو 3',
            suffixIcon: _availIcon(_nationalIdAvail),
          ),
        ),
        const SizedBox(height: 16),
        InkWell(
          onTap: _pickNationalIdExpiry,
          child: InputDecorator(
            decoration: const InputDecoration(labelText: 'تاريخ انتهاء البطاقة'),
            child: Text(
              _nationalIdExpiry == null ? 'اختر التاريخ' : _nationalIdExpiry!.toIso8601String().substring(0, 10),
              style: TextStyle(color: _nationalIdExpiry == null ? AppColors.textFaint : Colors.black87),
            ),
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(onPressed: _goNext, child: const Text('التالي ←')),
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('الخطوة ٢ — بيانات التواصل', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: AppColors.primary)),
        const SizedBox(height: 4),
        const Text('بريدك ومدينتك لخدمة توصيل أدق', style: TextStyle(fontSize: 12, color: AppColors.textFaint)),
        const SizedBox(height: 16),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          textDirection: TextDirection.ltr,
          onChanged: (_) => _checkEmail(),
          decoration: InputDecoration(labelText: 'البريد الإلكتروني', hintText: 'example@gmail.com', suffixIcon: _availIcon(_emailAvail)),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _city,
          decoration: const InputDecoration(labelText: 'المدينة'),
          items: egyptianCities.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
          onChanged: (v) => setState(() => _city = v),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(child: OutlinedButton(onPressed: _goBack, child: const Text('→ السابق'))),
            const SizedBox(width: 12),
            Expanded(child: ElevatedButton(onPressed: _goNext, child: const Text('التالي ←'))),
          ],
        ),
      ],
    );
  }

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('الخطوة ٣ — الأمان', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: AppColors.primary)),
        const SizedBox(height: 4),
        const Text('اختر كلمة مرور قوية لحماية حسابك', style: TextStyle(fontSize: 12, color: AppColors.textFaint)),
        const SizedBox(height: 16),
        TextField(
          controller: _passwordCtrl,
          obscureText: true,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'كلمة المرور'),
        ),
        const SizedBox(height: 8),
        _PasswordRules(password: _passwordCtrl.text),
        const SizedBox(height: 16),
        TextField(
          controller: _confirmCtrl,
          obscureText: true,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'تأكيد كلمة المرور'),
        ),
        if (_confirmCtrl.text.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            _confirmCtrl.text == _passwordCtrl.text ? '✓ كلمتا المرور متطابقتان' : '✗ كلمتا المرور غير متطابقتين',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _confirmCtrl.text == _passwordCtrl.text ? AppColors.success : AppColors.error),
          ),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(child: OutlinedButton(onPressed: _goBack, child: const Text('→ السابق'))),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('إنشاء الحساب ✓'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget? _availIcon(_Avail state) {
    switch (state) {
      case _Avail.idle:
        return null;
      case _Avail.checking:
        return const Padding(padding: EdgeInsets.all(14), child: SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2)));
      case _Avail.ok:
        return const Icon(Icons.check_circle, color: AppColors.success);
      case _Avail.taken:
        return const Icon(Icons.error, color: AppColors.error);
    }
  }
}

class _StepIndicator extends StatelessWidget {
  final int step;
  final int total;
  const _StepIndicator({required this.step, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 1; i <= total; i++) ...[
          CircleAvatar(
            radius: 15,
            backgroundColor: i <= step ? AppColors.primary : AppColors.primaryLight,
            child: Text(
              i < step ? '✓' : '$i',
              style: TextStyle(color: i <= step ? Colors.white : AppColors.primary, fontWeight: FontWeight.w900, fontSize: 12),
            ),
          ),
          if (i != total)
            Expanded(
              child: Container(height: 3, color: i < step ? AppColors.primary : AppColors.primaryLight),
            ),
        ],
      ],
    );
  }
}

class _PasswordRules extends StatelessWidget {
  final String password;
  const _PasswordRules({required this.password});

  @override
  Widget build(BuildContext context) {
    final rules = [
      ('8 أحرف على الأقل', password.length >= 8),
      ('حرف كبير (A-Z)', RegExp(r'[A-Z]').hasMatch(password)),
      ('حرف صغير (a-z)', RegExp(r'[a-z]').hasMatch(password)),
      ('رقم واحد', RegExp(r'[0-9]').hasMatch(password)),
      ('بدون رموز أو مسافات', password.isNotEmpty && RegExp(r'^[A-Za-z0-9]+$').hasMatch(password)),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: rules
          .map((r) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(r.$2 ? Icons.check_circle : Icons.circle_outlined, size: 14, color: r.$2 ? AppColors.success : AppColors.textFaint),
                  const SizedBox(width: 4),
                  Text(r.$1, style: TextStyle(fontSize: 11, color: r.$2 ? AppColors.success : AppColors.textFaint)),
                ],
              ))
          .toList(),
    );
  }
}
