import 'package:http/http.dart' as http;
import '../../core/supabase_client.dart';

/// The `accounts` table has no SELECT grant for anon/authenticated at all —
/// reads go through the `lookup_account` RPC. A direct `.update()` also
/// needs fixing here: Postgres requires SELECT on any column referenced in
/// an UPDATE's WHERE clause (here, `phone`) in addition to UPDATE on the
/// changed columns, so a raw `sb.from('accounts').update(...).eq('phone', ...)`
/// fails with "permission denied for table accounts" (db/security-67) —
/// writes go through security-definer RPCs instead, same as
/// update_account_email() already did.
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
    String? username,
  }) async {
    if (name == null && city == null && username == null) return;
    await sb.rpc('update_account_profile', params: {
      'p_phone': phone,
      if (name != null) 'p_name': name,
      if (city != null) 'p_city': city,
      if (username != null) 'p_username': username,
    });
  }

  /// email is deliberately not part of updateProfile()'s direct table
  /// UPDATE — an unverified email change would let anyone hijack an
  /// account via "forgot password" (security-47), so it goes through this
  /// password-verified RPC instead.
  Future<bool> updateEmail(String phone, String password, String newEmail) async {
    final result = await sb.rpc('update_account_email', params: {
      'p_phone': phone,
      'p_password': password,
      'p_new_email': newEmail,
    });
    return result == true;
  }

  /// Uploads to the same anon-writable `documents` storage bucket
  /// AuthRepository.uploadDriverPhoto() already uses (see auth_repository.dart),
  /// just under an `avatars/` path instead of `driver-apps/` since this is a
  /// profile picture the user can change anytime, not a one-off KYC photo.
  Future<String?> uploadAvatar(String phone, List<int> bytes, String fileExt) async {
    final path = 'avatars/$phone/avatar-${DateTime.now().millisecondsSinceEpoch}.$fileExt';
    final uploadRes = await http.post(
      Uri.parse('$supabaseUrl/storage/v1/object/documents/$path'),
      headers: {
        'apikey': supabaseAnonKey,
        'Authorization': 'Bearer $supabaseAnonKey',
        'Content-Type': 'image/$fileExt',
      },
      body: bytes,
    );
    if (uploadRes.statusCode != 200 && uploadRes.statusCode != 201) return null;
    final url = '$supabaseUrl/storage/v1/object/public/documents/$path';
    await sb.rpc('update_account_avatar', params: {'p_phone': phone, 'p_avatar_url': url});
    return url;
  }

  // ---------------------------------------------------------------------
  // Saved addresses (customer account screen). Routed through RPCs
  // (db/security-49-secure-wallets-and-addresses.sql) instead of direct
  // table access — the table had no row filter at all, so a raw SELECT
  // dumped every customer's saved addresses, and any row id could be
  // edited/deleted by anyone. Every call here is phone-scoped and, for
  // update/delete, re-verified against the row's own customer_phone.
  // ---------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> fetchSavedAddresses(String phone) async {
    final rows = await sb.rpc('list_saved_addresses', params: {'p_phone': phone});
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<void> addSavedAddress(
    String phone, {
    required String label,
    String? area,
    required String address,
    bool makeDefault = false,
  }) async {
    await sb.rpc('add_saved_address', params: {
      'p_phone': phone,
      'p_label': label,
      'p_area': area,
      'p_address': address,
      'p_make_default': makeDefault,
    });
  }

  Future<void> updateSavedAddress(
    String id,
    String phone, {
    required String label,
    String? area,
    required String address,
  }) async {
    await sb.rpc('update_saved_address', params: {
      'p_id': id,
      'p_phone': phone,
      'p_label': label,
      'p_area': area,
      'p_address': address,
    });
  }

  /// Unsets any other default for this phone first — only one address can
  /// be the default at a time.
  Future<void> setDefaultAddress(String id, String phone) async {
    await sb.rpc('set_default_saved_address', params: {'p_id': id, 'p_phone': phone});
  }

  Future<void> deleteSavedAddress(String id, String phone) async {
    await sb.rpc('delete_saved_address', params: {'p_id': id, 'p_phone': phone});
  }
}
