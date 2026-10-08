import '../../core/supabase_client.dart';

class AppNotification {
  final String id;
  final String title;
  final String body;
  final String? url;
  final String? type;
  final DateTime createdAt;
  final bool read;

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    this.url,
    this.type,
    required this.createdAt,
    required this.read,
  });

  factory AppNotification.fromRow(Map<String, dynamic> r) => AppNotification(
        id: r['id'] as String,
        title: r['title'] as String? ?? '',
        body: r['body'] as String? ?? '',
        url: r['url'] as String?,
        type: r['type'] as String?,
        createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
        read: r['read_at'] != null,
      );
}

/// Server-backed notification inbox (db/security-116) — a durable,
/// cross-device copy of every push send-push.ts (supabase/functions/
/// send-push) makes, independent from the device-local tray-notification
/// log in core/notifications.dart (AppNotifications.history()). Reads go
/// through list_notifications/unread_notifications_count (SECURITY
/// DEFINER RPCs — the table itself has no grants for anon beyond the open
/// SELECT policy used for Realtime, see security-116) rather than a plain
/// table select, matching the rest of this app's phone-scoped RPC pattern.
class NotificationsRepository {
  Future<List<AppNotification>> list(String phone, {int limit = 50}) async {
    final rows = await sb.rpc('list_notifications', params: {'p_phone': phone, 'p_limit': limit});
    return (rows as List).map((r) => AppNotification.fromRow(r as Map<String, dynamic>)).toList();
  }

  Future<int> unreadCount(String phone) async {
    final count = await sb.rpc('unread_notifications_count', params: {'p_phone': phone});
    return count as int;
  }

  Future<void> markRead(String phone, String id) async {
    await sb.rpc('mark_notification_read', params: {'p_phone': phone, 'p_id': id});
  }

  Future<void> markAllRead(String phone) async {
    await sb.rpc('mark_all_notifications_read', params: {'p_phone': phone});
  }

  /// Realtime stream for the unread badge — the RPCs above are one-shot
  /// reads, so the badge instead watches raw row changes and recomputes
  /// the unread count on every change (table is tiny per-user, cheap).
  Stream<int> watchUnreadCount(String phone) {
    return sb
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('phone', phone)
        .map((rows) => rows.where((r) => r['read_at'] == null).length);
  }
}
