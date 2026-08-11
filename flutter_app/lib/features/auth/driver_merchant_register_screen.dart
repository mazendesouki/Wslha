import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/flavor.dart';
import '../../core/password_utils.dart';
import '../../core/phone_utils.dart';
import '../../core/theme.dart';
import 'auth_repository.dart';

const _driverCities = ['دمياط الجديدة', 'وسط دمياط', 'رأس البر', 'كفر سعد', 'فارسكور', 'الزرقا', 'شربين'];
const _merchantCities = ['دمياط الجديدة', 'وسط دمياط', 'رأس البر', 'كفر سعد'];

/// Native "account" step of driver/merchant onboarding — name, phone,
/// password, city, and (driver only) a circular camera-captured personal
/// photo. Mirrors driver.astro's panel-0 / merchant-apply.astro's step-0
/// exactly (same fields, same account-creation RPC flow), see
/// AuthRepository.registerDriverOrMerchant(). The remaining KYC steps
/// (ID/license documents, vehicle or store details, admin review) stay
/// on the website — rebuilding all ~10 document-upload fields natively
/// is a much bigger, separate piece of work.
class DriverMerchantRegisterScreen extends StatefulWidget {
  final AppFlavor flavor; // driver | merchant
  const DriverMerchantRegisterScreen({super.key, required this.flavor});

  @override
  State<DriverMerchantRegisterScreen> createState() => _DriverMerchantRegisterScreenState();
}

class _DriverMerchantRegisterScreenState extends State<DriverMerchantRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _authRepo = AuthRepository();
  final _picker = ImagePicker();

  bool get _isDriver => widget.flavor == AppFlavor.driver;
  List<String> get _cities => _isDriver ? _driverCities : _merchantCities;
  String _city = '';

  XFile? _photo;
  String? _photoUrl;
  bool _loading = false;
  String? _error;
  String? _successPhone;

  @override
  void initState() {
    super.initState();
    _city = _cities.first;
  }

  Future<void> _capturePhoto() async {
    final shot = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85, preferredCameraDevice: CameraDevice.front);
    if (shot != null) setState(() => _photo = shot);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_passwordController.text != _confirmController.text) {
      setState(() => _error = 'كلمتا المرور غير متطابقتين.');
      return;
    }
    if (_isDriver && _photo == null) {
      setState(() => _error = 'التقط صورتك الشخصية أولاً.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await _authRepo.registerDriverOrMerchant(
      role: _isDriver ? 'driver' : 'merchant',
      name: _nameController.text.trim(),
      phone: _phoneController.text,
      password: _passwordController.text,
      city: _city,
    );

    if (!mounted) return;

    if (result.alreadyRegistered) {
      setState(() {
        _loading = false;
        _error = 'الحساب ده مسجّل بالفعل — سجّل الدخول من الشاشة الرئيسية بدل التسجيل من جديد.';
      });
      return;
    }
    if (result.error) {
      setState(() {
        _loading = false;
        _error = 'تعذّر إنشاء الحساب، تحقق من الاتصال وحاول مجدداً.';
      });
      return;
    }

    if (_isDriver && _photo != null) {
      final bytes = await File(_photo!.path).readAsBytes();
      final ext = _photo!.path.split('.').last.toLowerCase();
      _photoUrl = await _authRepo.uploadDriverPhoto(result.phone, bytes, ext.isEmpty ? 'jpg' : ext);
    }

    setState(() {
      _loading = false;
      _successPhone = result.phone;
    });
  }

  Future<void> _continueOnWeb() async {
    final base = _isDriver ? 'https://wslha.vercel.app/driver' : 'https://wslha.vercel.app/merchant-apply';
    var url = '$base?phone=${Uri.encodeComponent(_successPhone!)}'
        '&name=${Uri.encodeComponent(_nameController.text.trim())}';
    // There's no driver_applications row to attach the photo to yet (see
    // AuthRepository.registerDriverOrMerchant — every column beyond
    // id/phone/full_name/status is NOT NULL with no default, so that
    // insert can never succeed with just what this screen collects). The
    // web page picks the URL up straight from this query param instead.
    if (_photoUrl != null) url += '&photo=${Uri.encodeComponent(_photoUrl!)}';
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isDriver ? 'تسجيل سائق جديد' : 'تسجيل تاجر جديد')),
      body: SafeArea(
        child: _successPhone != null ? _buildSuccess() : _buildForm(),
      ),
    );
  }

  Widget _buildSuccess() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('✅', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            const Text(
              'تم إنشاء الحساب بنجاح',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _isDriver
                  ? 'باقي عليك رقم البطاقة، صور الوثائق، وبيانات السيارة عشان يتراجع طلبك ويتفعّل حسابك.'
                  : 'باقي عليك بيانات النشاط التجاري والوثائق عشان يتراجع طلبك ويتفعّل حسابك.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textFaint),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _continueOnWeb,
              child: const Text('📝 كمّل باقي البيانات'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('رجوع لتسجيل الدخول'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
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
            if (_isDriver) ...[
              Center(
                child: GestureDetector(
                  onTap: _capturePhoto,
                  child: CircleAvatar(
                    radius: 56,
                    backgroundColor: AppColors.primaryLight,
                    backgroundImage: _photo != null ? FileImage(File(_photo!.path)) : null,
                    child: _photo == null
                        ? const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.camera_alt, size: 28, color: AppColors.primary),
                              SizedBox(height: 4),
                              Text('صورة شخصية', style: TextStyle(fontSize: 11, color: AppColors.primary)),
                            ],
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _capturePhoto,
                  child: Text(_photo == null ? '📷 التقط صورتك الشخصية' : '📷 إعادة التقاط الصورة'),
                ),
              ),
              const SizedBox(height: 8),
            ],
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'الاسم الكامل'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'أدخل اسمك' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(labelText: 'رقم الجوال', hintText: '01xxxxxxxxx'),
              validator: (v) => isEgyptianMobile(v ?? '') ? null : egPhoneError,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'كلمة المرور', helperText: passwordHint, helperMaxLines: 3),
              validator: (v) => validatePassword(v ?? ''),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _confirmController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'تأكيد كلمة المرور'),
              validator: (v) => (v == null || v.isEmpty) ? 'أكّد كلمة المرور' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _city,
              decoration: const InputDecoration(labelText: 'المدينة'),
              items: _cities.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setState(() => _city = v ?? _city),
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
                  : const Text('التالي'),
            ),
          ],
        ),
      ),
    );
  }
}
