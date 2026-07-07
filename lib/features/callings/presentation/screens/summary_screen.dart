import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/router/app_router.dart';
import '../../domain/entities/calling_state.dart';
import '../providers/callings_providers.dart';

/// Ward-wide summary of callings.
///
/// Two tabs:
///   * **By organization** — every "in service" calling grouped by
///     `calling.organization`. In-service = latest event state is one of
///     extended / accepted / sustained / set_apart / active. Terminal states
///     (declined, released) and the internal `selected` state are excluded.
///   * **Needs attention** — pipeline callings that haven't advanced in a
///     while: latest state is `selected` or `extended` and its `occurred_at`
///     is older than 14 days.
class SummaryScreen extends ConsumerStatefulWidget {
  const SummaryScreen({super.key});

  @override
  ConsumerState<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends ConsumerState<SummaryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const _inServiceStates = <CallingState>{
    CallingState.extended,
    CallingState.accepted,
    CallingState.sustained,
    CallingState.setApart,
    CallingState.active,
  };

  /// A pipeline calling that hasn't moved in this long lands in the attention
  /// tab. Fourteen days is arbitrary — long enough to ignore normal Sunday
  /// cadence, short enough to flag genuinely stalled calls.
  static const _staleThreshold = Duration(days: 14);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final summaryAsync = ref.watch(callingSummaryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ward summary'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => supabase.auth.signOut(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'By organization'),
            Tab(text: 'Needs attention'),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(callingSummaryProvider),
        child: summaryAsync.when(
          data: (rows) => TabBarView(
            controller: _tabController,
            children: [
              _ByOrganizationTab(rows: rows, states: _inServiceStates),
              _NeedsAttentionTab(rows: rows, threshold: _staleThreshold),
            ],
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ListView(
            children: [
              const SizedBox(height: 120),
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Failed to load summary:\n$error',
                      textAlign: TextAlign.center),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ByOrganizationTab extends StatelessWidget {
  const _ByOrganizationTab({required this.rows, required this.states});

  final List<CallingSummaryRow> rows;
  final Set<CallingState> states;

  static const _unassignedKey = '__unassigned__';
  static const _unassignedLabel = 'Unassigned';

  @override
  Widget build(BuildContext context) {
    final inService = rows
        .where((r) =>
            r.latestEvent != null && states.contains(r.latestEvent!.state))
        .toList();

    if (inService.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 120),
          Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No callings in service yet.\nExtend a calling to see it here.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      );
    }

    // Group by organization; keep an 'Unassigned' bucket for null/empty orgs.
    final groups = <String, List<CallingSummaryRow>>{};
    for (final row in inService) {
      final org = row.calling.organization?.trim();
      final key = (org == null || org.isEmpty) ? _unassignedKey : org;
      groups.putIfAbsent(key, () => []).add(row);
    }
    // Named groups alphabetically, then 'Unassigned' pinned to the bottom.
    final namedKeys = groups.keys.where((k) => k != _unassignedKey).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final orderedKeys = <String>[
      ...namedKeys,
      if (groups.containsKey(_unassignedKey)) _unassignedKey,
    ];

    return ListView(
      children: [
        for (final key in orderedKeys) ...[
          _SectionHeader(
            title: key == _unassignedKey ? _unassignedLabel : key,
            count: groups[key]!.length,
          ),
          for (final row in _sortRows(groups[key]!))
            _CallingRow(row: row, showOrganization: false),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  List<CallingSummaryRow> _sortRows(List<CallingSummaryRow> rows) {
    final sorted = [...rows];
    sorted.sort((a, b) {
      final aTitle = a.calling.title.toLowerCase();
      final bTitle = b.calling.title.toLowerCase();
      final byTitle = aTitle.compareTo(bTitle);
      if (byTitle != 0) return byTitle;
      final aMember = (a.member?.sortName ?? '').toLowerCase();
      final bMember = (b.member?.sortName ?? '').toLowerCase();
      return aMember.compareTo(bMember);
    });
    return sorted;
  }
}

class _NeedsAttentionTab extends StatelessWidget {
  const _NeedsAttentionTab({required this.rows, required this.threshold});

  final List<CallingSummaryRow> rows;
  final Duration threshold;

  static const _pipelineStates = <CallingState>{
    CallingState.selected,
    CallingState.extended,
  };

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final stale = rows.where((r) {
      final event = r.latestEvent;
      if (event == null) return false;
      if (!_pipelineStates.contains(event.state)) return false;
      return now.difference(event.occurredAt) >= threshold;
    }).toList();

    if (stale.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Nothing needs attention.\nPipeline callings older than '
                '${threshold.inDays} days will show up here.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      );
    }

    // Oldest first — the most urgent land at the top.
    stale.sort((a, b) => a.latestEvent!.occurredAt
        .compareTo(b.latestEvent!.occurredAt));

    return ListView(
      children: [
        _SectionHeader(
          title: 'Stalled in pipeline (${threshold.inDays}+ days)',
          count: stale.length,
        ),
        for (final row in stale) _CallingRow(row: row, showOrganization: true),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '$count',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _CallingRow extends StatelessWidget {
  const _CallingRow({required this.row, required this.showOrganization});

  final CallingSummaryRow row;
  final bool showOrganization;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final calling = row.calling;
    final member = row.member;
    final event = row.latestEvent;

    final subtitleParts = <String>[
      if (member != null) member.displayName,
      if (showOrganization &&
          calling.organization != null &&
          calling.organization!.isNotEmpty)
        calling.organization!,
    ];
    if (event != null) {
      subtitleParts.add(_formatOccurred(event.occurredAt));
    }

    return ListTile(
      title: Text(calling.title),
      subtitle: subtitleParts.isEmpty
          ? null
          : Text(subtitleParts.join(' • '),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      trailing: event == null
          ? const Icon(Icons.chevron_right)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StateChip(state: event.state),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right),
              ],
            ),
      onTap: member == null
          ? null
          : () => context.push(
                AppRoutes.callingDetail(member.id, calling.id),
              ),
    );
  }

  String _formatOccurred(DateTime value) {
    final local = value.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.state});

  final CallingState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = state.isTerminal
        ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.secondaryContainer;
    final fg = state.isTerminal
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.onSecondaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(state.label,
          style: theme.textTheme.labelSmall?.copyWith(color: fg)),
    );
  }
}
