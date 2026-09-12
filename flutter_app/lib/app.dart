import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/flavor.dart';
import 'core/notifications.dart';
import 'core/pricing_settings.dart';
import 'core/push.dart';
import 'core/session.dart';
import 'core/supabase_client.dart';
import 'core/theme.dart';
import 'features/auth/login_screen.dart';
import 'features/driver/driver_home_shell.dart';
import 'features/home/home_shell.dart';
import 'features/merchant/merchant_home_screen.dart';
import 'features/orders/order_invoice_screen.dart';
import 'features/orders/orders_repository.dart';
import 'features/rides/ride_repository.dart';
import 'features/rides/ride_tracking_screen.dart';
import 'shared/widgets/animated_splash.dart';

/// Shared entry point for all three build flavors — main_customer.dart,
/// main_driver.dart, and main_merchant.dart each just call this with their
/// own FlavorConfig. Same widgets/repositories, different app per audience
/// (own icon/name/package id via the Android product flavors).
Future<void> runWslhaApp(FlavorConfig config) async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSupabase();
  await AppNotifications.instance.init();
  // Fire-and-forget: admin-configurable pricing (see core/pricing_settings.dart).
  // Booking screens read PricingSettings synchronously, so a slow/failed
  // fetch just means the first quote after launch uses the hardcoded
  // defaults rather than blocking startup on a network call.
  unawaited(PricingSettings.load());
  runApp(WslhaApp(config: config));
}

class WslhaApp extends StatelessWidget {
  final FlavorConfig config;
  const WslhaApp({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: config.appTitle,
      debugShowCheckedModeBanner: false,
      // "modern" is trialled on the customer app only for now — see
      // core/theme.dart's buildAppTheme() doc comment.
      theme: buildAppTheme(modern: config.flavor == AppFlavor.customer),
      locale: const Locale('ar'),
      // DefaultMaterialLocalizations/DefaultWidgetsLocalizations only ever
      // support English — that's the "no real localization" fallback, not
      // an Arabic implementation. Using them with locale('ar') left every
      // Material widget (TextField, Form, ...) unable to resolve
      // MaterialLocalizations at all, crashing with "No MaterialLocalizations
      // found". The Global* delegates from flutter_localizations ship
      // Flutter's real Arabic translations.
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ar'), Locale('en')],
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
      home: _SessionGate(config: config),
      routes: {
        '/home': (_) => _SessionGate(config: config),
      },
    );
  }
}

class _SessionGate extends StatelessWidget {
  final FlavorConfig config;
  const _SessionGate({required this.config});

  /// The splash's own entrance animation is ~900ms — waiting on this
  /// alongside the real session fetch keeps a fast load from cutting it
  /// off mid-animation, without adding a fixed delay when the session
  /// fetch is the slower of the two.
  static Future<UserSession?> _loadWithMinimumSplash() async {
    final results = await Future.wait([
      SessionStore.load(),
      Future.delayed(const Duration(milliseconds: 1100)),
    ]);
    return results[0] as UserSession?;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserSession?>(
      future: _loadWithMinimumSplash(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return AnimatedSplash(appTitle: config.appTitle);
        }
        final session = snapshot.data;
        if (session == null) return LoginScreen(config: config);

        // Defensive re-check (e.g. a session saved before a role changed
        // server-side) — the login screen already blocks the wrong role
        // from getting this far in the normal case.
        if (session.role != config.allowedRole) {
          return _WrongRoleScreen(config: config);
        }

        // Re-registers on every cold start with an existing session (not
        // just right after login) — guarded per-phone inside PushRegistrar,
        // so this is a cheap no-op once already registered this run.
        unawaited(PushRegistrar.registerForSession(session));

        final homeScreen = switch (config.flavor) {
          AppFlavor.customer => HomeShell(session: session),
          AppFlavor.driver => DriverHomeShell(session: session),
          AppFlavor.merchant => MerchantHomeScreen(session: session),
        };
        // Customer-only: there's no dedicated full-screen tracking view to
        // resume into for merchant, and the driver flavor now restores its
        // own native active-job card (ActiveJobStore) from
        // DriverHomeScreen.initState() instead — pushing this same generic
        // RideTrackingScreen on top of it looked like a second, wrong
        // screen missing the driver's usual live-navigation/contact card.
        if (config.flavor != AppFlavor.customer) return homeScreen;
        return _ResumeActiveRide(phone: session.phone, child: homeScreen);
      },
    );
  }
}

/// Customer-only: wraps the normal home screen and, once it's actually on
/// screen, checks for a ride or delivery order this phone is still "in"
/// and pushes straight into its tracking screen if one exists — see
/// findActiveRide()'s doc comment for why this is needed (Android
/// reclaiming the backgrounded app resets Flutter's navigation to this
/// default route, which otherwise looks like the ride/order just
/// vanished). Runs once per cold start, not on every rebuild. If both a
/// ride and an order are somehow active at once, resumes into whichever
/// was created more recently (see findActiveOrder()'s doc comment).
class _ResumeActiveRide extends StatefulWidget {
  final String phone;
  final Widget child;
  const _ResumeActiveRide({required this.phone, required this.child});

  @override
  State<_ResumeActiveRide> createState() => _ResumeActiveRideState();
}

class _ResumeActiveRideState extends State<_ResumeActiveRide> {
  final _rideRepo = RideRepository();
  final _ordersRepo = OrdersRepository();
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    if (_checked || !mounted) return;
    _checked = true;
    final results = await Future.wait([
      _rideRepo.findActiveRide(widget.phone, asDriver: false).catchError((_) => null),
      _ordersRepo.findActiveOrder(widget.phone).catchError((_) => null),
    ]);
    final ride = results[0];
    final order = results[1];
    if (ride == null && order == null || !mounted) return;

    // Resume whichever is actually more recent — always favoring the ride
    // meant a customer with any stray never-finished ride sitting in their
    // history (a cancelled test, an old bug) would get sent back into
    // that forever instead of a genuinely newer order.
    final rideNewer = order == null ||
        (ride != null && (DateTime.tryParse(ride['created_at'] as String? ?? '') ?? DateTime(0))
            .isAfter(DateTime.tryParse(order['created_at'] as String? ?? '') ?? DateTime(0)));

    if (rideNewer && ride != null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => RideTrackingScreen(rideId: ride['id'] as String)),
      );
    } else if (order != null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => OrderInvoiceScreen(orderId: order['id'] as String)),
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _WrongRoleScreen extends StatelessWidget {
  final FlavorConfig config;
  const _WrongRoleScreen({required this.config});

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
                const Text('🚫', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 16),
                Text(config.wrongRoleMessage, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () async {
                    await SessionStore.clear();
                    if (context.mounted) {
                      Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
                    }
                  },
                  child: const Text('تسجيل الخروج'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
