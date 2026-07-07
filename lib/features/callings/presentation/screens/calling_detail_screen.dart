import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
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
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(callingByIdProvider(callingId));
          ref.invalidate(eventsForCallingProvider(callingId));
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
                  'History',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              _EventTimeline(eventsAsync: eventsAsync),
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
              if (currentState != null)
                Chip(
                  label: Text(currentState.label),
                  backgroundColor: currentState.isTerminal
                      ? theme.colorScheme.surfaceContainerHighest
                      : theme.colorScheme.secondaryContainer,
                  labelStyle: TextStyle(
                    color: currentState.isTerminal
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.onSecondaryContainer,
                  ),
                  side: BorderSide.none,
                ),
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
  const _EventTimeline({required this.eventsAsync});

  final AsyncValue<List<CallingEvent>> eventsAsync;

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
            for (final e in events) _EventTile(event: e),
          ],
        );
      },
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});

  final CallingEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(
        Icons.circle,
        size: 12,
        color: event.state.isTerminal
            ? theme.colorScheme.outline
            : theme.colorScheme.primary,
      ),
      title: Text(event.state.label),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_fmtDateTime(event.occurredAt.toLocal())),
          if (event.notes != null && event.notes!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(event.notes!),
            ),
        ],
      ),
    );
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
