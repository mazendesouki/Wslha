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
      body: Container(
        width: double.infinity,
        height: double.infinity,
        // Same teal brand gradient every other full-screen gate in this
        // app uses (login_screen.dart's header, the admin panel's
        // pass-gate) — this screen previously had none at all (a bare
        // "⬆️" emoji on a plain white background), the one screen in the
        // app with no brand identity whatsoever despite being the most
        // "official-looking" one a user needs to actually trust enough to
        // tap a button that downloads and installs a new APK.
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.primary, AppColors.primaryDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 6))],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset('assets/branding/logo.png', fit: BoxFit.cover),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    context.tr('update_required_title'),
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr('update_required_body'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  if (info.versionName.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${context.tr('update_required_version_prefix')} ${info.versionName}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                  ],
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _openUpdateLink,
                      child: Text(
                        context.tr('update_required_button'),
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
