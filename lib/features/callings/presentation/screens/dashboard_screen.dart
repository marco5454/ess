import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/chapel_icon.dart';
import '../../../../core/theme/chapel_theme.dart';
import '../../domain/entities/calling_state.dart';
import '../providers/callings_providers.dart';

/// Aggregate view of every calling in the ward, grouped by lifecycle state.
///
/// Renders a hero "Stale in pipeline" card (callings sitting in
/// `selected` or `extended` past [dashboardStaleThreshold]) plus a grid
/// of eight per-state tiles. Every tile is tappable and drills down to
/// the underlying callings via [AppRoutes.callingsInState].
///
/// Fully live — the counts recompute automatically whenever a calling
/// event is recorded, deleted, or a calling is created / removed.
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
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          // Force resubscribe on all three upstream streams.
          ref.invalidate(allCallingsStreamProvider);
          ref.invalidate(allEventsStreamProvider);
        },
        child: countsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
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

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.counts});

  final DashboardCounts counts;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _StaleCard(
          count: counts.staleInPipeline,
          thresholdDays: dashboardStaleThreshold.inDays,
        ),
        const SizedBox(height: 20),
        Text(
          'By state',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          '${counts.totalWithState} callings tracked',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            // Two tiles per row on phones, three on wider screens.
            final crossAxisCount = constraints.maxWidth >= 600 ? 3 : 2;
            return GridView.count(
              crossAxisCount: crossAxisCount,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.35,
              children: CallingState.values
                  .map((s) => _StateTile(
                        state: s,
                        count: counts.byState[s] ?? 0,
                      ))
                  .toList(growable: false),
            );
          },
        ),
      ],
    );
  }
}

class _StaleCard extends StatelessWidget {
  const _StaleCard({required this.count, required this.thresholdDays});

  final int count;
  final int thresholdDays;

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
        onTap: hasStale
            ? () {
                // Route users to the existing "Needs attention" tab on the
                // Summary screen — same threshold, ready-made list.
                // Cheapest useful action: encourage the user to switch tabs
                // manually. (No deep-link into a tabbed screen for now.)
              }
            : null,
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
                      hasStale
                          ? '$count stale in pipeline'
                          : 'No stale pipeline items',
                      style: theme.textTheme.titleLarge?.copyWith(color: fg),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasStale
                          ? 'Selected or extended for $thresholdDays+ days. '
                              'Check the "Needs attention" tab on Summary.'
                          : 'Everything in the pipeline is <$thresholdDays days old.',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: fg.withValues(alpha: 0.9)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StateTile extends StatelessWidget {
  const _StateTile({required this.state, required this.count});

  final CallingState state;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Empty tiles get a subdued treatment so the eye tracks non-zero
    // counts. Pipeline states glow in gold, in-service states in sage,
    // terminal states in a neutral paper tone.
    final isEmpty = count == 0;

    final Color bg;
    final Color fg;
    if (isEmpty) {
      bg = scheme.surfaceContainerHighest;
      fg = scheme.onSurfaceVariant;
    } else {
      switch (state) {
        case CallingState.selected:
        case CallingState.extended:
        case CallingState.accepted:
          bg = ChapelPalette.goldLight;
          fg = ChapelPalette.goldDark;
          break;
        case CallingState.sustained:
        case CallingState.setApart:
        case CallingState.active:
          bg = ChapelPalette.sageLight;
          fg = const Color(0xFF2E4A2E);
          break;
        case CallingState.declined:
        case CallingState.released:
          bg = scheme.surfaceContainerHigh;
          fg = scheme.onSurface;
          break;
      }
    }

    return Card(
      color: bg,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => context.push(AppRoutes.callingsInState(state.wireName)),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                state.label,
                style: theme.textTheme.labelLarge?.copyWith(color: fg),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$count',
                    style: theme.textTheme.displaySmall?.copyWith(
                          color: fg,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  Icon(Icons.chevron_right, color: fg),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
