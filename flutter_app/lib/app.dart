import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/flavor.dart';
import 'core/notifications.dart';
import 'core/session.dart';
import 'core/supabase_client.dart';
import 'core/theme.dart';
import 'features/auth/login_screen.dart';
import 'features/driver/driver_home_screen.dart';
import 'features/home/home_shell.dart';
import 'features/merchant/merchant_home_screen.dart';

/// Shared entry point for all three build flavors — main_customer.dart,
/// main_driver.dart, and main_merchant.dart each just call this with their
/// own FlavorConfig. Same widgets/repositories, different app per audience
/// (own icon/name/package id via the Android product flavors).
Future<void> runWslhaApp(FlavorConfig config) async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSupabase();
  await AppNotifications.instance.init();
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
      theme: buildAppTheme(),
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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserSession?>(
      future: SessionStore.load(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final session = snapshot.data;
        if (session == null) return LoginScreen(config: config);

        // Defensive re-check (e.g. a session saved before a role changed
        // server-side) — the login screen already blocks the wrong role
        // from getting this far in the normal case.
        if (session.role != config.allowedRole) {
          return _WrongRoleScreen(config: config);
        }

        return switch (config.flavor) {
          AppFlavor.customer => HomeShell(session: session),
          AppFlavor.driver => DriverHomeScreen(session: session),
          AppFlavor.merchant => MerchantHomeScreen(session: session),
        };
      },
    );
  }
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
