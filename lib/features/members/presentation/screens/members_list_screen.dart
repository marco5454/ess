import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/motion/motion.dart';
import '../../../../core/motion/skeletons.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/sync/sync_service.dart';
import '../../../../core/theme/chapel_theme.dart';
import '../../../callings/domain/entities/calling.dart';
import '../../../callings/presentation/providers/callings_providers.dart';
import '../../domain/entities/member.dart';
import '../providers/members_providers.dart';

/// Phase 2 members list — the "who's who" of the ward.
///
/// Members are alphabetized by last name and grouped under sticky
/// alphabetical section headers. Each row shows an initials avatar, the
/// member's display name (First Last, or Preferred Last), a calling
/// summary derived from their in-service callings, and a count badge when
/// they hold more than one calling.
///
/// The list can be filtered three ways:
///   - free-text search across first / last / preferred name (in the
///     app-bar);
///   - single-select filter chips below the search: All, Serving,
///     Unassigned, Youth (under 18 by date of birth);
///   - a "Show inactive members" toggle in the app-bar overflow menu,
///     off by default.
///
/// FAB opens the add-member form. Sign-out and About live in the app bar.
class MembersListScreen extends ConsumerStatefulWidget {
  const MembersListScreen({super.key});

  @override
  ConsumerState<MembersListScreen> createState() => _MembersListScreenState();
}

/// The high-level filter selector across the top of the list.
enum _MemberFilter {
  all,
  serving,
  unassigned,
  youth;

  String get label => switch (this) {
        _MemberFilter.all => 'All',
        _MemberFilter.serving => 'Serving',
        _MemberFilter.unassigned => 'Unassigned',
        _MemberFilter.youth => 'Youth',
      };
}

/// A member joined with their currently-in-service callings (may be empty).
/// Kept purely as a view-model for this screen so downstream widgets don't
/// need to know how the join happened.
class _MemberRowData {
  const _MemberRowData({required this.member, required this.callings});
  final Member member;
  final List<Calling> callings;
}

class _MembersListScreenState extends ConsumerState<MembersListScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  _MemberFilter _filter = _MemberFilter.all;
  bool _showInactive = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() => _query = value.trim().toLowerCase());
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
  }

  // ─── Filters ───────────────────────────────────────────────────────────

  /// Case-insensitive contains-match on first / last / preferred name.
  bool _matchesQuery(_MemberRowData row) {
    if (_query.isEmpty) return true;
    final m = row.member;
    final first = m.firstName.toLowerCase();
    final last = m.lastName.toLowerCase();
    final preferred = m.preferredName?.toLowerCase() ?? '';
    return first.contains(_query) ||
        last.contains(_query) ||
        preferred.contains(_query);
  }

  bool _matchesFilter(_MemberRowData row) {
    switch (_filter) {
      case _MemberFilter.all:
        return true;
      case _MemberFilter.serving:
        return row.callings.isNotEmpty;
      case _MemberFilter.unassigned:
        return row.callings.isEmpty;
      case _MemberFilter.youth:
        final dob = row.member.dateOfBirth;
        if (dob == null) return false;
        return _ageInYears(dob) < 18;
    }
  }

  // ─── Sectioning ────────────────────────────────────────────────────────

  /// Section key: first letter of the last name (upper case), or '#' for
  /// names starting with anything non-alphabetic. Empty last-name defensive.
  String _sectionKey(Member m) {
    final name = m.lastName.trim();
    if (name.isEmpty) return '#';
    final ch = name[0].toUpperCase();
    final code = ch.codeUnitAt(0);
    // 65..90 = 'A'..'Z'
    if (code >= 65 && code <= 90) return ch;
    return '#';
  }

  /// Alphabetical items with `String` section headers spliced in between
  /// `_MemberRowData` entries. Preserves the input order (already sorted
  /// by `sortName`).
  List<Object> _withSectionHeaders(List<_MemberRowData> rows) {
    final out = <Object>[];
    String? currentKey;
    for (final row in rows) {
      final key = _sectionKey(row.member);
      if (key != currentKey) {
        out.add(key);
        currentKey = key;
      }
      out.add(row);
    }
    return out;
  }

  // ─── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final membersAsync = _showInactive
        ? ref.watch(allMembersProvider)
        : ref.watch(activeMembersProvider);
    final callingsByMember =
        ref.watch(membersWithCallingsProvider).value ?? const {};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Members'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About',
            onPressed: () => context.push(AppRoutes.about),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'toggle-inactive':
                  setState(() => _showInactive = !_showInactive);
                  break;
                case 'sign-out':
                  performSignOut(ref);
                  break;
              }
            },
            itemBuilder: (_) => [
              CheckedPopupMenuItem<String>(
                value: 'toggle-inactive',
                checked: _showInactive,
                child: const Text('Show inactive'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'sign-out',
                child: ListTile(
                  leading: Icon(Icons.logout),
                  title: Text('Sign out'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(112),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search members',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: 'Clear search',
                            onPressed: _clearSearch,
                          ),
                    isDense: true,
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              _FilterChipsRow(
                selected: _filter,
                onSelect: (f) => setState(() => _filter = f),
              ),
            ],
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(allMembersStreamProvider);
          ref.invalidate(allCallingsStreamProvider);
          ref.invalidate(allEventsStreamProvider);
        },
        child: membersAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.only(top: 8),
            child: MembersListSkeleton(),
          ),
          error: (error, _) => ListView(
            children: [
              const SizedBox(height: 120),
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: FadeSlideIn(
                    child: Text('Failed to load members:\n$error',
                        textAlign: TextAlign.center),
                  ),
                ),
              ),
            ],
          ),
          data: (members) {
            if (members.isEmpty) {
              return _EmptyState(
                message: 'No members yet.\nTap + to add one.',
              );
            }

            // Join once, filter, then sort by lastName then firstName.
            final joined = members
                .map((m) => _MemberRowData(
                      member: m,
                      callings: callingsByMember[m.id] ?? const [],
                    ))
                .where(_matchesQuery)
                .where(_matchesFilter)
                .toList()
              ..sort((a, b) {
                final ln = a.member.lastName
                    .toLowerCase()
                    .compareTo(b.member.lastName.toLowerCase());
                if (ln != 0) return ln;
                return a.member.firstName
                    .toLowerCase()
                    .compareTo(b.member.firstName.toLowerCase());
              });

            if (joined.isEmpty) {
              return _EmptyState(
                message: _emptyMatchesMessage(),
              );
            }

            final items = _withSectionHeaders(joined);

            // Row stagger is capped at 12; headers don't participate so
            // long alphabetical scrolls don't feel sluggish.
            var rowStaggerIndex = 0;
            return ListView.builder(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                if (item is String) {
                  return _SectionHeader(letter: item);
                }
                final row = item as _MemberRowData;
                final tile = _MemberRow(row: row);
                final s = rowStaggerIndex.clamp(0, 12);
                rowStaggerIndex++;
                return FadeSlideIn(
                  delay: Duration(milliseconds: 25 * s),
                  child: tile,
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add member',
        onPressed: () => context.push(AppRoutes.memberAdd),
        child: const Icon(Icons.person_add),
      ),
    );
  }

  String _emptyMatchesMessage() {
    if (_query.isNotEmpty) {
      return 'No members match "${_searchController.text}".';
    }
    switch (_filter) {
      case _MemberFilter.all:
        return 'No members to show.';
      case _MemberFilter.serving:
        return 'No members are currently serving.';
      case _MemberFilter.unassigned:
        return 'Every active member has a calling.';
      case _MemberFilter.youth:
        return 'No youth (under 18) match the current view.\n'
            'Members without a date of birth are excluded.';
    }
  }
}

