import '../../core/supabase_client.dart';

/// The `accounts` table is not directly SELECTable by the anon key — the
/// web app (profile.astro) goes through the same `lookup_account` RPC and
/// PATCHes `accounts` directly for edits, which does work under RLS since
/// the row is matched by phone. Mirrors that exactly.
class AccountRepository {
  Future<Map<String, dynamic>?> lookupAccount(String phone) async {
    final rows = await sb.rpc('lookup_account', params: {'p_phone': phone});
    if (rows is List && rows.isNotEmpty) return Map<String, dynamic>.from(rows.first);
    return null;
  }

  Future<void> updateProfile(
    String phone, {
    String? name,
    String? city,
    String? email,
    String? username,
  }) async {
    final patch = <String, dynamic>{};
    if (name != null) patch['name'] = name;
    if (city != null) patch['city'] = city;
    if (email != null) patch['email'] = email;
    if (username != null) patch['username'] = username;
    if (patch.isEmpty) return;
    await sb.from('accounts').update(patch).eq('phone', phone);
  }
}
