import '../../core/supabase_client.dart';

/// Same wallets/wallet_transactions tables and RPCs wallet.astro uses —
/// the client never writes a balance directly, only calls these
/// security-definer RPCs (db/security-02-wallet.sql).
class WalletRepository {
  Future<double> getBalance(String phone) async {
    final rows = await sb.from('wallets').select('balance').eq('phone', phone).limit(1);
    if (rows.isEmpty) return 0;
    return (rows.first['balance'] as num?)?.toDouble() ?? 0;
  }

  Future<List<Map<String, dynamic>>> getTransactions(String phone) async {
    final rows = await sb
        .from('wallet_transactions')
        .select('amount,type,note,created_at')
        .eq('phone', phone)
        .order('created_at', ascending: false)
        .limit(50);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> requestDeposit(String phone, double amount, String method, String note) async {
    await sb.rpc('request_deposit', params: {
      'p_phone': phone,
      'p_amount': amount,
      'p_method': method,
      'p_note': note,
    });
  }

  Future<void> requestWithdrawal(String phone, double amount, String dest, String? note) async {
    await sb.rpc('request_withdrawal', params: {
      'p_phone': phone,
      'p_amount': amount,
      'p_dest': dest,
      'p_note': note,
    });
  }

  Future<Map<String, dynamic>?> lookupAccount(String phone) async {
    final rows = await sb.rpc('lookup_account', params: {'p_phone': phone});
    if (rows is List && rows.isNotEmpty) return Map<String, dynamic>.from(rows.first);
    return null;
  }

  Future<void> transfer(String fromPhone, String toPhone, double amount, String? note) async {
    await sb.rpc('wallet_transfer', params: {
      'p_from': fromPhone,
      'p_to': toPhone,
      'p_amount': amount,
      'p_note': note,
    });
  }
}

/// Maps the RPC's raised exception text to the same Arabic messages
/// wallet.astro's rpcError() shows.
String walletErrorMessage(Object error) {
  final txt = error.toString();
  if (txt.contains('insufficient_funds')) return 'رصيدك غير كافٍ';
  if (txt.contains('amount_too_small')) return 'المبلغ أقل من الحد المسموح';
  if (txt.contains('destination_required')) return 'أدخل رقم التحويل';
  if (txt.contains('recipient_not_found')) return 'لم يُعثر على هذا المستخدم';
  if (txt.contains('same_account')) return 'لا يمكن التحويل لنفس الحساب';
  return 'حدث خطأ، حاول مرة أخرى';
}
