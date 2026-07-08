import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/motion/skeletons.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/shell/home_shell.dart';
import '../../../../core/theme/chapel_icon.dart';
import '../../../../core/theme/chapel_theme.dart';
import '../../domain/entities/calling_state.dart';
import '../providers/callings_providers.dart';

/// Executive-briefing view of the ward's callings.
///
/// The dashboard is deliberately opinionated about hierarchy: it is *not*
/// a uniform grid of every state. It is meant to answer three questions,
/// in this order, at a glance:
///
///   1. Is anything demanding my attention right now? → the attention card.
///   2. Where are things flowing? → the pipeline strip (selected → set apart).
///   3. What just changed? → the recent activity list.
///
/// Terminal states (`declined`, `released`) are demoted to a footer link
/// because for day-to-day bishopric use they are history, not action items.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countsAsync = ref.watch(dashboardCountsProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const Padding(
          padding: EdgeInsets.all(12),
          child: ChapelIcon(size: 24),
        ),
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.assignment_outlined),
            tooltip: 'Bishopric agenda',
            onPressed: () => context.push(AppRoutes.agenda),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About',
            onPressed: () => context.push(AppRoutes.about),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          // Force resubscribe on all three upstream streams so a manual
          // pull reflects any silent server-side changes.
          ref.invalidate(allCallingsStreamProvider);
          ref.invalidate(allEventsStreamProvider);
        },
        child: countsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.only(top: 8),
            child: DashboardSkeleton(),
          ),
          error: (e, _) => ListView(
            children: [
              const SizedBox(height: 120),
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Failed to load dashboard:\n$e',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
          data: (counts) => _DashboardBody(counts: counts),
        ),
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({required this.counts});

  final DashboardCounts counts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final activeCount = counts.byState[CallingState.active] ?? 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _AttentionCard(
          count: counts.staleInPipeline,
          thresholdDays: dashboardStaleThreshold.inDays,
          onOpen: () {
            // The Summary screen's second tab is "Needs attention", which
            // already renders the stalled-pipeline list. Flipping the
            // shell's active tab is the cheapest useful action and keeps
            // this card an actual affordance rather than a decoration.
            ref.read(homeShellTabProvider.notifier).select(0);
          },
        ),
        const SizedBox(height: 24),
        Text(
          'Pipeline',
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${counts.totalWithState} callings tracked',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        _PipelineFlow(counts: counts),
        const SizedBox(height: 20),
        _ActiveHeadline(count: activeCount),
        const SizedBox(height: 24),
        Text(
          'Recent activity',
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        const _RecentActivityList(),
        const SizedBox(height: 20),
        _HistoryFooter(
          declinedCount: counts.byState[CallingState.declined] ?? 0,
          releasedCount: counts.byState[CallingState.released] ?? 0,
        ),
      ],
    );
  }
}

/// Hero card at the top of the dashboard. Two visual variants:
///
/// - **Amber**, when there are stalled pipeline items — communicates "look
///   at this" without shouting; tap flips to the Summary tab.
/// - **Sage**, when nothing is stalled — reassuring all-clear state.
///
/// A single card, not a KPI wall. If more attention signals appear later
/// (e.g. unfilled ordinance-required callings), they should chain into
/// this card as sub-items rather than sprout new cards.
class _AttentionCard extends StatelessWidget {
  const _AttentionCard({
    required this.count,
    required this.thresholdDays,
    required this.onOpen,
  });

  final int count;
  final int thresholdDays;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasStale = count > 0;
    final bg = hasStale ? ChapelPalette.amberLight : ChapelPalette.sageLight;
    final fg = hasStale ? ChapelPalette.amber : const Color(0xFF2E4A2E);
    final icon = hasStale ? Icons.watch_later_outlined : Icons.check_circle;

