import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/phone_utils.dart';
import '../../core/pricing_settings.dart';
import '../../core/session.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../account/account_repository.dart';
import '../ratings/ratings_list_screen.dart';
import '../ratings/ratings_repository.dart';
import '../referrals/referral_screen.dart';
import 'driver_repository.dart';

/// The driver's own profile tab — replaces the generic AccountScreen for
/// the driver flavor only (customer/merchant still use AccountScreen).
/// Pulls together things that previously had nowhere to show up: the
/// customer's ratings after a completed ride (bug report — the data was
/// always being saved, just never displayed anywhere in the driver app),
/// a level badge driven by rating count, the driver's own uploadable
/// profile photo (new — accounts had no avatar column before), the car
/// photo/model from driver_applications (existing KYC data, never surfaced
/// post-approval), and the trip-count breakdown by service type.
class DriverProfileScreen extends StatefulWidget {
  final UserSession session;
  const DriverProfileScreen({super.key, required this.session});

  @override
  State<DriverProfileScreen> createState() => DriverProfileScreenState();
}

/// Public (not `_`-prefixed) so DriverHomeShell can hold a
/// `GlobalKey<DriverProfileScreenState>` and call refresh() when the "حسابي"
/// tab is (re)selected — this screen sits inside an IndexedStack, so
/// switching tabs back to it does NOT re-run initState()/_load(), which is
/// why the trip totals/ratings looked frozen even right after finishing a
/// ride (same bug/fix as the customer account screen).
class DriverProfileScreenState extends State<DriverProfileScreen> {
  final _accountRepo = AccountRepository();
  final _driverRepo = DriverRepository();
  final _picker = ImagePicker();

  Map<String, dynamic>? _account;
  Map<String, dynamic>? _vehicle;
  Map<String, dynamic> _stats = {};
  (int, int) _progress = (0, 0);
  RatingSummary _ratingSummary = RatingSummary(0, 0);
  List<Map<String, dynamic>> _reviews = [];
  bool _loading = true;
  bool _uploadingAvatar = false;

  // Ratings arrive on THIS device from a rating another party (the
  // customer) submits on THEIRS — a tab-reselect refresh on the driver's
  // own phone can never see that. These two live streams (db/security-53
  // adds `ratings` to the realtime publication) are what actually makes a
  // brand-new customer rating show up here without the driver manually
  // reopening the app, right after the ride ends.
  List<Map<String, dynamic>> _ratingsLocal = [];
  List<Map<String, dynamic>> _ratingsIntl = [];
  final List<StreamSubscription> _ratingSubs = [];

  @override
  void initState() {
    super.initState();
    _load();
    final local = normalizeEgyptianPhone(widget.session.phone);
    final intl = toIntlEgyptianPhone(widget.session.phone);
    _ratingSubs.add(sb.from('ratings').stream(primaryKey: ['id']).eq('driver_phone', local).listen((rows) {
      if (!mounted) return;
      setState(() => _ratingsLocal = rows);
      _recomputeRatings();
    }));
    _ratingSubs.add(sb.from('ratings').stream(primaryKey: ['id']).eq('driver_phone', intl).listen((rows) {
      if (!mounted) return;
      setState(() => _ratingsIntl = rows);
      _recomputeRatings();
    }));
  }

  @override
  void dispose() {
    for (final s in _ratingSubs) {
      s.cancel();
    }
    super.dispose();
  }

  void _recomputeRatings() {
    final rows = [..._ratingsLocal, ..._ratingsIntl].where((r) => r['rated_by'] == 'customer').toList()
      ..sort((a, b) => (b['created_at'] as String? ?? '').compareTo(a['created_at'] as String? ?? ''));
    final nums = rows.map((r) => (r['rating'] as num?)?.toDouble()).whereType<double>().toList();
    if (!mounted) return;
    setState(() {
      _ratingSummary = nums.isEmpty ? RatingSummary(0, 0) : RatingSummary(nums.reduce((a, b) => a + b) / nums.length, nums.length);
      _reviews = rows.take(20).toList();
    });
  }

