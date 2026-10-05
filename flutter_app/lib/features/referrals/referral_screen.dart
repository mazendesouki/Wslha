import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

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
  int _referredCount = 0;
  double _totalEarned = 0;
  List<Map<String, dynamic>> _referrals = [];

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
    final results = await Future.wait([
      _repo.getStats(session.phone),
      _repo.getMyReferrals(session.phone),
    ]).catchError((_) => <Object>[(referredCount: 0, totalEarned: 0.0), <Map<String, dynamic>>[]]);
    if (!mounted) return;
    final stats = results[0] as ({int referredCount, double totalEarned});
    setState(() {
      _referredCount = stats.referredCount;
      _totalEarned = stats.totalEarned;
      _referrals = results[1] as List<Map<String, dynamic>>;
    });
  }

  Future<void> _shareCode() async {
    if (_myCode == null) return;
    final text = '${context.tr('referral_share_prefix')} "$_myCode" — ${context.tr('referral_share_suffix')}';
    await Share.share(text);
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
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  icon: '👥',
                  value: '$_referredCount',
                  label: context.tr('referral_stat_invited'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatTile(
                  icon: '💰',
                  value: '${_totalEarned.toStringAsFixed(0)} ${context.tr('referral_currency')}',
                  label: context.tr('referral_stat_earned'),
                ),
              ),
            ],
          ),
          if (_referrals.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(context.tr('referral_people_invited_title'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
            const SizedBox(height: 8),
            ..._referrals.map((r) {
              final joined = DateTime.tryParse(r['created_at'] as String? ?? '')?.toLocal();
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: context.surfaceColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.borderColor),
                ),
                child: Row(
                  children: [
                    const CircleAvatar(radius: 16, backgroundColor: AppColors.primaryLight, child: Text('👤')),
                    const SizedBox(width: 10),
                    Expanded(child: Text(r['name'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                    if (joined != null)
                      Text('${joined.day}/${joined.month}/${joined.year}', style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
                  ],
                ),
              );
            }),
          ],
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

class _StatTile extends StatelessWidget {
  final String icon;
  final String value;
  final String label;
  const _StatTile({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.primaryDark)),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textFaint), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
