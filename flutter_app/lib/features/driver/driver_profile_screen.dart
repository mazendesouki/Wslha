import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/session.dart';
import '../../core/theme.dart';
import '../account/account_repository.dart';
import '../ratings/ratings_repository.dart';
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
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  final _accountRepo = AccountRepository();
  final _driverRepo = DriverRepository();
  final _ratingsRepo = RatingsRepository();
  final _picker = ImagePicker();

  Map<String, dynamic>? _account;
  Map<String, dynamic>? _vehicle;
  Map<String, dynamic> _stats = {};
  RatingSummary _ratingSummary = RatingSummary(0, 0);
  List<Map<String, dynamic>> _reviews = [];
  bool _loading = true;
  bool _uploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final phone = widget.session.phone;
    final results = await Future.wait([
      _accountRepo.lookupAccount(phone),
      _driverRepo.fetchVehicleInfo(phone),
      _driverRepo.fetchTripStats(phone),
      _ratingsRepo.driverTrustBadge(phone),
      _ratingsRepo.driverReviews(phone),
    ]);
    if (!mounted) return;
    setState(() {
      _account = results[0] as Map<String, dynamic>?;
      _vehicle = results[1] as Map<String, dynamic>?;
      _stats = results[2] as Map<String, dynamic>;
      _ratingSummary = results[3] as RatingSummary;
      _reviews = results[4] as List<Map<String, dynamic>>;
      _loading = false;
    });
  }

  Future<void> _pickAvatar() async {
    final shot = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 800);
    if (shot == null) return;
    setState(() => _uploadingAvatar = true);
    final bytes = await File(shot.path).readAsBytes();
    final ext = shot.path.split('.').last.toLowerCase();
    final url = await _accountRepo.uploadAvatar(widget.session.phone, bytes, ext.isEmpty ? 'jpg' : ext);
    if (!mounted) return;
    setState(() => _uploadingAvatar = false);
    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذّر رفع الصورة، حاول تاني')));
      return;
    }
    await _load();
  }

  Future<void> _editProfile() async {
    final nameCtrl = TextEditingController(text: _account?['name'] as String? ?? widget.session.name);
    final cityCtrl = TextEditingController(text: _account?['city'] as String? ?? widget.session.city ?? '');
    final emailCtrl = TextEditingController(text: _account?['email'] as String? ?? '');
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
        child: Column(
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
            ),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: () => Navigator.of(sheetContext).pop(true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (saved != true) return;
    await _accountRepo.updateProfile(
      widget.session.phone,
      name: nameCtrl.text.trim(),
      city: cityCtrl.text.trim(),
      email: emailCtrl.text.trim(),
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
            const SizedBox(height: 16),
            _buildReviewsSection(),
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
          Text(name, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
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
    return Container(
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
        ],
      ),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: const [
        BoxShadow(color: Color(0x11000000), blurRadius: 8, offset: Offset(0, 2)),
      ]),
      child: Row(
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
                  [v['vehicle_model'], v['vehicle_color']].where((e) => e != null && (e as String).isNotEmpty).join(' — '),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                ),
                if ((v['vehicle_reg_number'] as String?)?.isNotEmpty == true)
                  Text('لوحة: ${v['vehicle_reg_number']}', style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
                if ((v['vehicle_year'] as String?)?.isNotEmpty == true)
                  Text('موديل: ${v['vehicle_year']}', style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
              ],
            ),
          ),
        ],
      ),
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

  Widget _buildReviewsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 10, right: 4),
          child: Text('🌟 تقييمات العملاء', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
        ),
        if (_reviews.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: const Center(
              child: Text('لسه مفيش تقييمات — هتظهر هنا أول ما عميل يقيّمك بعد رحلة', style: TextStyle(color: AppColors.textFaint, fontSize: 12)),
            ),
          )
        else
          ..._reviews.map(_reviewTile),
      ],
    );
  }

  Widget _reviewTile(Map<String, dynamic> r) {
    final rating = ((r['rating'] as num?) ?? 0).toInt();
    final emoji = rating >= 1 && rating <= 5 ? ratingEmojis[rating - 1] : '⭐';
    final comment = r['comment'] as String?;
    final reply = r['driver_reply'] as String?;
    final tags = (r['tags'] as List?)?.cast<String>() ?? [];
    final serviceType = r['service_type'] as String?;
    final typeIcon = serviceType == 'order' ? '🛍️' : serviceType == 'airport' ? '✈️' : '🚗';
    final createdAt = DateTime.tryParse(r['created_at'] as String? ?? '');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text(typeIcon, style: const TextStyle(fontSize: 14)),
              const Spacer(),
              if (createdAt != null)
                Text('${createdAt.year}/${createdAt.month}/${createdAt.day}', style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
            ],
          ),
          if (comment != null && comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('"$comment"', style: const TextStyle(fontSize: 13)),
          ],
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: tags
                  .map((t) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(999)),
                        child: Text(t, style: const TextStyle(fontSize: 10, color: AppColors.primaryDark)),
                      ))
                  .toList(),
            ),
          ],
          if (reply != null && reply.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(8)),
              child: Text('ردك: $reply', style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
            ),
          ],
        ],
      ),
    );
  }
}
