import 'package:supabase_flutter/supabase_flutter.dart';

/// Same Supabase project + publishable anon key the web app uses
/// (src/utils/supabaseClient.ts) — no backend changes, this app talks to
/// the exact same tables/RPCs/Edge Functions.
const String supabaseUrl = 'https://vtikgyiopkjnrwlqnmfx.supabase.co';
const String supabaseAnonKey = 'sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4';

Future<void> initSupabase() async {
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
}

SupabaseClient get sb => Supabase.instance.client;
