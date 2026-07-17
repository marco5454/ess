import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/motion/skeletons.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/chapel_theme.dart';
import '../../../../core/theme/state_chip.dart';
import '../../../audit/presentation/widgets/entity_history_section.dart';
import '../../../callings/domain/entities/calling_event.dart';
import '../../../callings/presentation/providers/callings_providers.dart';
import '../../domain/entities/member.dart';
import '../providers/members_providers.dart';

/// Detail page for a single member.
///
/// Layout, top to bottom:
///
///  * **Hero** — initials avatar + full name, an optional "Prefers X"
///    subtitle, and a compact row of chips summarising priesthood office,
///    sex, and age. An "Archived" chip appears here when the member is
///    inactive.
///  * **Contact card** — tappable phone (`tel:`) and email (`mailto:`)
///    rows. Long-press copies the value to the clipboard. Rendered only
///    when at least one of the fields is present.
///  * **Notes card** — its own bordered block so multi-line notes can
///    breathe. Only rendered when notes are non-empty.
///  * **Current callings** — the subset of the member's callings whose
///    latest event puts them "in service" (per
///    [memberInServiceStates]). Styled a shade louder so the bishop's
///    eye lands here first.
///  * **Calling history** — an [ExpansionTile] labelled
///    "History · N" containing every calling for the member, current
///    or not. Collapsed by default. Hidden entirely when there are no
///    callings.
///
/// AppBar carries Edit plus an overflow menu with Copy phone, Copy
/// email, and Archive / Unarchive. Archive uses the existing
/// [MembersRepository.updateMember] path with the same payload shape
/// the Edit form uses, so the outbox and sync behaviour are unchanged.
///
/// FAB: extended "Add calling".
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
          if (memberAsync.hasValue)
            _MemberOverflowMenu(member: memberAsync.value!),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(allMembersStreamProvider);
          ref.invalidate(allCallingsStreamProvider);
          ref.invalidate(allEventsStreamProvider);
        },
        child: memberAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.only(top: 8),
            child: MemberDetailSkeleton(),
          ),
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
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
            children: [
              _MemberHero(member: member),
              if (_hasContact(member)) _ContactCard(member: member),
              if (_hasNotes(member)) _NotesCard(notes: member.notes!),
              _CallingsSection(
                memberId: memberId,
                callingsAsync: callingsAsync,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: EntityHistorySection(
                  entityType: 'member',
                  entityId: memberId,
                  emptyLabel: 'No history for this member yet.',
                ),
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

  static bool _hasContact(Member m) =>
      (m.phone?.trim().isNotEmpty ?? false) ||
      (m.email?.trim().isNotEmpty ?? false);

  static bool _hasNotes(Member m) => m.notes?.trim().isNotEmpty ?? false;
}

// ─── Hero ──────────────────────────────────────────────────────────────

class _MemberHero extends StatelessWidget {
  const _MemberHero({required this.member});

  final Member member;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasPreferred =
        (member.preferredName?.trim().isNotEmpty ?? false) &&
            member.preferredName!.trim().toLowerCase() !=
                member.firstName.trim().toLowerCase();

    final chips = <Widget>[
      if ((member.priesthoodOffice?.trim().isNotEmpty ?? false))
        _FactChip(icon: Icons.church_outlined, label: member.priesthoodOffice!),
      if ((member.sex?.trim().isNotEmpty ?? false))
        _FactChip(icon: Icons.person_outline, label: member.sex!),
      if (member.dateOfBirth != null)
        _FactChip(
          icon: Icons.cake_outlined,
          label: '${_ageInYears(member.dateOfBirth!)} yrs',
        ),
      if (!member.isActive)
        _FactChip(
          icon: Icons.archive_outlined,
          label: 'Archived',
          tone: _FactChipTone.muted,
        ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LargeInitialsAvatar(member: member),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${member.firstName} ${member.lastName}',
                  style: theme.textTheme.headlineSmall,
                ),
                if (hasPreferred) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Prefers ${member.preferredName!.trim()}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                if (chips.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 6, children: chips),
                ],
                if (member.dateOfBirth != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Born ${_fmtDateLong(member.dateOfBirth!)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Larger version of the initials avatar shown on the members list. Same
/// hashed-swatch rotation so a member's color is stable across screens.
class _LargeInitialsAvatar extends StatelessWidget {
  const _LargeInitialsAvatar({required this.member});

  final Member member;

  static const _swatches = <(Color, Color)>[
    (ChapelPalette.navyLight, Colors.white),
    (ChapelPalette.gold, Colors.white),
    (ChapelPalette.sage, Colors.white),
    (ChapelPalette.amber, Colors.white),
    (ChapelPalette.goldLight, ChapelPalette.goldDark),
    (ChapelPalette.sageLight, Color(0xFF2E4A2E)),
    (ChapelPalette.amberLight, ChapelPalette.amber),
    (ChapelPalette.paperDeep, ChapelPalette.inkSoft),
  ];

  @override
  Widget build(BuildContext context) {
    final initials = _initials(member);
    final bucket = member.id.hashCode.abs() % _swatches.length;
    final (bg, fg) = _swatches[bucket];
    return CircleAvatar(
      radius: 34,
      backgroundColor: bg,
      child: Text(
        initials,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
      ),
    );
  }

  static String _initials(Member m) {
    final first = _firstLetter(m.preferredName) ?? _firstLetter(m.firstName);
    final last = _firstLetter(m.lastName);
    if (first != null && last != null) return '$first$last';
    if (first != null) return first;
    if (last != null) return last;
    return '?';
  }

  static String? _firstLetter(String? s) {
    if (s == null) return null;
    final t = s.trim();
    if (t.isEmpty) return null;
    return t[0].toUpperCase();
  }
}

enum _FactChipTone { neutral, muted }

/// Small icon+label pill used in the hero to summarise membership facts
/// (priesthood office, sex, age, archived flag).
class _FactChip extends StatelessWidget {
  const _FactChip({
    required this.icon,
    required this.label,
    this.tone = _FactChipTone.neutral,
  });

  final IconData icon;
  final String label;
  final _FactChipTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bg = tone == _FactChipTone.muted
        ? scheme.surfaceContainerHighest
        : scheme.secondaryContainer;
    final fg = tone == _FactChipTone.muted
        ? scheme.onSurfaceVariant
        : scheme.onSecondaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Contact card ──────────────────────────────────────────────────────

class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.member});

  final Member member;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phone = member.phone?.trim();
    final email = member.email?.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Card(
        elevation: 0,
        color: theme.colorScheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          children: [
            if (phone != null && phone.isNotEmpty)
              _ContactRow(
                icon: Icons.phone_outlined,
                label: 'Phone',
                value: phone,
                onTap: () => _launch(context, Uri(scheme: 'tel', path: phone)),
                onLongPress: () => _copy(context, 'Phone', phone),
              ),
            if (phone != null && phone.isNotEmpty &&
                email != null && email.isNotEmpty)
              Divider(
                height: 1,
                indent: 56,
                color: theme.colorScheme.outlineVariant,
              ),
            if (email != null && email.isNotEmpty)
              _ContactRow(
                icon: Icons.mail_outline,
                label: 'Email',
                value: email,
                onTap: () => _launch(context, Uri(scheme: 'mailto', path: email)),
                onLongPress: () => _copy(context, 'Email', email),
              ),
          ],
        ),
      ),
    );
  }

  static Future<void> _launch(BuildContext context, Uri uri) async {
    final ok = await launchUrl(uri);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open ${uri.scheme}: link.')),
      );
    }
  }

  static Future<void> _copy(
      BuildContext context, String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label copied.')),
      );
    }
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    required this.onLongPress,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 18,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(value, style: theme.textTheme.bodyLarge),
                ],
              ),
            ),
            Icon(
              Icons.arrow_outward,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Notes card ────────────────────────────────────────────────────────

class _NotesCard extends StatelessWidget {
  const _NotesCard({required this.notes});

  final String notes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Card(
        elevation: 0,
        color: theme.colorScheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.notes,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Notes',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SelectableText(
                notes.trim(),
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Callings section ──────────────────────────────────────────────────

class _CallingsSection extends StatelessWidget {
  const _CallingsSection({
    required this.memberId,
    required this.callingsAsync,
  });

  final String memberId;
  final AsyncValue<List<CallingWithLatestEvent>> callingsAsync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionTitle('Callings'),
                const SizedBox(height: 8),
                Text(
                  'No callings yet. Tap the button below to add one.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        }

        // Newest-first for both buckets — items already come sorted this
        // way from callingsForMemberProvider.
        final current = items.where((c) {
          final s = c.latestEvent?.state;
          return s != null && memberInServiceStates.contains(s);
        }).toList(growable: false);
        final historyOnly = items.where((c) {
          final s = c.latestEvent?.state;
          return s == null || !memberInServiceStates.contains(s);
        }).toList(growable: false);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: _SectionTitle(
                'Current callings',
                trailing: current.isEmpty
                    ? null
                    : _MiniCountBadge(count: current.length),
              ),
            ),
            if (current.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  'Not currently serving.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainer,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < current.length; i++) ...[
                        if (i > 0)
                          Divider(
                            height: 1,
                            color: theme.colorScheme.outlineVariant,
                          ),
                        _CallingTile(
                          memberId: memberId,
                          item: current[i],
                          emphasize: true,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            if (historyOnly.isNotEmpty) ...[
              const SizedBox(height: 4),
              Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                  childrenPadding: EdgeInsets.zero,
                  title: Row(
                    children: [
                      Icon(
                        Icons.history,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'History',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(width: 8),
                      _MiniCountBadge(count: historyOnly.length),
                    ],
                  ),
                  children: [
                    for (final item in historyOnly)
                      _CallingTile(
                        memberId: memberId,
                        item: item,
                        emphasize: false,
                      ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(text, style: Theme.of(context).textTheme.titleMedium),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing!,
        ],
      ],
    );
  }
}

class _MiniCountBadge extends StatelessWidget {
  const _MiniCountBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CallingTile extends StatelessWidget {
  const _CallingTile({
    required this.memberId,
    required this.item,
    required this.emphasize,
  });

  final String memberId;
  final CallingWithLatestEvent item;

  /// When true, the tile is rendered inside the "Current" card and uses
  /// a slightly stronger title weight. When false, it's a history row.
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final calling = item.calling;
    final event = item.latestEvent;

    final subtitle = <String>[
      if (calling.organization != null && calling.organization!.isNotEmpty)
        calling.organization!,
      if (event != null) _fmtDate(event.occurredAt),
    ].join(' • ');

    return ListTile(
      title: Text(
        calling.title,
        style: emphasize
            ? theme.textTheme.titleSmall
            : theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
      ),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: event == null
          ? const Icon(Icons.chevron_right)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StateChip(state: event.state, dense: true),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right),
              ],
            ),
      onTap: () => context.push(
        AppRoutes.callingDetail(memberId, calling.id),
      ),
    );
  }

  static String _fmtDate(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }
}

// ─── Overflow menu ─────────────────────────────────────────────────────

class _MemberOverflowMenu extends ConsumerWidget {
  const _MemberOverflowMenu({required this.member});

  final Member member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPhone = member.phone?.trim().isNotEmpty ?? false;
    final hasEmail = member.email?.trim().isNotEmpty ?? false;
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: const Icon(Icons.more_vert),
      onSelected: (value) async {
        switch (value) {
          case 'copy-phone':
            await Clipboard.setData(
                ClipboardData(text: member.phone!.trim()));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Phone copied.')),
              );
            }
            break;
          case 'copy-email':
            await Clipboard.setData(
                ClipboardData(text: member.email!.trim()));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Email copied.')),
              );
            }
            break;
          case 'toggle-archive':
            await _confirmAndToggleArchive(context, ref, member);
            break;
        }
      },
      itemBuilder: (_) => [
        if (hasPhone)
          const PopupMenuItem<String>(
            value: 'copy-phone',
            child: ListTile(
              leading: Icon(Icons.phone_outlined),
              title: Text('Copy phone'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
        if (hasEmail)
          const PopupMenuItem<String>(
            value: 'copy-email',
            child: ListTile(
              leading: Icon(Icons.mail_outline),
              title: Text('Copy email'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
        if (hasPhone || hasEmail) const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'toggle-archive',
          child: ListTile(
            leading: Icon(member.isActive
                ? Icons.archive_outlined
                : Icons.unarchive_outlined),
            title: Text(member.isActive ? 'Archive' : 'Unarchive'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
      ],
    );
  }

  Future<void> _confirmAndToggleArchive(
      BuildContext context, WidgetRef ref, Member member) async {
    final willArchive = member.isActive;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(willArchive ? 'Archive member?' : 'Unarchive member?'),
        content: Text(willArchive
            ? 'Archived members are hidden from the main list. Their '
                'callings and history are preserved.'
            : 'The member will reappear in the main list.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(willArchive ? 'Archive' : 'Unarchive'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    final repo = ref.read(membersRepositoryProvider);
    try {
      await repo.updateMember(
        member.id,
        MemberUpdate(
          firstName: member.firstName,
          lastName: member.lastName,
          preferredName: member.preferredName,
          phone: member.phone,
          email: member.email,
          notes: member.notes,
          dateOfBirth: member.dateOfBirth,
          sex: member.sex,
          priesthoodOffice: member.priesthoodOffice,
          isActive: !member.isActive,
        ),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(willArchive ? 'Member archived.' : 'Member restored.'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update member: $e')),
        );
      }
    }
  }
}

// ─── Small helpers ─────────────────────────────────────────────────────

/// Whole-year age from a birth date.
int _ageInYears(DateTime dob) {
  final now = DateTime.now();
  var years = now.year - dob.year;
  final hadBirthdayThisYear = now.month > dob.month ||
      (now.month == dob.month && now.day >= dob.day);
  if (!hadBirthdayThisYear) years -= 1;
  return years;
}

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// e.g. "12 April 1985". Used in the hero for the "Born …" byline.
String _fmtDateLong(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';
