import '../../core/supabase_client.dart';

class RideMessage {
  final String id;
  final String senderPhone;
  final String senderRole;
  final String body;
  final DateTime createdAt;
  const RideMessage({
    required this.id,
    required this.senderPhone,
    required this.senderRole,
    required this.body,
    required this.createdAt,
  });

  factory RideMessage.fromRow(Map<String, dynamic> r) => RideMessage(
        id: r['id'] as String,
        senderPhone: r['sender_phone'] as String,
        senderRole: r['sender_role'] as String,
        body: r['body'] as String,
        createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
      );
}

/// ride_messages is directly SELECT-able (db/security-69 — same open-by-id
/// trust model as rides/driver_locations/ride-track.astro) so Realtime
/// streaming works, but every INSERT goes through send_ride_message(),
/// which verifies the sender is an actual participant in that ride.
class RideChatRepository {
  Future<void> send({
    required String rideId,
    required String senderPhone,
    required String senderRole,
    required String body,
  }) async {
    await sb.rpc('send_ride_message', params: {
      'p_ride_id': rideId,
      'p_sender_phone': senderPhone,
      'p_sender_role': senderRole,
      'p_body': body,
    });
  }

  Stream<List<RideMessage>> watch(String rideId) {
    return sb
        .from('ride_messages')
        .stream(primaryKey: ['id'])
        .eq('ride_id', rideId)
        .order('created_at')
        .map((rows) => rows.map(RideMessage.fromRow).toList());
  }
}
