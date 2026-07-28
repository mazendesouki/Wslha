import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import 'wallet_repository.dart';

// Same Arabic labels as wallet.astro's `labels` map.
const Map<String, String> _txLabels = {
  'topup': 'إيداع',
  'deposit': 'إيداع',
  'earning': 'أرباح',
  'refund': 'استرداد',
  'transfer_in': 'تحويل وارد',
  'commission': 'عمولة',
  'payment': 'مدفوعات',
  'withdrawal': 'سحب',
  'transfer_out': 'تحويل صادر',
  'admin_credit': 'شحن يدوي',
  'admin_debit': 'خصم يدوي',
};

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final _walletRepo = WalletRepository();
  UserSession? _session;
  double _balance = 0;
  List<Map<String, dynamic>> _transactions = [];
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
    final results = await Future.wait([
      _walletRepo.getBalance(session.phone),
      _walletRepo.getTransactions(session.phone),
    ]);
    if (!mounted) return;
    setState(() {
      _session = session;
      _balance = results[0] as double;
      _transactions = results[1] as List<Map<String, dynamic>>;
      _loading = false;
    });
  }

  void _showToast(String message, {bool ok = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: ok ? AppColors.success : AppColors.error),
    );
  }

  Future<void> _openDepositSheet() async {
    final amountController = TextEditingController(text: '100');
    String method = 'فودافون كاش';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: StatefulBuilder(
          builder: (ctx, setSheetState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('⬆️ إيداع رصيد', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 16),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'المبلغ (جنيه)'),
              ),
              const SizedBox(height: 12),
              ...['فودافون كاش', 'إنستاباي', 'تحويل بنكي'].map((m) => RadioListTile<String>(
                    value: m,
                    groupValue: method,
                    onChanged: (v) => setSheetState(() => method = v!),
                    title: Text(m),
                    dense: true,
                  )),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () async {
                  final amount = double.tryParse(amountController.text) ?? 0;
                  if (amount < 10) {
                    _showToast('أدخل مبلغاً لا يقل عن 10 جنيه', ok: false);
                    return;
                  }
                  try {
                    await _walletRepo.requestDeposit(_session!.phone, amount, method, 'طلب إيداع عبر $method');
                    if (ctx.mounted) Navigator.pop(ctx);
                    _showToast('✅ تم استلام طلب الإيداع — سيُضاف الرصيد بعد تأكيد التحويل');
                    _load();
                  } catch (e) {
                    _showToast(walletErrorMessage(e), ok: false);
                  }
                },
                child: const Text('إيداع الرصيد'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openWithdrawSheet() async {
    final amountController = TextEditingController();
    final destController = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('⬇️ سحب الرصيد', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text('رصيدك المتاح: ${_balance.toStringAsFixed(0)} ج.م', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'المبلغ (جنيه)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: destController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'رقم فودافون كاش / إنستاباي'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () async {
                final amount = double.tryParse(amountController.text) ?? 0;
                if (amount < 10) {
                  _showToast('أدخل مبلغاً لا يقل عن 10 جنيه', ok: false);
                  return;
                }
                if (destController.text.trim().isEmpty) {
                  _showToast('أدخل رقم فودافون كاش أو إنستاباي', ok: false);
                  return;
                }
                try {
                  await _walletRepo.requestWithdrawal(_session!.phone, amount, destController.text.trim(), null);
                  if (ctx.mounted) Navigator.pop(ctx);
                  _showToast('✅ تم طلب سحب $amount ج.م — قيد المراجعة');
                  _load();
                } catch (e) {
                  _showToast(walletErrorMessage(e), ok: false);
                }
              },
              child: const Text('طلب سحب'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openTransferSheet() async {
    final phoneController = TextEditingController();
    final amountController = TextEditingController();
    Map<String, dynamic>? recipient;
    Timer? debounce;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: StatefulBuilder(
          builder: (ctx, setSheetState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('↔️ تحويل لمستخدم', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 16),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'رقم جوال المستلم'),
                onChanged: (v) {
                  debounce?.cancel();
                  debounce = Timer(const Duration(milliseconds: 600), () async {
                    if (v.trim().length < 10) return;
                    final found = await _walletRepo.lookupAccount(v.trim());
                    setSheetState(() => recipient = found);
                  });
                },
              ),
              if (recipient != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    children: [
                      const Text('👤', style: TextStyle(fontSize: 20)),
                      const SizedBox(width: 8),
                      Text(recipient!['name'] as String? ?? 'مستخدم', style: const TextStyle(fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'المبلغ (جنيه)'),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () async {
                  final amount = double.tryParse(amountController.text) ?? 0;
                  if (recipient == null) {
                    _showToast('لم يُعثر على هذا المستخدم', ok: false);
                    return;
                  }
                  final recipientPhone = recipient!['phone'] as String;
                  if (recipientPhone == _session!.phone) {
                    _showToast('لا يمكن التحويل لنفس الحساب', ok: false);
                    return;
                  }
                  if (amount < 1) {
                    _showToast('أدخل مبلغاً صحيحاً', ok: false);
                    return;
                  }
                  try {
                    await _walletRepo.transfer(_session!.phone, recipientPhone, amount, null);
                    if (ctx.mounted) Navigator.pop(ctx);
                    _showToast('✅ تم تحويل $amount ج.م بنجاح!');
                    _load();
                  } catch (e) {
                    _showToast(walletErrorMessage(e), ok: false);
                  }
                },
                child: const Text('تحويل الآن'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_session == null) {
      return const Scaffold(body: Center(child: Text('يرجى تسجيل الدخول')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('محفظتي')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('رصيدك الآن', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(
                    'EGP ${_balance.toStringAsFixed(0)}',
                    style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white54),
                          ),
                          onPressed: _openDepositSheet,
                          child: const Text('إيداع'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white54),
                          ),
                          onPressed: _openWithdrawSheet,
                          child: const Text('سحب'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white54),
                          ),
                          onPressed: _openTransferSheet,
                          child: const Text('تحويل'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text('المعاملات', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            const SizedBox(height: 8),
            if (_transactions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: Text('لا توجد معاملات بعد', style: TextStyle(color: AppColors.textFaint))),
              )
            else
              ..._transactions.map((t) {
                final amount = (t['amount'] as num).toDouble();
                final isPos = amount >= 0;
                final label = _txLabels[t['type']] ?? t['type'] as String;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 4)],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(isPos ? Icons.check_circle : Icons.cancel, size: 16, color: isPos ? AppColors.success : AppColors.error),
                          const SizedBox(width: 6),
                          Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        ],
                      ),
                      Text(
                        '${isPos ? '+' : ''}${amount.abs().toStringAsFixed(0)}',
                        style: TextStyle(fontWeight: FontWeight.w900, color: isPos ? AppColors.success : AppColors.error),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
