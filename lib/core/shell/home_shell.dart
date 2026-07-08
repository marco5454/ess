import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/callings/presentation/screens/dashboard_screen.dart';
import '../../features/callings/presentation/screens/summary_screen.dart';
import '../../features/members/presentation/screens/members_list_screen.dart';
import '../motion/motion.dart';
import '../sync/connectivity_service.dart';
import '../sync/outbox_dao.dart';
import '../sync/outbox_providers.dart';
import '../theme/chapel_theme.dart';

/// Which tab of the [HomeShell]'s bottom [NavigationBar] is currently
/// active. Exposed as a Riverpod provider so any screen inside the shell
/// can request a tab switch — for example, the Dashboard's "Needs
/// attention" hero flips the user to the Summary tab.
///
/// Indices match the order in the shell's [IndexedStack]:
/// 0 = Summary, 1 = Dashboard, 2 = Members.
final homeShellTabProvider =
    NotifierProvider<HomeShellTabNotifier, int>(HomeShellTabNotifier.new);

class HomeShellTabNotifier extends Notifier<int> {
  @override
  int build() => 0;

  /// Set the active tab. Callers should use this instead of mutating
  /// `state` directly so intent reads clearly at call sites.
  void select(int index) => state = index;
}

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
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(homeShellTabProvider);
    return Scaffold(
      body: SafeArea(
        top: true,
        bottom: false,
        child: Column(
          children: [
            const _SyncStatusStrip(),
            Expanded(
              child: IndexedStack(
                index: index,
                children: const [
                  SummaryScreen(),
                  DashboardScreen(),
                  MembersListScreen(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) =>
            ref.read(homeShellTabProvider.notifier).select(i),
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

    // Animate the strip's height as banners appear/disappear so it slides
    // down smoothly rather than popping in.
    return Material(
      color: Colors.transparent,
      child: AnimatedSize(
        duration: MotionDurations.medium,
        curve: MotionCurves.enter,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedSwitcher(
              duration: MotionDurations.medium,
              switchInCurve: MotionCurves.enter,
              switchOutCurve: MotionCurves.exit,
              transitionBuilder: _slideFadeVertical,
              child: isOffline
                  ? const _OfflineBanner(key: ValueKey('offline'))
                  : const SizedBox.shrink(key: ValueKey('offline-empty')),
            ),
            AnimatedSwitcher(
              duration: MotionDurations.medium,
              switchInCurve: MotionCurves.enter,
              switchOutCurve: MotionCurves.exit,
              transitionBuilder: _slideFadeVertical,
              child: pending > 0
                  ? _PendingBanner(
                      key: ValueKey('pending-$pending'),
                      count: pending,
                    )
                  : const SizedBox.shrink(key: ValueKey('pending-empty')),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _slideFadeVertical(Widget child, Animation<double> animation) {
  final offset = Tween<Offset>(
    begin: const Offset(0, -0.35),
    end: Offset.zero,
  ).animate(animation);
  return ClipRect(
    child: SlideTransition(
      position: offset,
      child: FadeTransition(opacity: animation, child: child),
    ),
  );
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({super.key});

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
  const _PendingBanner({super.key, required this.count});

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
