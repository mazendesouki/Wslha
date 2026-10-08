import 'package:flutter/material.dart';

import '../../core/date_format_ar.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import 'notifications_repository.dart';

const Map<String, String> _typeIcon = {
  'order': '📦',
  'ride': '🚗',
};

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _repo = NotificationsRepository();
  String? _phone;
  List<AppNotification>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = await SessionStore.load();
    _phone = session?.phone;
    if (_phone == null) {
      if (!mounted) return;
      setState(() => _items = []);
      return;
    }
    final items = await _repo.list(_phone!);
    if (!mounted) return;
    setState(() => _items = items);
  }

  Future<void> _markAllRead() async {
    final phone = _phone;
    if (phone == null) return;
    await _repo.markAllRead(phone);
    await _load();
  }

  Future<void> _onTap(AppNotification item) async {
    final phone = _phone;
    if (phone != null && !item.read) {
      await _repo.markRead(phone, item.id);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final hasUnread = items != null && items.any((n) => !n.read);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('notif_list_title')),
        actions: [
          if (hasUnread)
            IconButton(onPressed: _markAllRead, icon: const Icon(Icons.done_all), tooltip: context.tr('notif_list_mark_all_read')),
        ],
      ),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? const _EmptyState()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => _NotificationTile(item: items[i], onTap: () => _onTap(items[i])),
                  ),
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
  final AppNotification item;
  final VoidCallback onTap;
  const _NotificationTile({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final icon = _typeIcon[item.type ?? ''] ?? '🔔';
    return ListTile(
      onTap: onTap,
      tileColor: item.read ? null : AppColors.primaryLight.withValues(alpha: 0.25),
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: AppColors.primaryLight,
        child: Text(icon, style: const TextStyle(fontSize: 18)),
      ),
      title: Text(
        item.title,
        style: TextStyle(fontWeight: item.read ? FontWeight.w700 : FontWeight.w900, fontSize: 14),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(item.body, style: const TextStyle(fontSize: 13)),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            arRelativeTime(item.createdAt),
            style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
            textAlign: TextAlign.left,
          ),
          if (!item.read) const SizedBox(height: 4),
          if (!item.read)
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(color: AppColors.primaryDark, shape: BoxShape.circle),
            ),
        ],
      ),
      isThreeLine: false,
    );
  }
}
