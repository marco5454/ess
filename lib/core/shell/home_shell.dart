import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/callings/presentation/screens/dashboard_screen.dart';
import '../../features/callings/presentation/screens/summary_screen.dart';
import '../../features/members/presentation/screens/members_list_screen.dart';
import '../sync/connectivity_service.dart';
import '../sync/outbox_dao.dart';
import '../sync/outbox_providers.dart';
import '../theme/chapel_theme.dart';

/// Root shell for the authenticated app.
///
/// Hosts a bottom [NavigationBar] with three tabs — Summary, Dashboard,
/// and Members — inside an [IndexedStack] so each tab preserves its state
/// (scroll position, search query) when the user switches away and back.
/// Each tab screen owns its own [Scaffold] / [AppBar] so it can supply
/// tab-specific actions, FABs, and search fields.
///
/// A slim status strip above the stack surfaces two things when relevant:
/// an offline banner and a pending-writes pill (count of outbox rows
/// still waiting to be pushed to Supabase).
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
      body: Column(
        children: [
          const _SyncStatusStrip(),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: const [
                SummaryScreen(),
                DashboardScreen(),
                MembersListScreen(),
              ],
            ),
          ),
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

/// Slim horizontal strip below the AppBar that shows:
///
/// - a navy "Offline mode" banner when the device has no connectivity;
/// - a gold "N pending" pill when the outbox has queued writes waiting to
///   be pushed to Supabase.
///
/// Both are `SizedBox.shrink()` when there is nothing to say, so the strip
/// takes no vertical space when the app is online with an empty outbox.
class _SyncStatusStrip extends ConsumerWidget {
  const _SyncStatusStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectivity = ref.watch(connectivityStatusProvider);
    final isOffline = connectivity.value == false;

    final pendingAsync = ref.watch(_pendingOutboxCountProvider);
    final pending = pendingAsync.value ?? 0;

    if (!isOffline && pending == 0) {
      return const SizedBox.shrink();
    }

    return Material(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isOffline) const _OfflineBanner(),
          if (pending > 0) _PendingBanner(count: pending),
        ],
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: ChapelPalette.navyDark,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.cloud_off, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Offline mode — changes are saved locally and will sync when '
              'you reconnect.',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingBanner extends StatelessWidget {
  const _PendingBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = count == 1 ? '1 change pending sync' : '$count changes pending sync';
    return Container(
      color: ChapelPalette.goldLight,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.sync, color: ChapelPalette.goldDark, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: ChapelPalette.goldDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Live count of pending outbox rows, streamed from Drift. Wraps
/// [OutboxDao.watchPendingCount] into a Riverpod [StreamProvider] so the
/// banner rebuilds automatically when writes are enqueued or drained.
final _pendingOutboxCountProvider = StreamProvider<int>((ref) {
  final OutboxDao dao = ref.watch(outboxDaoProvider);
  return dao.watchPendingCount();
});
