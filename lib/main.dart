import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/supabase_config.dart';
import 'core/router/app_router.dart';
import 'core/sync/sync_service.dart';
import 'core/theme/chapel_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');
  await initSupabase();

  runApp(const ProviderScope(child: BishopricTrackerApp()));
}

class BishopricTrackerApp extends ConsumerWidget {
  const BishopricTrackerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    // Keep the seed-on-login listener active for the app's lifetime.
    ref.watch(seedOnLoginProvider);

    return MaterialApp.router(
      title: 'Bishopric Tracker',
      debugShowCheckedModeBanner: false,
      theme: buildChapelTheme(),
      routerConfig: router,
    );
  }
}
