import 'package:flutter/material.dart';

/// Phase 1 home screen shell.
///
/// UI-only placeholder confirming the authenticated route renders. Dashboard,
/// member list, and other features arrive in later phases.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bishopric Tracker')),
      body: const Center(
        child: Text('Home (placeholder)'),
      ),
    );
  }
}
