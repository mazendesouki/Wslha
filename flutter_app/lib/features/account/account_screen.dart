import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/session.dart';
import '../../core/theme.dart';
import '../orders/orders_repository.dart';
import '../ratings/ratings_repository.dart';
import 'account_repository.dart';
import 'invoices_screen.dart';

const Map<String, String> _roleAr = {
  'customer': 'عميل',
  'driver': 'سائق',
  'merchant': 'تاجر',
  'admin': 'أدمن',
};

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => AccountScreenState();
}

/// Public (not `_`-prefixed) so HomeShell can hold a GlobalKey<AccountScreenState>
/// and call refresh() when the "حسابي" tab is (re)selected — this screen sits
/// inside an IndexedStack, so switching tabs back to it does NOT re-run
/// initState()/_load(), which is why the stats/addresses/reviews used to look
/// "frozen" even right after finishing a ride or order.
class AccountScreenState extends State<AccountScreen> {
  final _repo = AccountRepository();
  final _ordersRepo = OrdersRepository();
  final _ratingsRepo = RatingsRepository();
  final _picker = ImagePicker();

  UserSession? _session;
  Map<String, dynamic>? _account;
  HistoryStats _stats = HistoryStats(totalOrders: 0, totalRides: 0, totalSpent: 0);
  List<Map<String, dynamic>> _addresses = [];
  List<Map<String, dynamic>> _reviews = [];
  List<Map<String, dynamic>> _driverNotes = [];
  bool _loading = true;
  bool _uploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Called by HomeShell when the "حسابي" tab is selected again.
  Future<void> refresh() => _load();

