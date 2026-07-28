import 'package:flutter/material.dart';
import 'core/session.dart';
import 'core/supabase_client.dart';
import 'core/theme.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSupabase();
  runApp(const WslhaApp());
}

class WslhaApp extends StatelessWidget {
  const WslhaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'وصّلها',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: const Locale('ar'),
      localizationsDelegates: const [
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ar'), Locale('en')],
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const _SessionGate(),
      routes: {
        '/login': (_) => const LoginScreen(),
        '/home': (_) => const _SessionGate(),
      },
    );
  }
}

/// Decides whether to land on the login screen or the home shell based on
/// the persisted session (SharedPreferences-backed, mirrors the web app's
/// localStorage.wslha_user check in every page's auth guard).
class _SessionGate extends StatelessWidget {
  const _SessionGate();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserSession?>(
      future: SessionStore.load(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final session = snapshot.data;
        if (session == null) return const LoginScreen();
        return HomeShell(session: session);
      },
    );
  }
}
