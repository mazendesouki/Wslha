import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/feature_flags.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/sos_service.dart';
import '../../core/theme.dart';
import '../../features/safety/emergency_contacts_screen.dart';

/// The زرار طوارئ shown during an active ride (both customer and driver
/// views) — a hold-to-confirm dialog (3s countdown, cancelable) guards
/// against an accidental tap before SosService actually fires.
class SosButton extends StatelessWidget {
  final String role; // 'customer' | 'driver'
  final String? rideId;
  const SosButton({super.key, required this.role, this.rideId});

  Future<void> _openConfirm(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _SosCountdownDialog(),
    );
    if (confirmed != true || !context.mounted) return;

    final session = await SessionStore.load();
    if (session == null || !context.mounted) return;

    final result = await SosService().trigger(phone: session.phone, role: role, rideId: rideId);
    if (!context.mounted) return;

    if (!result.hadContacts) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr('sos_alert_no_contacts')),
        action: SnackBarAction(
          label: context.tr('sos_add_contacts_action'),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EmergencyContactsScreen())),
        ),
      ));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(result.smsOpened ? context.tr('sos_alert_sms_opened') : context.tr('sos_alert_logged')),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (!FeatureFlags.sosEnabled) return const SizedBox.shrink();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => _openConfirm(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(999)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.sos, color: Colors.white, size: 18),
              const SizedBox(width: 6),
              Text(context.tr('sos_button_label'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SosCountdownDialog extends StatefulWidget {
  @override
  State<_SosCountdownDialog> createState() => _SosCountdownDialogState();
}

class _SosCountdownDialogState extends State<_SosCountdownDialog> {
  int _secondsLeft = 3;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 1) {
        t.cancel();
        Navigator.of(context).pop(true);
        return;
      }
      setState(() => _secondsLeft--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('sos_countdown_title')),
      content: Text(context.tr('sos_countdown_body').replaceAll('SECONDS', '$_secondsLeft')),
      actions: [
        TextButton(
          onPressed: () {
            _timer?.cancel();
            Navigator.of(context).pop(false);
          },
          child: Text(context.tr('sos_countdown_cancel')),
        ),
      ],
    );
  }
}
