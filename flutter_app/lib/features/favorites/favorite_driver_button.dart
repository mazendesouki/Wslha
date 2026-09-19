import 'package:flutter/material.dart';

import '../../core/feature_flags.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import 'favorites_repository.dart';

/// A self-contained heart toggle for _DriverCard (ride_tracking_screen.dart)
/// — loads its own current-favorite state and flips it on tap, without the
/// parent needing to be stateful.
class FavoriteDriverButton extends StatefulWidget {
  final String driverPhone;
  const FavoriteDriverButton({super.key, required this.driverPhone});

  @override
  State<FavoriteDriverButton> createState() => _FavoriteDriverButtonState();
}

class _FavoriteDriverButtonState extends State<FavoriteDriverButton> {
  final _repo = FavoritesRepository();
  String? _phone;
  bool? _isFavorite;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = await SessionStore.load();
    if (session == null || !mounted) return;
    final fav = await _repo.isFavorite(session.phone, widget.driverPhone).catchError((_) => false);
    if (!mounted) return;
    setState(() {
      _phone = session.phone;
      _isFavorite = fav;
    });
  }

  Future<void> _toggle() async {
    if (_phone == null) return;
    final previous = _isFavorite ?? false;
    setState(() => _isFavorite = !previous);
    try {
      final nowFavorite = await _repo.toggle(_phone!, widget.driverPhone);
      if (!mounted) return;
      setState(() => _isFavorite = nowFavorite);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isFavorite = previous);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!FeatureFlags.favoritesEnabled) return const SizedBox.shrink();
    final isFavorite = _isFavorite ?? false;
    return IconButton(
      onPressed: _phone == null ? null : _toggle,
      icon: Icon(
        isFavorite ? Icons.favorite : Icons.favorite_border,
        color: isFavorite ? AppColors.error : AppColors.textFaint,
      ),
      tooltip: isFavorite ? context.tr('favorite_driver_remove_tooltip') : context.tr('favorite_driver_add_tooltip'),
    );
  }
}
