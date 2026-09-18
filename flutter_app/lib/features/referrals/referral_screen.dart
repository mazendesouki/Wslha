import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/session.dart';
import '../../core/theme.dart';
import 'referral_repository.dart';

class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  final _repo = ReferralRepository();
  final _codeCtrl = TextEditingController();
  String? _phone;
  String? _myCode;
  bool _redeeming = false;
  String? _resultMessage;
  bool _resultOk = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final session = await SessionStore.load();
    if (session == null) return;
    final code = await _repo.getMyCode(session.phone).catchError((_) => null);
    if (!mounted) return;
    setState(() {
      _phone = session.phone;
      _myCode = code;
    });
  }

  Future<void> _shareCode() async {
    if (_myCode == null) return;
    final text = Uri.encodeComponent('انزل تطبيق وصّلها واستخدم كود الدعوة بتاعي "$_myCode" — كل واحد فينا ياخد رصيد 20 ج.م في المحفظة 🎁');
    await launchUrl(Uri.parse('https://wa.me/?text=$text'), mode: LaunchMode.externalApplication);
  }

  Future<void> _copyCode() async {
    if (_myCode == null) return;
    await Clipboard.setData(ClipboardData(text: _myCode!));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ الكود')));
  }

  Future<void> _redeem() async {
    if (_phone == null) return;
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _redeeming = true;
      _resultMessage = null;
    });
    final ok = await _repo.redeem(_phone!, code).catchError((_) => false);
    if (!mounted) return;
    setState(() {
      _redeeming = false;
      _resultOk = ok;
      _resultMessage = ok ? '🎉 تم! اتضاف 20 ج.م لمحفظتك' : 'الكود غير صحيح أو مستخدم قبل كده';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF9),
      appBar: AppBar(title: const Text('🎁 كود الدعوة')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.primaryDark, AppColors.primary]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Text('كود الدعوة بتاعك', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  _myCode ?? '...',
                  style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 4),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _myCode == null ? null : _copyCode,
                      icon: const Icon(Icons.copy, color: Colors.white, size: 16),
                      label: const Text('نسخ', style: TextStyle(color: Colors.white)),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white70)),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      onPressed: _myCode == null ? null : _shareCode,
                      icon: const Icon(Icons.share, size: 16),
                      label: const Text('مشاركة'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.primary),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'ادعُ صحابك — كل واحد يستخدم كودك ياخد 20 ج.م رصيد في محفظته، وانت كمان تاخد 20 ج.م.',
            style: TextStyle(fontSize: 12, color: AppColors.textFaint, height: 1.6),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          const Text('عندك كود من صاحبك؟', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(hintText: 'اكتب الكود هنا', prefixIcon: Icon(Icons.card_giftcard_outlined)),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _redeeming ? null : _redeem,
                child: _redeeming
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('استخدام'),
              ),
            ],
          ),
          if (_resultMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              _resultMessage!,
              style: TextStyle(color: _resultOk ? AppColors.success : AppColors.error, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
