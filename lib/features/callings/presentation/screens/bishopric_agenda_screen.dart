/// Bishopric meeting agenda.
///
/// A read-only, print-friendly view that slices the ward's calling work
/// into the sections a bishopric walks through in a meeting:
///
///   1. Ready to sustain     (state = accepted)
///   2. Ready to set apart   (state = sustained)
///   3. Awaiting response    (state = extended)
///   4. New selections       (state = selected)
///   5. Stalled ≥14 days     (selected/extended, latest event ≥14 days old)
///   6. Recent activity      (last N state transitions)
///
/// The screen exists mainly to be *shared*: the bottom action button
/// renders the whole agenda as plaintext and passes it to the platform
/// share sheet. That way the bishopric can drop the report into whatever
/// group thread or email they already use for meeting prep without the
/// app needing to know about any specific channel.
///
/// The visible header carries a "Confidential — Bishopric Only" banner
/// so the shared artifact is self-labeling: even if it ends up in a
/// screenshot or a paper printout, it says what it is.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/motion/motion.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/chapel_theme.dart';
import '../providers/callings_providers.dart';

class BishopricAgendaScreen extends ConsumerWidget {
  const BishopricAgendaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agendaAsync = ref.watch(bishopricAgendaProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bishopric agenda'),
      ),
      body: agendaAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Failed to load agenda:\n$e',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (agenda) => _AgendaBody(agenda: agenda),
      ),
    );
  }
}

class _AgendaBody extends StatelessWidget {
  const _AgendaBody({required this.agenda});

  final BishopricAgenda agenda;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Wrap the whole thing in a Column so the share button can pin
    // itself to the bottom without floating over the last row.
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _AgendaHeader(agenda: agenda),
              const SizedBox(height: 8),
              const _ConfidentialBanner(),
              const SizedBox(height: 20),
              _AgendaSection(
                title: 'Ready to sustain',
                subtitle:
                    'Accepted — bring these names to the pulpit on Sunday.',
                rows: agenda.readyToSustain,
              ),
              _AgendaSection(
                title: 'Ready to set apart',
                subtitle:
                    'Sustained but not yet set apart. Schedule during the week.',
                rows: agenda.readyToSetApart,
              ),
              _AgendaSection(
                title: 'Awaiting response',
                subtitle: 'Extended — waiting for the member to accept.',
                rows: agenda.awaitingResponse,
              ),
              _AgendaSection(
                title: 'New selections',
                subtitle:
                    'On the shortlist but not yet extended. Assign an extender.',
                rows: agenda.newSelections,
              ),
              _StalledSection(rows: agenda.stalled),
              _RecentActivitySection(rows: agenda.recent),
            ],
          ),
        ),
        _ShareBar(agenda: agenda, theme: theme),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Header + confidential banner
// ---------------------------------------------------------------------------

class _AgendaHeader extends StatelessWidget {
  const _AgendaHeader({required this.agenda});