// ─── Widgets ────────────────────────────────────────────────────────────

class _FilterChipsRow extends StatelessWidget {
  const _FilterChipsRow({required this.selected, required this.onSelect});

  final _MemberFilter selected;
  final ValueChanged<_MemberFilter> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final f in _MemberFilter.values) ...[
            _FilterChip(
              label: f.label,
              selected: f == selected,
              onTap: () => onSelect(f),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      labelStyle: theme.textTheme.labelMedium?.copyWith(
        color: selected ? scheme.onPrimary : scheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
      selectedColor: scheme.primary,
      backgroundColor: scheme.surfaceContainerHighest,
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.letter});

  final String letter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      alignment: Alignment.centerLeft,
      child: Text(
        letter,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// Row for a single member. Shows initials avatar, display name, calling
/// summary line, and a trailing count badge when the member holds more
/// than one calling. Inactive members are rendered with reduced opacity.
class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.row});

  final _MemberRowData row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final m = row.member;
    final callings = row.callings;
    final isDim = !m.isActive;

    final subtitle = _callingSummary(callings);
    final subtitleColor = callings.isEmpty
        ? scheme.onSurfaceVariant.withValues(alpha: 0.75)
        : scheme.onSurfaceVariant;

    final content = ListTile(
      leading: _InitialsAvatar(member: m),
      title: Text(
        m.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleMedium,
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: subtitleColor,
          fontStyle:
              callings.isEmpty ? FontStyle.italic : FontStyle.normal,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (callings.length > 1)
            _CountBadge(count: callings.length)
          else if (!m.isActive)
            _InactivePill(),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
        ],
      ),
      onTap: () => context.push(AppRoutes.memberDetail(m.id)),
    );

    if (!isDim) return content;
    return Opacity(opacity: 0.55, child: content);
  }

  /// Compact one-line summary of the member's current callings. When the
  /// member holds three or more, we show the first two joined by " · "
  /// then a "+N more" suffix so the row doesn't wrap.
  String _callingSummary(List<Calling> callings) {
    if (callings.isEmpty) return 'No calling';
    if (callings.length <= 2) {
      return callings.map((c) => c.title).join(' · ');
    }
    final head = callings.take(2).map((c) => c.title).join(' · ');
    return '$head · +${callings.length - 2} more';
  }
}

/// Circular avatar with the member's initials. Background color is
/// derived from a stable hash of the member's id so the same person
/// always gets the same swatch across sessions and devices.
///
/// Uses a small chapel-palette rotation so the avatars feel like part of
/// the design system rather than random Material blues.
class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({required this.member});

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
      radius: 20,
      backgroundColor: bg,
      child: Text(
        initials,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
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

/// Small pill-shaped count badge shown to the right of a member's name
/// when they hold more than one calling. Communicates "this person is
/// carrying a load" without needing to list every title in the subtitle.
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
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Marker rendered in place of the count badge when an inactive member is
/// shown (only possible via the "Show inactive" toggle). Signals *why*
/// this row is dimmed without depending on color alone.
class _InactivePill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Inactive',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: FadeSlideIn(
              child: Text(message, textAlign: TextAlign.center),
            ),
          ),
        ),
      ],
    );
  }
}

/// Whole-year age from a birth date. `DateTime` arithmetic in Dart is
/// exact enough for our purposes; the Youth filter only cares about the
/// integer.
int _ageInYears(DateTime dob) {
  final now = DateTime.now();
  var years = now.year - dob.year;
  final hadBirthdayThisYear = now.month > dob.month ||
      (now.month == dob.month && now.day >= dob.day);
  if (!hadBirthdayThisYear) years -= 1;
  return years;
}
