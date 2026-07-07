import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Typed access to environment variables loaded from the bundled `.env` asset.
///
/// Call [DotEnv.load] (via `dotenv.load(...)`) from `main()` before reading
/// any of these values.
class Env {
  const Env._();

  static String get supabaseUrl => _require('SUPABASE_URL');

  static String get supabaseAnonKey => _require('SUPABASE_ANON_KEY');

  static String _require(String key) {
    final value = dotenv.env[key];
    if (value == null || value.isEmpty) {
      throw StateError(
        'Missing required environment variable "$key". '
        'Ensure it is set in the `.env` file at the project root and that '
        '`.env` is registered under `flutter.assets` in pubspec.yaml.',
      );
    }
    return value;
  }
}
