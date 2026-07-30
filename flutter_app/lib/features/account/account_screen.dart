import 'package:flutter/material.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import 'account_repository.dart';

const Map<String, String> _roleAr = {
  'customer': 'عميل',
  'driver': 'سائق',
  'merchant': 'تاجر',
  'admin': 'أدمن',
};

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _repo = AccountRepository();
  UserSession? _session;
  Map<String, dynamic>? _account;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = await SessionStore.load();
    if (session == null) {
      setState(() => _loading = false);
      return;
    }
    final account = await _repo.lookupAccount(session.phone);
    if (!mounted) return;
    setState(() {
      _session = session;
      _account = account;
      _loading = false;
    });
  }

  Future<void> _logout() async {
    await SessionStore.clear();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
  }

  Future<void> _editProfile() async {
    if (_session == null) return;
    final nameCtrl = TextEditingController(text: _account?['name'] as String? ?? _session!.name);
    final cityCtrl = TextEditingController(text: _account?['city'] as String? ?? _session!.city ?? '');
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
            ElevatedButton(
              onPressed: () => Navigator.of(sheetContext).pop(true),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    await _repo.updateProfile(
      _session!.phone,
      name: nameCtrl.text.trim(),
      city: cityCtrl.text.trim(),
      email: emailCtrl.text.trim(),
    );
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ التعديلات')));
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

    return Scaffold(
      appBar: AppBar(title: const Text('حسابي')),
      body: ListView(
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
                const CircleAvatar(radius: 32, backgroundColor: Colors.white24, child: Text('👤', style: TextStyle(fontSize: 28))),
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
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
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
          const SizedBox(height: 12),
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
