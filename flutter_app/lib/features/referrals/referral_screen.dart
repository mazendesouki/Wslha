import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n.dart';
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
    final text = Uri.encodeComponent('${context.tr('referral_share_prefix')} "$_myCode" — ${context.tr('referral_share_suffix')}');
    await launchUrl(Uri.parse('https://wa.me/?text=$text'), mode: LaunchMode.externalApplication);
  }

  Future<void> _copyCode() async {
    if (_myCode == null) return;
    await Clipboard.setData(ClipboardData(text: _myCode!));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('referral_code_copied'))));
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
      _resultMessage = ok ? context.tr('referral_redeem_success') : context.tr('referral_redeem_error');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.mutedSurface,
      appBar: AppBar(title: Text('🎁 ${context.tr('referral_appbar_title')}')),
      body: SafeArea(
        top: false,
        child: ListView(
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
                Text(context.tr('referral_my_code_label'), style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w700)),
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
                      label: Text(context.tr('referral_copy'), style: const TextStyle(color: Colors.white)),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white70)),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      onPressed: _myCode == null ? null : _shareCode,
                      icon: const Icon(Icons.share, size: 16),
                      label: Text(context.tr('referral_share')),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.primary),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            context.tr('referral_invite_explainer'),
            style: const TextStyle(fontSize: 12, color: AppColors.textFaint, height: 1.6),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Text(context.tr('referral_have_code_question'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(hintText: context.tr('referral_code_hint'), prefixIcon: const Icon(Icons.card_giftcard_outlined)),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _redeeming ? null : _redeem,
                child: _redeeming
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(context.tr('referral_use_button')),
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
      ),
    );
  }
}
