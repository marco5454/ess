import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/callings/presentation/screens/dashboard_screen.dart';
import '../../features/callings/presentation/screens/summary_screen.dart';
import '../../features/members/presentation/screens/members_list_screen.dart';

/// Root shell for the authenticated app.
///
/// Hosts a bottom [NavigationBar] with three tabs — Summary, Dashboard,
/// and Members — inside an [IndexedStack] so each tab preserves its state
/// (scroll position, search query) when the user switches away and back.
/// Each tab screen owns its own [Scaffold] / [AppBar] so it can supply
/// tab-specific actions, FABs, and search fields.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          SummaryScreen(),
          DashboardScreen(),
          MembersListScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.view_agenda_outlined),
            selectedIcon: Icon(Icons.view_agenda),
            label: 'Summary',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Members',
          ),
        ],
      ),
    );
  }
}
