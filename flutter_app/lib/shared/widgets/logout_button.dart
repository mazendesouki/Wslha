import 'package:flutter/material.dart';
import '../../core/driver_background_service.dart';
import '../../core/session.dart';

/// Clears the session and re-enters the flavor's _SessionGate at '/home',
/// which then falls through to LoginScreen since there's no session left.
class LogoutButton extends StatelessWidget {
  const LogoutButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.logout),
      tooltip: 'تسجيل الخروج',
      onPressed: () async {
        // No-op on customer/merchant (the service is never started there)
        // — driver-only safety net so a signed-out account never keeps
        // pinging location in the background under a stale session.
        await stopDriverBackgroundService();
        await SessionStore.clear();
        if (context.mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
        }
      },
    );
  }
}