  final BishopricAgenda agenda;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Bishopric agenda',
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          '${_formatDateLong(agenda.generatedAt)} · '
          '${agenda.inServiceCount} in service',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _ConfidentialBanner extends StatelessWidget {
  const _ConfidentialBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: ChapelPalette.amberLight,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: ChapelPalette.amber.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline,
              size: 18, color: ChapelPalette.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Confidential — Bishopric only',
              style: theme.textTheme.labelMedium?.copyWith(
                color: ChapelPalette.amber,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sections
// ---------------------------------------------------------------------------

/// A single agenda section: title bar with count + subtitle + list of rows.
/// Empty sections render a single italic "None." so the printout stays
/// visually complete rather than skipping headers.
class _AgendaSection extends StatelessWidget {
  const _AgendaSection({
    required this.title,
    required this.subtitle,
    required this.rows,
  });

  final String title;
  final String subtitle;
  final List<CallingSummaryRow> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(title: title, count: rows.length),
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 8),
            child: Text(
              subtitle,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          if (rows.isEmpty)
            const _EmptyLine()
          else
            _RowsCard(
              children: [
                for (var i = 0; i < rows.length; i++)
                  FadeSlideIn(
                    delay: Duration(milliseconds: 20 * i.clamp(0, 10)),
                    child: _CallingRow(row: rows[i]),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Stalled section — same shape as [_AgendaSection] but with a warning tone.
class _StalledSection extends StatelessWidget {
  const _StalledSection({required this.rows});

  final List<CallingSummaryRow> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = rows.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.hourglass_bottom,
                  size: 20, color: theme.colorScheme.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Stalled — 14+ days',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _CountPill(
                count: count,
                bg: theme.colorScheme.errorContainer,
                fg: theme.colorScheme.error,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 8),
            child: Text(
              'Callings sitting in the pipeline too long — decide, extend, '
              'or release.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          if (rows.isEmpty)
            const _EmptyLine(text: 'Nothing stalled. Nice.')
          else
            _RowsCard(
              children: [
                for (var i = 0; i < rows.length; i++)
                  FadeSlideIn(
                    delay: Duration(milliseconds: 20 * i.clamp(0, 10)),
                    child: _CallingRow(row: rows[i], emphasizeStale: true),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _RecentActivitySection extends StatelessWidget {
  const _RecentActivitySection({required this.rows});

  final List<RecentActivityRow> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(title: 'Recent activity', count: rows.length),
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 8),
            child: Text(
              'Last ${rows.length} state changes for the record.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          if (rows.isEmpty)
            const _EmptyLine()
          else
            _RowsCard(
              children: [
                for (var i = 0; i < rows.length; i++)
                  FadeSlideIn(
                    delay: Duration(milliseconds: 20 * i.clamp(0, 10)),
                    child: _RecentActivityRowTile(row: rows[i]),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Row primitives
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        _CountPill(
          count: count,
          bg: theme.colorScheme.primaryContainer,
          fg: theme.colorScheme.onPrimaryContainer,
        ),
      ],
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count, required this.bg, required this.fg});

  final int count;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _RowsCard extends StatelessWidget {
  const _RowsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final divided = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        divided.add(Divider(
          height: 1,
          thickness: 0.5,
          indent: 16,
          endIndent: 16,
          color: theme.colorScheme.outline.withValues(alpha: 0.15),
        ));
      }
      divided.add(children[i]);
    }
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.15),
        ),
      ),
      child: Column(children: divided),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine({this.text = 'None.'});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

class _CallingRow extends StatelessWidget {
  const _CallingRow({required this.row, this.emphasizeStale = false});

  final CallingSummaryRow row;

  /// When true, renders the "days waiting" trailing text in the error
  /// color to draw the eye. Used in the Stalled section.
  final bool emphasizeStale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final member = row.member;
    final calling = row.calling;
    final event = row.latestEvent;

    final name = member?.displayName ?? 'Unknown member';
    final org = (calling.organization ?? '').trim();
    final subtitleParts = <String>[
      calling.title,
      if (org.isNotEmpty) org,
    ];

    final days = event == null
        ? null
        : DateTime.now().difference(event.occurredAt).inDays;

    return InkWell(
      onTap: () {
        if (member == null) return;
        context.push(AppRoutes.callingDetail(member.id, calling.id));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitleParts.join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (days != null)
              Text(
                _formatDaysAgo(days),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: emphasizeStale
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight:
                      emphasizeStale ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RecentActivityRowTile extends StatelessWidget {
  const _RecentActivityRowTile({required this.row});

  final RecentActivityRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final member = row.member;
    final calling = row.calling;
    final event = row.event;

    return InkWell(
      onTap: () {
        if (member == null) return;
        context.push(AppRoutes.callingDetail(member.id, calling.id));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member?.displayName ?? 'Unknown member',
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${calling.title} → ${event.state.label}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _formatShortDate(event.occurredAt),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Share bar
// ---------------------------------------------------------------------------

class _ShareBar extends StatelessWidget {
  const _ShareBar({required this.agenda, required this.theme});

  final BishopricAgenda agenda;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.ios_share),
              label: const Text('Share as text'),
              onPressed: () => _shareAgenda(context, agenda),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _shareAgenda(BuildContext context, BishopricAgenda agenda) async {
  final text = renderAgendaAsText(agenda);
  final result = await Share.share(
    text,
    subject: 'Bishopric agenda — ${_formatDateLong(agenda.generatedAt)}',
  );
  if (!context.mounted) return;
  if (result.status == ShareResultStatus.unavailable) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sharing is not available on this device.')),
    );
  }
}

// ---------------------------------------------------------------------------
// Plaintext rendering
//
// Kept as a top-level function (not a widget) so it can be unit-tested
// without touching Flutter. The format is intentionally boring — flat
// sections, no fancy characters — so it renders identically in every
// messaging app, email client, or paper printout the bishopric might use.
// ---------------------------------------------------------------------------

/// Render an agenda as plaintext suitable for the platform share sheet.
///
/// Public so tests can call it without spinning up a widget.
String renderAgendaAsText(BishopricAgenda agenda) {
  final buf = StringBuffer();
  buf.writeln('Bishopric Agenda');
  buf.writeln(_formatDateLong(agenda.generatedAt));
  buf.writeln('${agenda.inServiceCount} callings in service');
  buf.writeln('Confidential — Bishopric only');
  buf.writeln();

  void section(String title, List<CallingSummaryRow> rows,
      {String emptyLabel = '(none)'}) {
    buf.writeln('${title.toUpperCase()} (${rows.length})');
    if (rows.isEmpty) {
      buf.writeln('  $emptyLabel');
    } else {
      for (final row in rows) {
        buf.writeln('  - ${_plainRowLine(row)}');
      }
    }
    buf.writeln();
  }

  section('Ready to sustain', agenda.readyToSustain);
  section('Ready to set apart', agenda.readyToSetApart);
  section('Awaiting response', agenda.awaitingResponse);
  section('New selections', agenda.newSelections);
  section('Stalled 14+ days', agenda.stalled,
      emptyLabel: '(none — nothing stalled)');

  buf.writeln('RECENT ACTIVITY (${agenda.recent.length})');
  if (agenda.recent.isEmpty) {
    buf.writeln('  (none)');
  } else {
    for (final row in agenda.recent) {
      final name = row.member?.displayName ?? 'Unknown member';
      final date = _formatShortDate(row.event.occurredAt);
      buf.writeln(
          '  - $name — ${row.calling.title} → ${row.event.state.label} ($date)');
    }
  }

  return buf.toString().trimRight();
}

String _plainRowLine(CallingSummaryRow row) {
  final name = row.member?.displayName ?? 'Unknown member';
  final org = (row.calling.organization ?? '').trim();
  final orgPart = org.isEmpty ? '' : ' ($org)';
  final event = row.latestEvent;
  final daysPart = event == null
      ? ''
      : ', ${_formatDaysAgo(DateTime.now().difference(event.occurredAt).inDays)}';
  return '$name — ${row.calling.title}$orgPart$daysPart';
}

// ---------------------------------------------------------------------------
// Date helpers
// ---------------------------------------------------------------------------

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

String _formatDateLong(DateTime dt) {
  return '${dt.day} ${_months[dt.month - 1]} ${dt.year}';
}

String _formatShortDate(DateTime dt) {
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

String _formatDaysAgo(int days) {
  if (days <= 0) return 'today';
  if (days == 1) return '1 day';
  return '$days days';
}
