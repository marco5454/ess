import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/audit_log_entry.dart';
import '../providers/audit_log_provider.dart';

/// Admin-only paginated audit-log viewer.
///
/// Rows are read via the `list_audit_log()` RPC (keyset-paginated on
/// `(occurred_at desc, id desc)`). Data is online-only — nothing is
/// mirrored to Drift. Admins can filter by entity type via the top chip
/// row.
class AdminAuditLogScreen extends ConsumerStatefulWidget {
  const AdminAuditLogScreen({super.key});

  @override
  ConsumerState<AdminAuditLogScreen> createState() =>
      _AdminAuditLogScreenState();
}

class _AdminAuditLogScreenState extends ConsumerState<AdminAuditLogScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scroll.removeListener(_maybeLoadMore);
    _scroll.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    // Trigger a page fetch when within 400 px of the bottom.
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      ref.read(auditLogProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(auditLogProvider);
    final notifier = ref.read(auditLogProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Activity log')),
      body: Column(
        children: [
          _FilterBar(
            active: state.actionLike,
            onChanged: notifier.setActionFilter,
          ),
          const Divider(height: 0),
          Expanded(
            child: RefreshIndicator(
              onRefresh: notifier.refresh,
              child: _body(state),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(AuditLogState state) {
    if (state.entries.isEmpty) {
      if (state.isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (state.error != null) {
        return ListView(
          children: [
            const SizedBox(height: 120),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Failed to load activity:\n${state.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        );
      }
      return ListView(
        children: const [
          SizedBox(height: 120),
          Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No activity recorded yet.'),
            ),
          ),
        ],
      );
    }

    // At least one row. Show them + a trailing loader/error/end-marker.
    final itemCount = state.entries.length + 1;
    return ListView.separated(
      controller: _scroll,
      itemCount: itemCount,
      separatorBuilder: (_, _) => const Divider(height: 0),
      itemBuilder: (context, i) {
        if (i == state.entries.length) {
          return _Footer(state: state);
        }
        return _AuditRow(entry: state.entries[i]);
      },
    );
  }
}

/// Filter chips over the top of the list. Maps friendly labels to the
/// LIKE patterns accepted by `list_audit_log`.
class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.active, required this.onChanged});

  final String? active;
  final ValueChanged<String?> onChanged;

  static const _filters = <(String label, String? pattern)>[
    ('All', null),
    ('Members', 'member.%'),
    ('Callings', 'calling.%'),
    ('Events', 'calling_event.%'),
    ('Admin', 'admin.%'),
    ('Invites', 'invite.%'),
    ('Users', 'user.%'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (label, pattern) in _filters) ...[
              ChoiceChip(
                label: Text(label),
                selected: active == pattern,
                onSelected: (_) => onChanged(pattern),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.state});

  final AuditLogState state;

  @override
  Widget build(BuildContext context) {
    if (state.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (state.error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            'Failed to load more:\n${state.error}',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.red),
          ),
        ),
      );
    }
    if (!state.hasMore) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            'End of activity.',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _AuditRow extends StatelessWidget {
  const _AuditRow({required this.entry});

  final AuditLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final title = entry.summary?.isNotEmpty == true
        ? entry.summary!
        : entry.action;
    final actor = entry.actorEmail?.isNotEmpty == true
        ? entry.actorEmail!
        : (entry.actorId ?? 'system');

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _colorFor(entry.action, scheme),
        child: Icon(_iconFor(entry.action), size: 20, color: Colors.white),
      ),
      title: Text(title, style: theme.textTheme.bodyMedium),
      subtitle: Text(
        '$actor • ${_formatTimestamp(entry.occurredAt)}',
        style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
      ),
      trailing: Text(
        entry.action,
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.outline,
          fontFamily: 'monospace',
        ),
      ),
      isThreeLine: false,
      dense: true,
    );
  }

  IconData _iconFor(String action) {
    if (action.startsWith('member.')) return Icons.person_outline;
    if (action.startsWith('calling_event.')) return Icons.event_note_outlined;
    if (action.startsWith('calling.')) return Icons.assignment_outlined;
    if (action.startsWith('admin.')) return Icons.shield_outlined;
    if (action.startsWith('invite.')) {
      return Icons.confirmation_number_outlined;
    }
    if (action.startsWith('user.')) return Icons.person_off_outlined;
    return Icons.circle_outlined;
  }

  Color _colorFor(String action, ColorScheme scheme) {
    if (action.endsWith('.delete')) return scheme.error;
    if (action.endsWith('.create')) return scheme.primary;
    if (action.startsWith('admin.') || action.startsWith('user.')) {
      return scheme.tertiary;
    }
    return scheme.secondary;
  }
}

/// Format an audit timestamp as `YYYY-MM-DD HH:MM` in local time.
String _formatTimestamp(DateTime d) {
  final local = d.toLocal();
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final h = local.hour.toString().padLeft(2, '0');
  final min = local.minute.toString().padLeft(2, '0');
  return '$y-$m-$day $h:$min';
}
