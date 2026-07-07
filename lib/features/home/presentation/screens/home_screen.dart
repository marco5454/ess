import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/supabase_config.dart';

/// Phase 1 home screen shell.
///
/// Placeholder for the authenticated area. Currently offers a sign-out action
/// so the full auth loop can be exercised end-to-end.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bishopric Tracker'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => supabase.auth.signOut(),
          ),
        ],
      ),
      body: const Center(
        child: Text('Home (placeholder)'),
      ),
    );
  }
}
