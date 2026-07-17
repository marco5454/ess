import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/chapel_theme.dart';
import '../../domain/entities/activity_kind.dart';
import '../../domain/entities/activity_status.dart';
import '../providers/tracked_activities_providers.dart';
import '../widgets/activity_status_chip.dart';

/// The Activities tab: a searchable, filterable list of every ward
/// bookkeeping task (temple recommend interviews, ministering interviews,
/// etc). Rendered inside the [HomeShell]'s IndexedStack — owns its own
/// Scaffold/AppBar/FAB.
class ActivitiesListScreen extends ConsumerStatefulWidget {
  const ActivitiesListScreen({super.key});

  @override
  ConsumerState<ActivitiesListScreen> createState() =>
      _ActivitiesListScreenState();
}

class _ActivitiesListScreenState extends ConsumerState<ActivitiesListScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  ActivityKind? _kindFilter; // null = all kinds
  bool _showCompleted = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rowsAsync = ref.watch(activityRowsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Activities'),
        actions: [
          IconButton(
            tooltip: _showCompleted ? 'Hide completed' : 'Show completed',
            icon: Icon(
              _showCompleted
                  ? Icons.check_circle
                  : Icons.check_circle_outline,
            ),
            onPressed: () =>
                setState(() => _showCompleted = !_showCompleted),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(112),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search activities',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            },
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v.trim()),
                ),
              ),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    _KindChip(
                      label: 'All',
                      selected: _kindFilter == null,
                      onSelected: () => setState(() => _kindFilter = null),
                    ),
                    for (final kind in ActivityKind.values)
                      _KindChip(
                        icon: kind.icon,
                        label: kind.label,
                        selected: _kindFilter == kind,
                        onSelected: () =>
                            setState(() => _kindFilter = kind),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(allActivitiesStreamProvider);
        },
        child: rowsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorState(error: e),
          data: (rows) {
            final filtered = _filter(rows);
            if (filtered.isEmpty) {
              return ListView(
                // Ensure RefreshIndicator has a scrollable child.
                children: const [
                  SizedBox(height: 120),
                  _EmptyState(),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: filtered.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, indent: 16, endIndent: 16),
              itemBuilder: (context, i) => _ActivityTile(row: filtered[i]),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        tooltip: 'Add activity',
        onPressed: () => context.push(AppRoutes.activityAdd),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
    );
  }

  List<ActivityRow> _filter(List<ActivityRow> rows) {
    final q = _query.toLowerCase();
    return rows.where((r) {
      final a = r.activity;
      if (_kindFilter != null && a.kind != _kindFilter) return false;
      if (!_showCompleted && a.status.isTerminal) return false;
      if (q.isEmpty) return true;
      if (a.title.toLowerCase().contains(q)) return true;
      if (a.notes?.toLowerCase().contains(q) ?? false) return true;
      final m = r.member;
      if (m != null && m.displayName.toLowerCase().contains(q)) return true;
      return false;
    }).toList(growable: false);
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({
    this.icon,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final IconData? icon;
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        avatar: icon == null ? null : Icon(icon, size: 16),
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.row});

  final ActivityRow row;

  @override
  Widget build(BuildContext context) {
    final a = row.activity;
    final m = row.member;
    final subtitleParts = <String>[];
    if (m != null) subtitleParts.add(m.displayName);
    subtitleParts.add(a.kind.label);
    if (a.dueAt != null) subtitleParts.add('Due ${_formatDate(a.dueAt!)}');

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: ChapelPalette.paperDeep,
        child: Icon(a.kind.icon, color: ChapelPalette.inkSoft, size: 20),
      ),
      title: Text(
        a.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          decoration: a.status == ActivityStatus.completed
              ? TextDecoration.lineThrough
              : null,
        ),
      ),
      subtitle: Text(
        subtitleParts.join(' \u00b7 '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: a.isOverdue ? Theme.of(context).colorScheme.error : null,
          fontWeight: a.isOverdue ? FontWeight.w600 : null,
        ),
      ),
      trailing: ActivityStatusChip(status: a.status, dense: true),
      onTap: () => context.push(AppRoutes.activityDetail(a.id)),
    );
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.checklist_outlined, size: 48),
            const SizedBox(height: 12),
            Text(
              'No activities to show',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Track temple recommend interviews, ministering interviews, and other tasks. Tap Add to get started.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});
  final Object error;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Failed to load activities:\n$error'),
      ),
    );
  }
}