  /// Called by DriverHomeShell when the "حسابي" tab is selected again.
  Future<void> refresh() => _load();

  Future<void> _load() async {
    final phone = widget.session.phone;
    // Each call is independently defensive — the profile as a whole
    // (photo, name, ratings) shouldn't go blank just because one section
    // (e.g. vehicle info, if a driver_applications column is missing on
    // an older row) throws. A diagnostic error banner briefly lived here to
    // chase down why trip totals/ratings read as permanently empty — root
    // cause was two real DB bugs (see db/security-33-fix-trip-stats-and-tags.sql):
    // get_driver_trip_stats() compared a text column to a uuid one without a
    // cast, and ratings.tags didn't exist yet on this project (security-24
    // had never actually been run here) — both now fixed server-side.
    // Ratings themselves are no longer fetched here — see the live
    // _ratingsLocal/_ratingsIntl streams started in initState().
    final results = await Future.wait([
      _accountRepo.lookupAccount(phone).catchError((_) => null),
      _driverRepo.fetchVehicleInfo(phone).catchError((_) => null),
      _driverRepo.fetchTripStats(phone).catchError((_) => <String, dynamic>{}),
      _driverRepo.fetchProgress(phone).catchError((_) => (0, 0)),
    ]);
    if (!mounted) return;
    setState(() {
      _account = results[0] as Map<String, dynamic>?;
      _vehicle = results[1] as Map<String, dynamic>?;
      _stats = results[2] as Map<String, dynamic>;
      _progress = results[3] as (int, int);
      _loading = false;
    });
  }

