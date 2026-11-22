import 'dart:async';
import 'package:flutter/widgets.dart';
import 'flavor.dart';
import 'update_checker.dart';

/// Periodic + resume-triggered update check, shared by every home shell
/// (driver/customer/merchant) instead of each one re-implementing its own
/// single `UpdateChecker().checkForUpdate(...)` call in initState().
///
/// Reported live: "the update screen doesn't appear when there's a new
/// update" — the one-shot initState check only ever ran once, at the
/// moment that shell widget was first created (effectively, app cold
/// start). A build published while the app stayed open — foregrounded, or
/// merely backgrounded without being fully killed by the OS — was never
/// noticed until the user force-closed and relaunched the app themselves.
/// This re-checks on every resume from background, plus a periodic timer
/// as a safety net for sessions that never background at all (e.g. a
/// driver who leaves the app foregrounded for a long shift).
class UpdateCheckController with WidgetsBindingObserver {
  final AppFlavor flavor;
  final void Function(UpdateInfo info) onUpdateFound;
  final _checker = UpdateChecker();
  Timer? _timer;
  bool _started = false;

  UpdateCheckController({required this.flavor, required this.onUpdateFound});

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _check();
    _timer = Timer.periodic(const Duration(minutes: 20), (_) => _check());
  }

  void dispose() {
    if (!_started) return;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final info = await _checker.checkForUpdate(flavor);
    if (info != null) onUpdateFound(info);
  }
}
