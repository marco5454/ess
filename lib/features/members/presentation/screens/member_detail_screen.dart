import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../callings/domain/entities/calling_event.dart';
import '../../../callings/presentation/providers/callings_providers.dart';
import '../../domain/entities/member.dart';
import '../providers/members_providers.dart';

/// Shows a single member's info plus the list of callings assigned to them.
///
/// FAB navigates to the add-calling flow.
class MemberDetailScreen extends ConsumerWidget {
  const MemberDetailScreen({super.key, required this.memberId});

  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberAsync = ref.watch(memberByIdProvider(memberId));
    final callingsAsync = ref.watch(callingsForMemberProvider(memberId));

    return Scaffold(
      appBar: AppBar(
        title: Text(memberAsync.maybeWhen(
          data: (m) => m.displayName,
          orElse: () => 'Member',
        )),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: memberAsync.hasValue
                ? () => context.push(AppRoutes.memberEdit(memberId))
                : null,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(memberByIdProvider(memberId));
          ref.invalidate(callingsForMemberProvider(memberId));
        },
        child: memberAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              const SizedBox(height: 120),
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Failed to load member:\n$e',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
          data: (member) => ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              _MemberInfoCard(member: member),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Callings',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              _CallingsSection(
                memberId: memberId,
                callingsAsync: callingsAsync,
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        tooltip: 'Add calling',
        onPressed: () => context.push(
          AppRoutes.callingAddFor(memberId),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Calling'),
      ),
    );
  }
}

class _MemberInfoCard extends StatelessWidget {
  const _MemberInfoCard({required this.member});

  final Member member;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <Widget>[
      _kv(theme, 'Name', '${member.firstName} ${member.lastName}'),
      if (member.preferredName != null && member.preferredName!.isNotEmpty)
        _kv(theme, 'Preferred', member.preferredName!),
      if (member.priesthoodOffice != null &&
          member.priesthoodOffice!.isNotEmpty)
        _kv(theme, 'Priesthood', member.priesthoodOffice!),
      if (member.sex != null && member.sex!.isNotEmpty)
        _kv(theme, 'Sex', member.sex!),
      if (member.email != null && member.email!.isNotEmpty)
        _kv(theme, 'Email', member.email!),
      if (member.phone != null && member.phone!.isNotEmpty)
        _kv(theme, 'Phone', member.phone!),
      if (member.dateOfBirth != null)
        _kv(theme, 'Date of birth', _fmtDate(member.dateOfBirth!)),
      if (member.notes != null && member.notes!.isNotEmpty)
        _kv(theme, 'Notes', member.notes!),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!member.isActive)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.archive_outlined,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Archived — hidden from the main list',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ...rows,
        ],
      ),
    );
  }

  Widget _kv(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyLarge)),
        ],
      ),
    );
  }

  static String _fmtDate(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }
}

class _CallingsSection extends StatelessWidget {
  const _CallingsSection({
    required this.memberId,
    required this.callingsAsync,
  });

  final String memberId;
  final AsyncValue<List<CallingWithLatestEvent>> callingsAsync;

  @override
  Widget build(BuildContext context) {
    return callingsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Failed to load callings:\n$e'),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Text('No callings yet.'),
          );
        }
        return Column(
          children: [
            for (final item in items)
              _CallingTile(memberId: memberId, item: item),
          ],
        );
      },
    );
  }
}

class _CallingTile extends StatelessWidget {
  const _CallingTile({required this.memberId, required this.item});

  final String memberId;
  final CallingWithLatestEvent item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final calling = item.calling;
    final event = item.latestEvent;

    final subtitle = <String>[
      if (calling.organization != null && calling.organization!.isNotEmpty)
        calling.organization!,
    ].join(' • ');

    return ListTile(
      title: Text(calling.title),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: event == null
          ? const Icon(Icons.chevron_right)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Chip(
                  label: Text(event.state.label),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  labelStyle: TextStyle(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                  side: BorderSide.none,
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
      onTap: () => context.push(
        AppRoutes.callingDetail(memberId, calling.id),
      ),
    );
  }
}