  Future<ImageSource?> _chooseImageSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('التقاط صورة بالكاميرا'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('اختيار من معرض الصور'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAvatar() async {
    final source = await _chooseImageSource();
    if (source == null) return;
    try {
      final shot = await _picker.pickImage(source: source, imageQuality: 85, maxWidth: 800);
      if (shot == null) return;
      setState(() => _uploadingAvatar = true);
      final bytes = await File(shot.path).readAsBytes();
      final ext = shot.path.split('.').last.toLowerCase();
      final url = await _accountRepo.uploadAvatar(widget.session.phone, bytes, ext.isEmpty ? 'jpg' : ext);
      if (!mounted) return;
      if (url == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذّر رفع الصورة، حاول تاني')));
        return;
      }
      await _load();
    } catch (e) {
      // Without this, an exception mid-upload (e.g. the camera capture
      // never producing a readable file) left _uploadingAvatar stuck true
      // forever — an endless spinner with no error shown, since nothing
      // downstream of the throw point ever ran.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذّر التقاط/رفع الصورة: $e')));
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _editProfile() async {
    final nameCtrl = TextEditingController(text: _account?['name'] as String? ?? widget.session.name);
    final cityCtrl = TextEditingController(text: _account?['city'] as String? ?? widget.session.city ?? '');
    final originalEmail = _account?['email'] as String? ?? '';
    final emailCtrl = TextEditingController(text: originalEmail);
    final passwordCtrl = TextEditingController();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
        ),
        child: StatefulBuilder(
          builder: (sheetContext, setSheetState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('تعديل بياناتي', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
              const SizedBox(height: 16),
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'الاسم')),
              const SizedBox(height: 12),
              TextField(controller: cityCtrl, decoration: const InputDecoration(labelText: 'المدينة')),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'البريد الإلكتروني'),
                onChanged: (_) => setSheetState(() {}),
              ),
              // Changing the email needs a password check (update_account_email,
              // security-47) — an unverified email change would let someone
              // hijack the account via "forgot password".
              if (emailCtrl.text.trim().toLowerCase() != originalEmail.trim().toLowerCase()) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: passwordCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'كلمة مرور حسابك (لتأكيد تغيير البريد)'),
                ),
              ],
              const SizedBox(height: 20),
              ElevatedButton(onPressed: () => Navigator.of(sheetContext).pop(true), child: const Text('حفظ')),
            ],
          ),
        ),
      ),
    );
    if (saved != true) return;

    final newEmail = emailCtrl.text.trim();
    if (newEmail.toLowerCase() != originalEmail.trim().toLowerCase()) {
      if (passwordCtrl.text.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل كلمة مرور حسابك لتأكيد تغيير البريد الإلكتروني')));
        return;
      }
      final ok = await _accountRepo.updateEmail(widget.session.phone, passwordCtrl.text, newEmail);
      if (!ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('كلمة المرور غير صحيحة — لم يتم تغيير البريد الإلكتروني')));
        return;
      }
    }
    await _accountRepo.updateProfile(
      widget.session.phone,
      name: nameCtrl.text.trim(),
      city: cityCtrl.text.trim(),
    );
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ التعديلات')));
  }

  Future<void> _logout() async {
    await SessionStore.clear();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
  }

  int _typeTrips(String rideType) {
    final list = (_stats['by_type'] as List?) ?? [];
    for (final row in list) {
      if (row['ride_type'] == rideType) return ((row['trips'] as num?) ?? 0).toInt();
    }
    return 0;
  }

  int get _storeOrderTrips => ((_stats['store_orders']?['trips'] as num?) ?? 0).toInt();

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final name = _account?['name'] as String? ?? widget.session.name;
    final email = _account?['email'] as String?;
    final city = _account?['city'] as String? ?? widget.session.city;
    final avatarUrl = _account?['avatar_url'] as String?;
    final level = levelForRatingCount(_ratingSummary.count);
    final next = nextLevelFor(_ratingSummary.count);

    return Scaffold(
      appBar: AppBar(title: const Text('ملفي الشخصي')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildHeader(name, avatarUrl, level, next),
            const SizedBox(height: 16),
            _buildGoalCard(),
            const SizedBox(height: 16),
            _buildRatingCard(),
            const SizedBox(height: 16),
            _buildTripStats(),
            if (_vehicle != null) ...[
              const SizedBox(height: 16),
              _buildVehicleCard(),
            ],
            const SizedBox(height: 16),
            _buildInfoCard(city, email),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _editProfile,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('تعديل بياناتي'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReferralScreen())),
              icon: const Icon(Icons.card_giftcard_outlined),
              label: const Text('كود الدعوة'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout, color: AppColors.error),
              label: const Text('تسجيل الخروج', style: TextStyle(color: AppColors.error)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.error),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(String name, String? avatarUrl, DriverLevel level, DriverLevel? next) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.primary, AppColors.primaryDark]),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 38,
                backgroundColor: Colors.white24,
                backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                child: avatarUrl == null ? const Text('👤', style: TextStyle(fontSize: 32)) : null,
              ),
              Positioned(
                bottom: -2,
                left: -2,
                child: GestureDetector(
                  onTap: _uploadingAvatar ? null : _pickAvatar,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                    child: _uploadingAvatar
                        ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
              if (_ratingSummary.isTrusted) ...[
                const SizedBox(width: 6),
                const Icon(Icons.verified, color: Color(0xFFFFD54F), size: 18),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(widget.session.phone, style: const TextStyle(color: Colors.white70, fontSize: 12), textDirection: TextDirection.ltr),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(999)),
            child: Text(
              '${level.emoji} ${level.label}',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900),
            ),
          ),
          if (next != null) ...[
            const SizedBox(height: 8),
            Text(
              'باقي ${next.minCount - _ratingSummary.count} تقييم للوصول لمستوى ${next.emoji} ${next.label}',
              style: const TextStyle(color: Colors.white60, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRatingCard() {
    final s = _ratingSummary;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => RatingsListScreen(
            title: '🌟 تقييمات العملاء',
            summary: s,
            reviews: _reviews,
            countLabel: 'تقييم من العملاء',
            emptyMessage: 'لسه مفيش تقييمات — هتظهر هنا أول ما عميل يقيّمك بعد رحلة',
          ),
        )),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: const [
            BoxShadow(color: Color(0x11000000), blurRadius: 8, offset: Offset(0, 2)),
          ]),
          child: Row(
            children: [
              Text(
                s.isNew ? '🆕' : (s.avg >= 4.5 ? '😍' : s.avg >= 3.5 ? '🙂' : s.avg >= 2.5 ? '😐' : '🙁'),
                style: const TextStyle(fontSize: 32),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.isNew ? 'لسه ما وصلكش تقييم' : s.avg.toStringAsFixed(1),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                    Text(
                      s.isNew ? 'التقييمات هتظهر هنا بعد أول رحلة' : '${s.count} تقييم من العملاء',
                      style: const TextStyle(fontSize: 12, color: AppColors.textFaint),
                    ),
                  ],
                ),
              ),
              if (s.isTrusted)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
                  child: const Text('✅ سائق موثوق', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.success)),
                ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_left, color: AppColors.textFaint),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGoalCard() {
    final (today, week) = _progress;
    final dailyGoal = PricingSettings.driverDailyGoal;
    final weeklyGoal = PricingSettings.driverWeeklyGoal;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: const [
        BoxShadow(color: Color(0x11000000), blurRadius: 8, offset: Offset(0, 2)),
      ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🎯 هدفك', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
          const SizedBox(height: 12),
          _goalRow('اليوم', today, dailyGoal),
          const SizedBox(height: 12),
          _goalRow('الأسبوع', week, weeklyGoal),
        ],
      ),
    );
  }

  Widget _goalRow(String label, int done, int goal) {
    final ratio = goal > 0 ? (done / goal).clamp(0.0, 1.0) : 0.0;
    final reached = done >= goal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textFaint)),
            Text(
              reached ? '🎉 وصلت للهدف!' : '$done / $goal رحلة',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: reached ? AppColors.success : AppColors.primary),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 8,
            backgroundColor: const Color(0xFFE9ECEB),
            valueColor: AlwaysStoppedAnimation(reached ? AppColors.success : AppColors.primary),
          ),
        ),
      ],
    );
  }

  Widget _buildTripStats() {
    final overall = (_stats['overall'] as Map?) ?? {};
    final totalTrips = ((overall['trips'] as num?) ?? 0).toInt();
    final tiles = [
      ('🏙️', 'داخل المدينة', _typeTrips('local')),
      ('🛣️', 'خارج المحافظة', _typeTrips('external')),
      ('✈️', 'رحلات مطار', _typeTrips('airport')),
      ('🛍️', 'طلبات متاجر', _storeOrderTrips),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: const [
        BoxShadow(color: Color(0x11000000), blurRadius: 8, offset: Offset(0, 2)),
      ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('إجمالي رحلاتي', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
              Text('${totalTrips + _storeOrderTrips}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.2,
            children: tiles.map((t) => _statTile(t.$1, t.$2, t.$3)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _statTile(String emoji, String label, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$count', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.primaryDark)),
                Text(label, style: const TextStyle(fontSize: 10, color: AppColors.primaryDark), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleCard() {
    final v = _vehicle!;
    final photo = (v['vehicle_front_url'] as String?) ?? (v['plate_photo_url'] as String?);
    // vehicle_year/vehicle_reg_number are numeric in some driver_applications
    // rows and text in others (depending on when the row was created) — use
    // toString() instead of an `as String?` cast, which threw
    // "type 'int' is not a subtype of type 'String?'" and blanked this whole
    // tab (an uncaught exception inside build() renders as an empty grey
    // box in release mode, not a crash dialog).
    final regNumber = v['vehicle_reg_number']?.toString();
    final year = v['vehicle_year']?.toString();
    final model = v['vehicle_model']?.toString();
    final color = v['vehicle_color']?.toString();
    final hasAc = v['has_ac'] == true;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: const [
        BoxShadow(color: Color(0x11000000), blurRadius: 8, offset: Offset(0, 2)),
      ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: photo != null
                    ? Image.network(photo, width: 72, height: 72, fit: BoxFit.cover)
                    : Container(
                        width: 72,
                        height: 72,
                        color: AppColors.primaryLight,
                        child: const Center(child: Text('🚗', style: TextStyle(fontSize: 28))),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('السيارة', style: TextStyle(fontSize: 12, color: AppColors.textFaint, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      [model, color].where((e) => e != null && e.isNotEmpty).join(' — '),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                    ),
                    if (regNumber != null && regNumber.isNotEmpty)
                      Text('لوحة: $regNumber', style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
                    if (year != null && year.isNotEmpty)
                      Text('موديل: $year', style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 22),
          _qualityToggle(
            v: v,
            column: 'has_ac',
            value: hasAc,
            label: '❄️ عربيتي مكيّفة',
            hint: 'فعّلها لو عربيتك بتكييف — كده هتوصلك طلبات "عربية مكيّفة" اللي العميل بيدفع فيها سعر أعلى.',
          ),
          const SizedBox(height: 14),
          _qualityToggle(
            v: v,
            column: 'is_clean',
            value: v['is_clean'] == true,
            label: '🧼 عربيتي نظيفة',
            hint: 'فعّلها لو عربيتك دايمًا نظيفة من جوه وبره — كده هتوصلك طلبات "عربية نظيفة" اللي العميل بيدفع فيها سعر أعلى.',
          ),
          const SizedBox(height: 14),
          _qualityToggle(
            v: v,
            column: 'is_modern',
            value: v['is_modern'] == true,
            label: '✨ عربيتي موديل حديث',
            hint: 'فعّلها لو عربيتك موديل حديث فعلًا — كده هتوصلك طلبات "موديل حديث" اللي العميل بيدفع فيها سعر أعلى.',
          ),
        ],
      ),
    );
  }

  /// A single self-declared quality-tier flag (has_ac/is_clean/is_modern) —
  /// each toggle writes straight to its driver_applications column and
  /// determines whether this driver is offered that tier's rides at all
  /// (accept_dispatch_offer() checks the same column server-side). The red
  /// warning is the only guard against a driver lying about their car —
  /// there's no way to verify this automatically, so honesty here directly
  /// determines whether the customer actually gets the service they paid
  /// extra for.
  Widget _qualityToggle({
    required Map<String, dynamic> v,
    required String column,
    required bool value,
    required String label,
    required String hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
            Switch(
              value: value,
              onChanged: (val) async {
                setState(() => _vehicle = {...v, column: val});
                try {
                  await _driverRepo.updateQualityFlag(widget.session.phone, column, val);
                } catch (_) {
                  if (!mounted) return;
                  setState(() => _vehicle = {...v, column: value});
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذّر الحفظ، حاول تاني')));
                }
              },
            ),
          ],
        ),
        Text(hint, style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
        const SizedBox(height: 4),
        const Text(
          '⚠️ تفعيل الخدمة دي من غير ما تكون العربية فعلًا مطابقة يُعد مخالفة أخلاقية وعدم مصداقية في تقديم الخدمة — من فضلك التزم بالمصداقية حفاظًا على مستوى الخدمة.',
          style: TextStyle(fontSize: 10.5, color: Colors.red, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _buildInfoCard(String? city, String? email) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: const [
        BoxShadow(color: Color(0x11000000), blurRadius: 8, offset: Offset(0, 2)),
      ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _infoRow('المدينة', (city?.isNotEmpty == true) ? city! : '—'),
          const Divider(height: 20),
          _infoRow('البريد الإلكتروني', (email?.isNotEmpty == true) ? email! : '—'),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textFaint, fontWeight: FontWeight.w700)),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
      ],
    );
  }
}
