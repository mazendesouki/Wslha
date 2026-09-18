import 'package:flutter/material.dart';

import '../../core/contact_launcher.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import 'favorites_repository.dart';

class FavoriteDriversScreen extends StatefulWidget {
  const FavoriteDriversScreen({super.key});

  @override
  State<FavoriteDriversScreen> createState() => _FavoriteDriversScreenState();
}

class _FavoriteDriversScreenState extends State<FavoriteDriversScreen> {
  final _repo = FavoritesRepository();
  List<FavoriteDriver>? _drivers;
  String? _phone;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = await SessionStore.load();
    if (session == null) return;
    final drivers = await _repo.list(session.phone).catchError((_) => <FavoriteDriver>[]);
    if (!mounted) return;
    setState(() {
      _phone = session.phone;
      _drivers = drivers;
    });
  }

  Future<void> _remove(FavoriteDriver d) async {
    if (_phone == null) return;
    await _repo.toggle(_phone!, d.phone);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final drivers = _drivers;
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF9),
      appBar: AppBar(title: const Text('⭐ السائقين المفضّلين')),
      body: drivers == null
          ? const Center(child: CircularProgressIndicator())
          : drivers.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'لسه مفيش سائقين مفضّلين — دوس على أيقونة ❤️ في تفاصيل السائق أثناء أي رحلة عشان تضيفه هنا',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textFaint),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: drivers.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final d = drivers[i];
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE9ECEB))),
                      child: Row(
                        children: [
                          const CircleAvatar(backgroundColor: AppColors.primaryLight, child: Text('🚖')),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              d.name.isNotEmpty ? d.name : 'سائق',
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                            ),
                          ),
                          IconButton(onPressed: () => callPhone(d.phone), icon: const Icon(Icons.call, color: AppColors.success)),
                          IconButton(onPressed: () => _remove(d), icon: const Icon(Icons.favorite, color: AppColors.error)),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
