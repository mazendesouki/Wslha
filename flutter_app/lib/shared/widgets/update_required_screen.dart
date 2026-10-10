import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/update_checker.dart';

/// Full-screen, un-missable "update the app" prompt — shown ahead of any
/// other screen (including gated ones like the driver's approval-status
/// check) whenever a newer build has been published.
///
/// Exists because the original update signal (a small badge dot on the
/// settings tab icon — still there, see driver_home_shell.dart/
/// home_shell.dart) turned out to be unreachable in exactly the situation
/// it most needed to fire: an outdated driver build started getting
/// `permission denied` on direct table reads after security-122/123/124
/// locked several tables down to RPC-only access, which made
/// fetchApprovalStatus() throw and fall back to a non-'approved' status —
/// landing the driver on the pending-approval screen *before* the bottom
/// nav (and its update badge) ever rendered. The driver had no way to
/// learn an update even existed. This screen is checked first, so it
/// can't be hidden behind another gate again.
class UpdateRequiredScreen extends StatelessWidget {
  final UpdateInfo info;
  const UpdateRequiredScreen({super.key, required this.info});

  Future<void> _openUpdateLink() async {
    await launchUrl(Uri.parse(info.apkUrl), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('⬆️', style: TextStyle(fontSize: 56)),
                const SizedBox(height: 16),
                Text(
                  context.tr('update_required_title'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr('update_required_body'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textFaint),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _openUpdateLink,
                  child: Text(context.tr('update_required_button')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
