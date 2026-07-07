import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');
  await initSupabase();

  runApp(const ProviderScope(child: BishopricTrackerApp()));
}

class BishopricTrackerApp extends StatelessWidget {
  const BishopricTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bishopric Tracker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const _BootstrapPlaceholder(),
    );
  }
}

/// Temporary placeholder screen used to confirm the app boots and Supabase
/// initializes successfully. Will be replaced by the router + auth screens in
/// the next chunk.
class _BootstrapPlaceholder extends StatelessWidget {
  const _BootstrapPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text('Supabase initialized'),
      ),
    );
  }
}