    return Card(
      color: bg,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: hasStale ? onOpen : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, size: 40, color: fg),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasStale ? 'Needs your attention' : 'All clear',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: fg.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasStale
                          ? '$count stalled in pipeline'
                          : 'No stalled pipeline items',
                      style: theme.textTheme.titleLarge?.copyWith(color: fg),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasStale
                          ? 'Selected or extended for $thresholdDays+ days. '
                              'Tap to review on Summary.'
                          : 'Everything is within $thresholdDays days.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: fg.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
              if (hasStale) Icon(Icons.chevron_right, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal flow of the five pipeline states, showing count under each
/// step and a chevron arrow between them.
///
/// Communicates *motion*: from "selected" a member walks left-to-right
/// toward "set apart". A flat 8-tile grid destroyed that story; this
/// preserves it. Chevrons render at reduced opacity so the eye reads the
/// numbers first, the connective tissue second.
///
/// Scrollable horizontally so on very narrow screens users can pan — we
/// don't shrink text or wrap because either would break the "one step per
/// column" reading model.
class _PipelineFlow extends StatelessWidget {
  const _PipelineFlow({required this.counts});

  final DashboardCounts counts;

  static const _steps = <CallingState>[
    CallingState.selected,
    CallingState.extended,
    CallingState.accepted,
    CallingState.sustained,
    CallingState.setApart,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chevronColor =
        theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < _steps.length; i++) ...[
            _PipelineStep(
              state: _steps[i],
              count: counts.byState[_steps[i]] ?? 0,
            ),
            if (i < _steps.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  Icons.chevron_right,
                  color: chevronColor,
                  size: 20,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _PipelineStep extends StatelessWidget {
  const _PipelineStep({required this.state, required this.count});

  final CallingState state;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEmpty = count == 0;

    // Non-empty pipeline steps glow gold — they're the ones with work
    // in progress. Empty ones use a subdued surface so the eye tracks
    // non-zero counts naturally.
    final Color bg;
    final Color fg;
    if (isEmpty) {
      bg = theme.colorScheme.surfaceContainerHighest;
      fg = theme.colorScheme.onSurfaceVariant;
    } else {
      bg = ChapelPalette.goldLight;
      fg = ChapelPalette.goldDark;
    }

    return SizedBox(
      width: 96,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () =>
              context.push(AppRoutes.callingsInState(state.wireName)),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  '$count',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-width headline card for the "active in ward" count.
///
/// Broken out from the pipeline flow because `active` is the *destination*
/// of the pipeline, not another step in it. Giving it a dedicated card
/// makes that role obvious and prevents it from visually dwarfing the
/// pipeline states (which it will, in a healthy ward, by orders of
/// magnitude).
class _ActiveHeadline extends StatelessWidget {
  const _ActiveHeadline({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      color: ChapelPalette.sageLight,
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push(
          AppRoutes.callingsInState(CallingState.active.wireName),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              const Icon(
                Icons.groups,
                size: 36,
                color: Color(0xFF2E4A2E),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Active in ward',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: const Color(0xFF2E4A2E),
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$count',
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: const Color(0xFF2E4A2E),
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Recent activity" list — up to 5 most recent state transitions
/// ward-wide, newest first. Each row is tappable and opens the calling
/// detail. Renders a friendly empty state when the ward has no events yet.
class _RecentActivityList extends ConsumerWidget {
  const _RecentActivityList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final activityAsync = ref.watch(recentActivityProvider);

    return activityAsync.when(
      // Skeleton isn't necessary here — the parent already gates on
      // `countsAsync`, and this provider warms from the same three streams,
      // so by the time the counts are ready the activity is essentially
      // ready too. A brief empty box is preferable to a shimmer flash.
      loading: () => const SizedBox(height: 60),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Failed to load activity: $e',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No activity yet.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          );
        }
        return Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                _RecentActivityTile(row: rows[i]),
                if (i < rows.length - 1)
                  const Divider(height: 1, indent: 16, endIndent: 16),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _RecentActivityTile extends StatelessWidget {
  const _RecentActivityTile({required this.row});

  final RecentActivityRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final memberName = row.member?.displayName ?? 'Unknown member';
    final memberId = row.member?.id ?? row.calling.memberId;

    return ListTile(
      dense: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(
        memberName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${row.calling.title} → ${row.event.state.label}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Text(
        _formatRelative(row.event.occurredAt),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      onTap: () =>
          context.push(AppRoutes.callingDetail(memberId, row.calling.id)),
    );
  }
}

/// Formats a past date as a short relative string suitable for the
/// activity list's trailing slot. Anything older than a week falls back to
/// `yyyy-MM-dd` so the timestamp still tells a story without hogging space.
String _formatRelative(DateTime when) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(when.year, when.month, when.day);
  final days = today.difference(that).inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return '${days}d ago';
  return '${when.year.toString().padLeft(4, '0')}-'
      '${when.month.toString().padLeft(2, '0')}-'
      '${when.day.toString().padLeft(2, '0')}';
}

/// Small footer that opens a bottom sheet with links to the two terminal
/// states. Kept out of the primary layout because for daily bishopric use
/// declined/released rows are history, not something a user wants to see
/// competing for attention with the pipeline.
class _HistoryFooter extends StatelessWidget {
  const _HistoryFooter({
    required this.declinedCount,
    required this.releasedCount,
  });

  final int declinedCount;
  final int releasedCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = declinedCount + releasedCount;

    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        style: TextButton.styleFrom(
          foregroundColor: theme.colorScheme.onSurfaceVariant,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          visualDensity: VisualDensity.compact,
        ),
        icon: const Icon(Icons.history, size: 18),
        label: Text(
          total == 0
              ? 'History'
              : 'History · $total',
        ),
        onPressed: () => _openSheet(context),
      ),
    );
  }

  void _openSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Text(
                    'History',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.cancel_outlined),
                  title: const Text('Declined'),
                  trailing: Text('$declinedCount'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    context.push(AppRoutes.callingsInState(
                        CallingState.declined.wireName));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.event_available_outlined),
                  title: const Text('Released'),
                  trailing: Text('$releasedCount'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    context.push(AppRoutes.callingsInState(
                        CallingState.released.wireName));
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
