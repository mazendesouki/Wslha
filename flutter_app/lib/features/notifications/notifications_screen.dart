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
  final _scrollController = ScrollController();
  static const _pageSize = 50;
  String? _phone;
  List<AppNotification>? _items;
  bool _hasMore = true;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _load();
    // Fetches the next page (db/security-188's cursor) once the list is
    // scrolled near the bottom — without this, anything past the first
    // _pageSize notifications was permanently unreachable.
    _scrollController.addListener(() {
      if (!_loadingMore &&
          _hasMore &&
          _scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final session = await SessionStore.load();
    _phone = session?.phone;
    if (_phone == null) {
      if (!mounted) return;
      setState(() => _items = []);
      return;
    }
    final items = await _repo.list(_phone!, limit: _pageSize);
    if (!mounted) return;
    setState(() {
      _items = items;
      _hasMore = items.length >= _pageSize;
    });
  }

  Future<void> _loadMore() async {
    final phone = _phone;
    final items = _items;
    if (phone == null || items == null || items.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final last = items.last;
      final more = await _repo.list(phone, limit: _pageSize, afterCreatedAt: last.createdAt, afterId: last.id);
      if (!mounted) return;
      setState(() {
        _items = [...items, ...more];
        _hasMore = more.length >= _pageSize;
      });
    } catch (_) {
      // Next scroll-triggered attempt (or a pull-to-refresh) will retry.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
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
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: items.length + (_loadingMore ? 1 : 0),
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => i >= items.length
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : _NotificationTile(item: items[i], onTap: () => _onTap(items[i])),
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
