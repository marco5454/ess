import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/motion/motion.dart';
import '../../../../core/motion/skeletons.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/sync/sync_service.dart';
import '../../../../core/theme/chapel_icon.dart';
import '../../../../core/theme/state_chip.dart';
import '../../../admin/presentation/providers/admin_providers.dart';
import '../../../members/presentation/providers/members_providers.dart';
import '../../domain/entities/calling_state.dart';
import '../providers/callings_providers.dart';

/// Ward-wide summary of callings.
///
/// Two tabs:
///   * **By organization** — every "in service" calling grouped by
///     `calling.organization`, rendered as **collapsible sections** so the
///     summary stays skimmable as the ward accumulates callings. Each section
///     header shows the org name and a count pill; tap to expand. An
///     "Expand all / Collapse all" affordance at the top lets the user flip
///     modes quickly. In-service = latest event state is one of extended /
///     accepted / sustained / set_apart / active. Terminal states (declined,
///     released) and the internal `selected` state are excluded.
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
    final isAdmin = ref.watch(isAdminProvider).value ?? false;

    return Scaffold(
      appBar: AppBar(
        leading: const Padding(
          padding: EdgeInsets.all(12),
          child: ChapelIcon(size: 24),
        ),
        title: const Text('Ward summary'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About',
            onPressed: () => context.push(AppRoutes.about),
          ),
          if (isAdmin) ...[
            IconButton(
              icon: const Icon(Icons.people_alt_outlined),
              tooltip: 'Users',
              onPressed: () => context.push(AppRoutes.adminUsers),
            ),
            IconButton(
              icon: const Icon(Icons.admin_panel_settings_outlined),
              tooltip: 'Invite codes',
              onPressed: () => context.push(AppRoutes.adminInviteCodes),
            ),
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: 'Activity log',
              onPressed: () => context.push(AppRoutes.adminAuditLog),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => performSignOut(ref),
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
        onRefresh: () async {
          ref.invalidate(allMembersStreamProvider);
          ref.invalidate(allCallingsStreamProvider);
          ref.invalidate(allEventsStreamProvider);
        },
        child: summaryAsync.when(
          data: (rows) => TabBarView(
            controller: _tabController,
            children: [
              _ByOrganizationTab(rows: rows, states: _inServiceStates),
              _NeedsAttentionTab(rows: rows, threshold: _staleThreshold),
            ],
          ),
          loading: () => const Padding(
            padding: EdgeInsets.only(top: 8),
            child: SummarySkeleton(),
          ),
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

class _ByOrganizationTab extends StatefulWidget {
  const _ByOrganizationTab({required this.rows, required this.states});

  final List<CallingSummaryRow> rows;
  final Set<CallingState> states;

  @override
  State<_ByOrganizationTab> createState() => _ByOrganizationTabState();
}

class _ByOrganizationTabState extends State<_ByOrganizationTab> {
  static const _unassignedKey = '__unassigned__';
  static const _unassignedLabel = 'Unassigned';

  /// Keys of organization groups the user has expanded. Preserved across
  /// rebuilds (e.g. stream ticks) so drilling in doesn't collapse on refresh.
  /// Default: all collapsed — the summary should be skimmable at a glance.
  final Set<String> _expanded = <String>{};

  void _toggle(String key, bool isExpanded) {
    setState(() {
      if (isExpanded) {
        _expanded.add(key);
      } else {
        _expanded.remove(key);
      }
    });
  }

  void _expandAll(Iterable<String> keys) {
    setState(() {
      _expanded
        ..clear()
        ..addAll(keys);
    });
  }

  void _collapseAll() {
    setState(() => _expanded.clear());
  }

  @override
  Widget build(BuildContext context) {
    final inService = widget.rows
        .where((r) =>
            r.latestEvent != null &&
            widget.states.contains(r.latestEvent!.state))
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

    final allExpanded = _expanded.length == orderedKeys.length;

    return ListView(
      // Physics tweak so a nearly-empty tab still overscrolls into the
      // RefreshIndicator on the parent Scaffold.
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        _ExpandCollapseBar(
          allExpanded: allExpanded,
          totalCallings: inService.length,
          totalGroups: orderedKeys.length,
          onExpandAll: () => _expandAll(orderedKeys),
          onCollapseAll: _collapseAll,
        ),
        for (final key in orderedKeys)
          _OrgSection(
            key: ValueKey('org-$key'),
            title: key == _unassignedKey ? _unassignedLabel : key,
            rows: _sortRows(groups[key]!),
            isExpanded: _expanded.contains(key),
            onChanged: (v) => _toggle(key, v),
          ),
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

/// Compact bar above the org sections: shows totals and an expand/collapse-all
/// affordance so the user can flip modes without tapping every section.
class _ExpandCollapseBar extends StatelessWidget {
  const _ExpandCollapseBar({
    required this.allExpanded,
    required this.totalCallings,
    required this.totalGroups,
    required this.onExpandAll,
    required this.onCollapseAll,
  });

  final bool allExpanded;
  final int totalCallings;
  final int totalGroups;
  final VoidCallback onExpandAll;
  final VoidCallback onCollapseAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$totalCallings in service · $totalGroups '
              '${totalGroups == 1 ? 'organization' : 'organizations'}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: allExpanded ? onCollapseAll : onExpandAll,
            icon: Icon(
              allExpanded ? Icons.unfold_less : Icons.unfold_more,
              size: 18,
            ),
            label: Text(allExpanded ? 'Collapse all' : 'Expand all'),
          ),
        ],
      ),
    );
  }
}

/// One collapsible organization section. Header shows the org name and a count
/// pill; the body is the sorted list of calling rows with the original
/// staggered fade-in preserved (nice touch when the user drills in).
class _OrgSection extends StatelessWidget {
  const _OrgSection({
    super.key,
    required this.title,
    required this.rows,
    required this.isExpanded,
    required this.onChanged,
  });

  final String title;
  final List<CallingSummaryRow> rows;
  final bool isExpanded;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      // ExpansionTile paints a hairline top/bottom divider by default; the
      // summary reads cleaner without them so sections feel like one card.
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        // Keep child widgets alive so the FadeSlideIn animation only plays the
        // first time a section is expanded, not every time it's re-opened.
        maintainState: true,
        initiallyExpanded: isExpanded,
        onExpansionChanged: onChanged,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        title: Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CountBadge(count: rows.length),
            const SizedBox(width: 8),
            Icon(
              isExpanded ? Icons.expand_less : Icons.expand_more,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
        children: [
          for (var i = 0; i < rows.length; i++)
            FadeSlideIn(
              delay: Duration(milliseconds: 25 * i.clamp(0, 12)),
              child: _CallingRow(row: rows[i], showOrganization: false),
            ),
        ],
      ),
    );
  }
}

/// Small pill showing the number of callings in a section. Stays visible even
/// when the section is collapsed so the summary is still informative at a
/// glance.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
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
        for (var i = 0; i < stale.length; i++)
          FadeSlideIn(
            delay: Duration(milliseconds: 25 * i.clamp(0, 12)),
            child: _CallingRow(row: stale[i], showOrganization: true),
          ),
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
                StateChip(state: event.state),
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
