import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/state_chip.dart';
import '../../../audit/presentation/widgets/entity_history_section.dart';
import '../../domain/entities/calling.dart';
import '../../domain/entities/calling_event.dart';
import '../providers/callings_providers.dart';

/// Detail view for a single calling: header + append-only event timeline,
/// with a "Record next state" action if the current state is non-terminal.
class CallingDetailScreen extends ConsumerWidget {
  const CallingDetailScreen({
    super.key,
    required this.memberId,
    required this.callingId,
  });

  final String memberId;
  final String callingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callingAsync = ref.watch(callingByIdProvider(callingId));
    final eventsAsync = ref.watch(eventsForCallingProvider(callingId));

    return Scaffold(
      appBar: AppBar(
        title: Text(callingAsync.maybeWhen(
          data: (c) => c.title,
          orElse: () => 'Calling',
        )),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: callingAsync.hasValue
                ? () => context
                    .push(AppRoutes.callingEdit(memberId, callingId))
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete calling',
            onPressed: callingAsync.hasValue
                ? () => _confirmAndDeleteCalling(
                      context,
                      ref,
                      callingAsync.requireValue,
                    )
                : null,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(allCallingsStreamProvider);
          ref.invalidate(allEventsStreamProvider);
        },
        child: callingAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              const SizedBox(height: 120),
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Failed to load calling:\n$e',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
          data: (calling) => ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              _CallingHeader(calling: calling, eventsAsync: eventsAsync),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Timeline',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              _EventTimeline(
                eventsAsync: eventsAsync,
                memberId: memberId,
                callingId: callingId,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: EntityHistorySection(
                  entityType: 'calling',
                  entityId: callingId,
                  title: 'Change history',
                  emptyLabel: 'No metadata edits yet.',
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: eventsAsync.maybeWhen(
        data: (events) {
          final current = events.isEmpty ? null : events.first.state;
          if (current == null || current.isTerminal) return null;
          return FloatingActionButton.extended(
            tooltip: 'Record next state',
            onPressed: () => context.push(
              AppRoutes.callingRecordFor(memberId, callingId),
            ),
            icon: const Icon(Icons.timeline),
            label: const Text('Record state'),
          );
        },
        orElse: () => null,
      ),
    );
  }

  Future<void> _confirmAndDeleteCalling(
    BuildContext context,
    WidgetRef ref,
    Calling calling,
  ) async {
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this calling?'),
        content: Text(
          'This will permanently remove "${calling.title}" and its entire '
          'history. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(callingsRepositoryProvider).deleteCalling(calling.id);
      ref.invalidate(callingsForMemberProvider(memberId));
      messenger.showSnackBar(const SnackBar(content: Text('Calling deleted')));
      router.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
    }
  }
}

class _CallingHeader extends StatelessWidget {
  const _CallingHeader({required this.calling, required this.eventsAsync});

  final Calling calling;
  final AsyncValue<List<CallingEvent>> eventsAsync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentState = eventsAsync.maybeWhen(
      data: (events) => events.isEmpty ? null : events.first.state,
      orElse: () => null,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(calling.title, style: theme.textTheme.titleLarge),
              ),
              if (currentState != null) StateChip(state: currentState),
            ],
          ),
          if (calling.organization != null &&
              calling.organization!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              calling.organization!,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          if (calling.notes != null && calling.notes!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(calling.notes!, style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

class _EventTimeline extends StatelessWidget {
  const _EventTimeline({
    required this.eventsAsync,
    required this.memberId,
    required this.callingId,
  });

  final AsyncValue<List<CallingEvent>> eventsAsync;
  final String memberId;
  final String callingId;

  @override
  Widget build(BuildContext context) {
    return eventsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Failed to load history:\n$e'),
      ),
      data: (events) {
        if (events.isEmpty) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Text('No events recorded yet.'),
          );
        }
        return Column(
          children: [
            for (var i = 0; i < events.length; i++)
              _EventTile(
                event: events[i],
                previous: i + 1 < events.length ? events[i + 1] : null,
                isLatest: i == 0,
                isOnlyEvent: events.length == 1,
                memberId: memberId,
                callingId: callingId,
              ),
          ],
        );
      },
    );
  }
}

class _EventTile extends ConsumerWidget {
  const _EventTile({
    required this.event,
    required this.previous,
    required this.isLatest,
    required this.isOnlyEvent,
    required this.memberId,
    required this.callingId,
  });

  final CallingEvent event;

  /// The event immediately preceding this one in time (chronologically older),
  /// or `null` if this is the first event ever recorded on the calling.
  final CallingEvent? previous;
  final bool isLatest;
  final bool isOnlyEvent;
  final String memberId;
  final String callingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isInitial = previous == null;

    final Widget titleWidget;
    if (isInitial) {
      titleWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'Initial',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(event.state.label),
        ],
      );
    } else {
      titleWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            previous!.state.label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            Icons.arrow_forward,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            event.state.label,
            style: theme.textTheme.titleMedium,
          ),
        ],
      );
    }

    return ListTile(
      leading: Icon(
        Icons.circle,
        size: 12,
        color: event.state.isTerminal
            ? theme.colorScheme.outline
            : theme.colorScheme.primary,
      ),
      title: titleWidget,
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_fmtDateTime(event.occurredAt.toLocal())),
          if (event.performedBy != null && event.performedBy!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'By: ${event.performedBy!}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (event.notes != null && event.notes!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(event.notes!),
            ),
        ],
      ),
      trailing: isLatest
          ? IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete this event',
              onPressed: () => _confirmAndDelete(context, ref),
            )
          : null,
    );
  }

  Future<void> _confirmAndDelete(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this event?'),
        content: Text(
          isOnlyEvent
              ? 'This is the only event on this calling. Deleting it will '
                  'leave the calling with no recorded state.'
              : 'This will remove the "${event.state.label}" event. The '
                  'previous event will become the current state.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(callingsRepositoryProvider).deleteEvent(event.id);
      ref.invalidate(eventsForCallingProvider(callingId));
      ref.invalidate(callingsForMemberProvider(memberId));
      messenger.showSnackBar(const SnackBar(content: Text('Event deleted')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
    }
  }

  static String _fmtDateTime(DateTime d) {
    final date = '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    final time = '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
    return '$date $time';
  }
}
