import '../../core/supabase_client.dart';

class EmergencyContact {
  final String id;
  final String name;
  final String phone;
  const EmergencyContact({required this.id, required this.name, required this.phone});

  factory EmergencyContact.fromRow(Map<String, dynamic> r) => EmergencyContact(
        id: r['id'] as String,
        name: r['contact_name'] as String,
        phone: r['contact_phone'] as String,
      );
}

/// emergency_contacts has no direct SELECT/INSERT/DELETE grant for
/// anon/authenticated (db/security-68) — every call here goes through a
/// security-definer RPC scoped to the caller's own phone, same pattern as
/// AccountRepository's saved-addresses methods.
class EmergencyContactsRepository {
  Future<List<EmergencyContact>> list(String phone) async {
    final rows = await sb.rpc('list_emergency_contacts', params: {'p_phone': phone});
    return (rows as List).map((r) => EmergencyContact.fromRow(Map<String, dynamic>.from(r as Map))).toList();
  }

  /// Returns null if the 3-contact cap (db/security-68) was hit.
  Future<bool> add(String phone, String name, String contactPhone) async {
    try {
      await sb.rpc('add_emergency_contact', params: {'p_phone': phone, 'p_name': name, 'p_contact_phone': contactPhone});
      return true;
    } catch (e) {
      if (e.toString().contains('MAX_CONTACTS')) return false;
      rethrow;
    }
  }

  Future<bool> delete(String id, String phone) async {
    final result = await sb.rpc('delete_emergency_contact', params: {'p_id': id, 'p_phone': phone});
    return result == true;
  }
}