  Future<void> _load() async {
    final session = await SessionStore.load();
    if (session == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final phone = session.phone;
    // Each section loads independently — a hiccup fetching e.g. saved
    // addresses shouldn't blank the whole screen (same defensive pattern
    // as DriverProfileScreen after the vehicle-card crash bug).
    final results = await Future.wait([
      _repo.lookupAccount(phone).catchError((_) => null),
      _ordersRepo.fetchStats(phone).catchError((_) => HistoryStats(totalOrders: 0, totalRides: 0, totalSpent: 0)),
      _repo.fetchSavedAddresses(phone).catchError((_) => <Map<String, dynamic>>[]),
      _ratingsRepo.customerGivenReviews(phone).catchError((_) => <Map<String, dynamic>>[]),
      _ratingsRepo.driverGivenReviews(phone).catchError((_) => <Map<String, dynamic>>[]),
    ]);
    if (!mounted) return;
    setState(() {
      _session = session;
      _account = results[0] as Map<String, dynamic>?;
      _stats = results[1] as HistoryStats;
      _addresses = results[2] as List<Map<String, dynamic>>;
      _driverNotes = results[4] as List<Map<String, dynamic>>;
      _reviews = results[3] as List<Map<String, dynamic>>;
      _loading = false;
    });
  }

  Future<void> _logout() async {
    await SessionStore.clear();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
  }

  Future<void> _pickAvatar() async {
    if (_session == null) return;
    final shot = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 800);
    if (shot == null) return;
    setState(() => _uploadingAvatar = true);
    final bytes = await File(shot.path).readAsBytes();
    final ext = shot.path.split('.').last.toLowerCase();
    final url = await _repo.uploadAvatar(_session!.phone, bytes, ext.isEmpty ? 'jpg' : ext);
    if (!mounted) return;
    setState(() => _uploadingAvatar = false);
    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذّر رفع الصورة، حاول تاني')));
      return;
    }
    await _load();
  }

  Future<void> _editProfile() async {
    if (_session == null) return;
    final nameCtrl = TextEditingController(text: _account?['name'] as String? ?? _session!.name);
    final cityCtrl = TextEditingController(text: _account?['city'] as String? ?? _session!.city ?? '');
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
              ElevatedButton(
                onPressed: () => Navigator.of(sheetContext).pop(true),
                child: const Text('حفظ'),
              ),
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
      final ok = await _repo.updateEmail(_session!.phone, passwordCtrl.text, newEmail);
      if (!ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('كلمة المرور غير صحيحة — لم يتم تغيير البريد الإلكتروني')));
        return;
      }
    }
    await _repo.updateProfile(
      _session!.phone,
      name: nameCtrl.text.trim(),
      city: cityCtrl.text.trim(),
    );
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ التعديلات')));
  }

  Future<void> _addOrEditAddress({Map<String, dynamic>? existing}) async {
    if (_session == null) return;
    final labelCtrl = TextEditingController(text: existing?['label'] as String? ?? '');
    final areaCtrl = TextEditingController(text: existing?['area'] as String? ?? '');
    final addressCtrl = TextEditingController(text: existing?['address'] as String? ?? '');
    bool makeDefault = existing == null && _addresses.isEmpty;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
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
              Text(existing == null ? 'إضافة عنوان' : 'تعديل العنوان', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
              const SizedBox(height: 16),
              TextField(controller: labelCtrl, decoration: const InputDecoration(labelText: 'اسم العنوان (المنزل، الشغل...)')),
              const SizedBox(height: 12),
              TextField(controller: areaCtrl, decoration: const InputDecoration(labelText: 'المنطقة')),
              const SizedBox(height: 12),
              TextField(controller: addressCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'العنوان بالتفصيل')),
              if (existing == null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Switch(value: makeDefault, onChanged: (v) => setSheetState(() => makeDefault = v)),
                    const Text('اجعله العنوان الافتراضي', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () {
                  if (labelCtrl.text.trim().isEmpty || addressCtrl.text.trim().length < 5) {
                    ScaffoldMessenger.of(sheetContext).showSnackBar(const SnackBar(content: Text('اكتب اسم العنوان والتفاصيل كاملة')));
                    return;
                  }
                  Navigator.of(sheetContext).pop(true);
                },
                child: const Text('حفظ'),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved != true) return;
    if (existing == null) {
      await _repo.addSavedAddress(
        _session!.phone,
        label: labelCtrl.text.trim(),
        area: areaCtrl.text.trim(),
        address: addressCtrl.text.trim(),
        makeDefault: makeDefault,
      );
    } else {
      await _repo.updateSavedAddress(
        existing['id'].toString(),
        label: labelCtrl.text.trim(),
        area: areaCtrl.text.trim(),
        address: addressCtrl.text.trim(),
      );
    }
    await _load();
  }

  Future<void> _deleteAddress(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('حذف العنوان؟'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dCtx).pop(false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.of(dCtx).pop(true), child: const Text('حذف', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repo.deleteSavedAddress(id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_session == null) {
      return const Scaffold(body: Center(child: Text('يرجى تسجيل الدخول')));
    }
    final name = _account?['name'] as String? ?? _session!.name;
    final city = _account?['city'] as String? ?? _session!.city;
    final email = _account?['email'] as String?;
    final role = _account?['role'] as String? ?? _session!.role;
    final avatarUrl = _account?['avatar_url'] as String?;

    return Scaffold(
      appBar: AppBar(title: const Text('حسابي')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppColors.primary, AppColors.primaryDark]),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _pickAvatar,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundColor: Colors.white24,
                          backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                          child: avatarUrl == null || avatarUrl.isEmpty
                              ? const Text('👤', style: TextStyle(fontSize: 28))
                              : null,
                        ),
                        Positioned(
                          bottom: -2,
                          left: -2,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                            child: _uploadingAvatar
                                ? const SizedBox(height: 12, width: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(name, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(_session!.phone, style: const TextStyle(color: Colors.white70, fontSize: 12), textDirection: TextDirection.ltr),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(999)),
                    child: Text(_roleAr[role] ?? role, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _statsRow(),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.cardTint, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _infoRow('المدينة', (city?.isNotEmpty == true) ? city! : '—'),
                  const Divider(height: 20),
                  _infoRow('البريد الإلكتروني', (email?.isNotEmpty == true) ? email! : '—'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _editProfile,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('تعديل بياناتي'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => InvoicesScreen(customerPhone: _session!.phone),
              )),
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('🧾 فواتيري'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
            const SizedBox(height: 24),
            _addressesSection(),
            const SizedBox(height: 24),
            _reviewsSection(),
            const SizedBox(height: 24),
            _driverNotesSection(),
            const SizedBox(height: 24),
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

  Widget _statsRow() {
    return Row(
      children: [
        Expanded(child: _statTile('📦', AppColors.primary, '${_stats.totalOrders + _stats.totalRides}', 'إجمالي الطلبات')),
        const SizedBox(width: 10),
        Expanded(child: _statTile('💰', AppColors.accent, _stats.totalSpent.toStringAsFixed(0), 'إجمالي الإنفاق (ج.م)')),
        const SizedBox(width: 10),
        Expanded(child: _statTile('🚖', AppColors.primaryDark, '${_stats.totalRides}', 'عدد الرحلات')),
      ],
    );
  }

  Widget _statTile(String emoji, Color accent, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(color: AppColors.cardTint, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Text(emoji, style: const TextStyle(fontSize: 16)),
          ),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: accent)),
          const SizedBox(height: 2),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: AppColors.textFaint)),
        ],
      ),
    );
  }

  Widget _addressesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('📍 عناويني المحفوظة', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            TextButton.icon(
              onPressed: () => _addOrEditAddress(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('إضافة'),
            ),
          ],
        ),
        if (_addresses.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: AppColors.cardTint, borderRadius: BorderRadius.circular(16)),
            child: const Center(
              child: Text('مفيش عناوين محفوظة — ضيف عنوان عشان تختاره بسرعة وقت الطلب', style: TextStyle(color: AppColors.textFaint, fontSize: 12)),
            ),
          )
        else
          ..._addresses.map(_addressTile),
      ],
    );
  }

  Widget _addressTile(Map<String, dynamic> a) {
    final isDefault = a['is_default'] == true;
    final id = a['id'].toString();
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardTint,
        borderRadius: BorderRadius.circular(14),
        border: isDefault ? Border.all(color: AppColors.primary, width: 1.5) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(a['label'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                    if (isDefault) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(999)),
                        child: const Text('افتراضي', style: TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: () => _addOrEditAddress(existing: a),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.error),
                onPressed: () => _deleteAddress(id),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          if ((a['area'] as String?)?.isNotEmpty == true) Text(a['area'] as String, style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
          const SizedBox(height: 4),
          Text(a['address'] as String? ?? '', style: const TextStyle(fontSize: 12)),
          if (!isDefault) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () async {
                await _repo.setDefaultAddress(id, _session!.phone);
                await _load();
              },
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              child: const Text('اجعله افتراضي', style: TextStyle(fontSize: 11)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _reviewsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('⭐ تقييماتي للسائقين', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
        const SizedBox(height: 10),
        if (_reviews.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: AppColors.cardTint, borderRadius: BorderRadius.circular(16)),
            child: const Center(
              child: Text('لسه ما قيّمتش أي رحلة', style: TextStyle(color: AppColors.textFaint, fontSize: 12)),
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
    final tags = (r['tags'] as List?)?.cast<String>() ?? [];
    final createdAt = DateTime.tryParse(r['created_at'] as String? ?? '');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.cardTint, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
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
        ],
      ),
    );
  }

  Widget _driverNotesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('💬 ملاحظات وتقييمات السائقين عني', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
        const SizedBox(height: 10),
        if (_driverNotes.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: AppColors.cardTint, borderRadius: BorderRadius.circular(16)),
            child: const Center(
              child: Text('لسه مفيش تقييم أو ملاحظة من سائق — بتظهر هنا فور ما رحلتك تخلص ويقيّمك السائق', style: TextStyle(color: AppColors.textFaint, fontSize: 12), textAlign: TextAlign.center),
            ),
          )
        else
          ..._driverNotes.map(_reviewTile),
      ],
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
