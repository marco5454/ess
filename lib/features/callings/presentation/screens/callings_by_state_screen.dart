import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../domain/entities/calling_state.dart';
import '../providers/callings_providers.dart';

/// Drill-down list showing every calling currently in a given state.
///
/// Reached by tapping a tile on [DashboardScreen]. Rows are ordered by
/// `occurredAt` ascending — the oldest transitions rise to the top so
/// stale pipeline items are naturally visible without an explicit filter.
class CallingsByStateScreen extends ConsumerWidget {
  const CallingsByStateScreen({super.key, required this.state});

  final CallingState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rowsAsync = ref.watch(callingsInStateProvider(state));
    return Scaffold(
      appBar: AppBar(title: Text('${state.label} callings')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(allCallingsStreamProvider);
          ref.invalidate(allEventsStreamProvider);
        },
        child: rowsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              const SizedBox(height: 120),
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Failed to load:\n$e',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
          data: (rows) {
            if (rows.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 120),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No callings are currently ${state.label.toLowerCase()}.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, _) => const Divider(height: 0),
              itemBuilder: (context, i) {
                final row = rows[i];
                final member = row.member;
                final event = row.latestEvent!;
                final subtitleParts = <String>[
                  if (member != null) member.displayName,
                  if ((row.calling.organization ?? '').trim().isNotEmpty)
                    row.calling.organization!.trim(),
                  'Since ${_formatDate(event.occurredAt)}',
                ];
                return ListTile(
                  title: Text(row.calling.title),
                  subtitle: Text(subtitleParts.join(' • ')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: member == null
                      ? null
                      : () => context.push(
                            AppRoutes.callingDetail(
                              member.id,
                              row.calling.id,
                            ),
                          ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

String _formatDate(DateTime d) {
  final local = d.toLocal();
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}
