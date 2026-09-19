import 'package:flutter/material.dart';

import '../../core/date_format_ar.dart';
import '../../core/i18n.dart';
import '../../core/notifications.dart';
import '../../core/theme.dart';

const Map<String, String> _channelIcon = {
  'wslha_orders': '📦',
  'wslha_proximity_v3': '🚗',
};

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await AppNotifications.instance.history();
    if (!mounted) return;
    setState(() => _items = items);
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.tr('notif_list_clear_title')),
        content: Text(dialogContext.tr('notif_list_clear_body')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(dialogContext.tr('notif_list_cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(dialogContext.tr('notif_list_clear_confirm'), style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AppNotifications.instance.clearHistory();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('notif_list_title')),
        actions: [
          if (items != null && items.isNotEmpty)
            IconButton(onPressed: _clear, icon: const Icon(Icons.delete_outline), tooltip: context.tr('notif_list_clear_tooltip')),
        ],
      ),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? const _EmptyState()
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => _NotificationTile(item: items[i]),
                ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🔔', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(context.tr('notif_list_empty_title'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 4),
            Text(
              context.tr('notif_list_empty_body'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textFaint, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final Map<String, dynamic> item;
  const _NotificationTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final channelId = item['channelId'] as String? ?? '';
    final icon = _channelIcon[channelId] ?? '🔔';
    final title = item['title'] as String? ?? '';
    final body = item['body'] as String? ?? '';
    final at = DateTime.tryParse(item['at'] as String? ?? '');
    return ListTile(
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: AppColors.primaryLight,
        child: Text(icon, style: const TextStyle(fontSize: 18)),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(body, style: const TextStyle(fontSize: 13)),
      ),
      trailing: at == null
          ? null
          : Text(
              arRelativeTime(at),
              style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
              textAlign: TextAlign.left,
            ),
      isThreeLine: false,
    );
  }
}
