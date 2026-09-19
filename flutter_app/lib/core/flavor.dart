import 'package:flutter/material.dart';

/// Same codebase, three build targets (Flutter product flavors) instead of
/// one app that shows different screens after login — each audience gets
/// its own installable app (own icon/name/package id), but all three share
/// every widget/repository in lib/. Admin stays web-only (admin.astro is
/// already a full, mobile-responsive panel — no native admin app planned).
enum AppFlavor { customer, driver, merchant }

class FlavorConfig {
  final AppFlavor flavor;
  final String appTitle;
  final String allowedRole; // must match accounts.role for this build
  final String wrongRoleMessage;
  // Splash screen (shared/widgets/animated_splash.dart): a small
  // service-identifying icon shown above the logo, distinct per flavor
  // since each build serves a different audience.
  final IconData splashIcon;

  const FlavorConfig._(this.flavor, this.appTitle, this.allowedRole, this.wrongRoleMessage, this.splashIcon);

  static const customer = FlavorConfig._(
    AppFlavor.customer,
    'وصّلها',
    'customer',
    'هذا التطبيق مخصص للعملاء — لتطبيق السائقين أو التجار حمّل النسخة المناسبة.',
    Icons.map_outlined,
  );

  static const driver = FlavorConfig._(
    AppFlavor.driver,
    'وصّلها سائق',
    'driver',
    'هذا التطبيق مخصص للسائقين المعتمدين فقط.',
    Icons.local_taxi_outlined,
  );

  static const merchant = FlavorConfig._(
    AppFlavor.merchant,
    'وصّلها تاجر',
    'merchant',
    'هذا التطبيق مخصص لأصحاب المتاجر فقط.',
    Icons.storefront_outlined,
  );
}
