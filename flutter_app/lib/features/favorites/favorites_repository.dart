import '../../core/supabase_client.dart';

class FavoriteDriver {
  final String phone;
  final String name;
  const FavoriteDriver({required this.phone, required this.name});

  factory FavoriteDriver.fromRow(Map<String, dynamic> r) => FavoriteDriver(
        phone: r['driver_phone'] as String,
        name: (r['driver_name'] as String?) ?? '',
      );
}

/// favorite_drivers has no direct grants (db/security-69) — everything
/// goes through security-definer RPCs scoped to the customer's own phone.
class FavoritesRepository {
  Future<List<FavoriteDriver>> list(String phone) async {
    final rows = await sb.rpc('list_favorite_drivers', params: {'p_phone': phone});
    return (rows as List).map((r) => FavoriteDriver.fromRow(Map<String, dynamic>.from(r as Map))).toList();
  }

  /// Returns the new state — true if now favorited, false if now removed.
  Future<bool> toggle(String phone, String driverPhone) async {
    final result = await sb.rpc('toggle_favorite_driver', params: {'p_phone': phone, 'p_driver_phone': driverPhone});
    return result == true;
  }

  Future<bool> isFavorite(String phone, String driverPhone) async {
    final result = await sb.rpc('is_favorite_driver', params: {'p_phone': phone, 'p_driver_phone': driverPhone});
    return result == true;
  }
}
