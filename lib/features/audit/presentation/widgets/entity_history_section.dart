import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../admin/domain/entities/entity_history_entry.dart';
import '../providers/audit_providers.dart';

/// A collapsible "History" section that renders the redacted per-entity
/// audit history.
///
/// Actor identity and metadata diffs are intentionally not surfaced — the
/// server's `list_audit_log_for_entity` RPC strips them before returning.
/// See migration `20260717210000_audit_log_extensions.sql`.
class EntityHistorySection extends ConsumerWidget {
  const EntityHistorySection({
    super.key,
    required this.entityType,
    required this.entityId,
    this.title = 'History',
    this.emptyLabel = 'No history yet.',
  });

  /// One of `'member'`, `'calling'`, `'calling_event'`, `'user'`. Matches
  /// the values written by the server-side audit triggers.
  final String entityType;

  /// UUID (or invite code) of the record.
  final String entityId;

  final String title;
  final String emptyLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = EntityHistoryKey(
      entityType: entityType,
      entityId: entityId,
    );
    final async = ref.watch(entityHistoryProvider(key));
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Row(
                children: [
                  Icon(Icons.history, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(title, style: theme.textTheme.titleSmall),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Refresh',
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: () =>
                        ref.invalidate(entityHistoryProvider(key)),
                  ),
                ],
              ),
            ),
            async.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Failed to load history: $e',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
              data: (rows) {
                if (rows.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Text(
                      emptyLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final row in rows) _HistoryRow(entry: row),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});

  final EntityHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final title = entry.summary?.isNotEmpty == true
        ? entry.summary!
        : entry.action;

    return ListTile(
      dense: true,
      leading: Icon(_iconFor(entry.action), size: 20, color: scheme.primary),
      title: Text(title, style: theme.textTheme.bodyMedium),
      subtitle: Text(
        _formatTimestamp(entry.occurredAt),
        style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
      ),
    );
  }

  IconData _iconFor(String action) {
    if (action.endsWith('.create')) return Icons.add_circle_outline;
    if (action.endsWith('.delete')) return Icons.remove_circle_outline;
    if (action.endsWith('.update')) return Icons.edit_outlined;
    return Icons.circle_outlined;
  }
}

String _formatTimestamp(DateTime d) {
  final local = d.toLocal();
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final h = local.hour.toString().padLeft(2, '0');
  final min = local.minute.toString().padLeft(2, '0');
  return '$y-$m-$day $h:$min';
}
