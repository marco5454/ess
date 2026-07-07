import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';

/// Bootstrap for the Supabase client.
///
/// Call [initSupabase] once, from `main()`, after `dotenv.load(...)` has
/// completed and before `runApp(...)`.
Future<void> initSupabase() async {
  await Supabase.initialize(
    url: Env.supabaseUrl,
    // Supabase renamed `anonKey` to `publishableKey` in v2.16+.
    // The value semantically is still the project's public/anon key.
    publishableKey: Env.supabaseAnonKey,
  );
}

/// Convenience accessor for the initialized Supabase client.
///
/// Only valid after [initSupabase] has completed.
SupabaseClient get supabase => Supabase.instance.client;
