import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/db/app_database_provider.dart';
import '../../../../core/sync/outbox_providers.dart';
import '../../../../core/sync/sync_service.dart';
import '../../../members/domain/entities/member.dart';
import '../../../members/presentation/providers/members_providers.dart';
import '../../data/local/callings_dao.dart';
import '../../data/repositories/callings_repository.dart';
import '../../domain/entities/calling.dart';
import '../../domain/entities/calling_event.dart';
import '../../domain/entities/calling_state.dart';

/// Provides the singleton [CallingsDao].
final callingsDaoProvider = Provider<CallingsDao>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return CallingsDao(db);
});

/// Provides the singleton [CallingsRepository].
final callingsRepositoryProvider = Provider<CallingsRepository>((ref) {
  return CallingsRepository(
    client: supabase,
    dao: ref.watch(callingsDaoProvider),
    outbox: ref.watch(outboxDaoProvider),
    kickDrain: () => ref.read(syncServiceProvider).drainOutbox(),
  );
});

/// Live ward-wide callings stream. Single upstream source; other providers
/// derive from it. Exported so pull-to-refresh can resubscribe.
final allCallingsStreamProvider = StreamProvider<List<Calling>>((ref) {
  final repo = ref.watch(callingsRepositoryProvider);
  return repo.watchAllCallings();
});

/// Live ward-wide events stream. Single upstream source; other providers
/// derive from it. Exported so pull-to-refresh can resubscribe.
final allEventsStreamProvider = StreamProvider<List<CallingEvent>>((ref) {
  final repo = ref.watch(callingsRepositoryProvider);
  return repo.watchAllEvents();
});

/// Combines the calling and events streams into the join expected by the
/// member-detail and summary screens. Emits whenever either upstream fires.
AsyncValue<List<CallingWithLatestEvent>> _joinCallingsWithLatestEvent(
  AsyncValue<List<Calling>> callingsAsync,
  AsyncValue<List<CallingEvent>> eventsAsync,
) {
  if (callingsAsync.isLoading || eventsAsync.isLoading) {
    return const AsyncValue.loading();
  }
  if (callingsAsync.hasError) {
    return AsyncValue.error(
      callingsAsync.error!,
      callingsAsync.stackTrace ?? StackTrace.current,
    );
  }
  if (eventsAsync.hasError) {
    return AsyncValue.error(
      eventsAsync.error!,
      eventsAsync.stackTrace ?? StackTrace.current,
    );
  }
  final callings = callingsAsync.value!;
  final events = eventsAsync.value!;

  // Events are already sorted newest-first; first hit per calling id wins.
  final latestByCalling = <String, CallingEvent>{};
  for (final event in events) {
    latestByCalling.putIfAbsent(event.callingId, () => event);
  }
  return AsyncValue.data(
    callings
        .map((c) => CallingWithLatestEvent(
              calling: c,
              latestEvent: latestByCalling[c.id],
            ))
        .toList(growable: false),
  );
}

/// Callings (with their latest event) for a given member. Live.
final callingsForMemberProvider = Provider.family<
    AsyncValue<List<CallingWithLatestEvent>>, String>((ref, memberId) {
  final callingsAsync = ref.watch(allCallingsStreamProvider);
  final eventsAsync = ref.watch(allEventsStreamProvider);
  final joined = _joinCallingsWithLatestEvent(callingsAsync, eventsAsync);
  return joined.whenData(
    (list) => list
        .where((c) => c.calling.memberId == memberId)
        .toList(growable: false),
  );
});

/// A single calling by id. Live.
final callingByIdProvider =
    Provider.family<AsyncValue<Calling>, String>((ref, callingId) {
  final callingsAsync = ref.watch(allCallingsStreamProvider);
  return callingsAsync.whenData((list) => list.firstWhere(
        (c) => c.id == callingId,
        orElse: () => throw StateError('Calling $callingId not found'),
      ));
});

/// The full event timeline for a calling, newest first. Live.
final eventsForCallingProvider = Provider.family<
    AsyncValue<List<CallingEvent>>, String>((ref, callingId) {
  final eventsAsync = ref.watch(allEventsStreamProvider);
  return eventsAsync.whenData(
    (list) => list
        .where((e) => e.callingId == callingId)
        .toList(growable: false),
  );
});

/// A ward-wide row: a calling, its owning member, and its latest event.
///
/// Used by the summary screen. [member] can be null defensively but every
/// calling has a NOT NULL member_id FK so in practice it's always present.
class CallingSummaryRow {
  const CallingSummaryRow({
    required this.calling,
    required this.member,
    this.latestEvent,
  });

  final Calling calling;
  final Member? member;
  final CallingEvent? latestEvent;
}

/// All callings ward-wide, joined with their member and latest event. Live.
///
/// Composes the three upstream streams (members, callings, events).
final callingSummaryProvider =
    Provider<AsyncValue<List<CallingSummaryRow>>>((ref) {
  final membersAsync = ref.watch(allMembersProvider);
  final callingsAsync = ref.watch(allCallingsStreamProvider);
  final eventsAsync = ref.watch(allEventsStreamProvider);

  final withLatest =
      _joinCallingsWithLatestEvent(callingsAsync, eventsAsync);

  if (membersAsync.isLoading || withLatest.isLoading) {
    return const AsyncValue.loading();
  }
  if (membersAsync.hasError) {
    return AsyncValue.error(
      membersAsync.error!,
      membersAsync.stackTrace ?? StackTrace.current,
    );
  }
  if (withLatest.hasError) {
    return AsyncValue.error(
      withLatest.error!,
      withLatest.stackTrace ?? StackTrace.current,
    );
  }

  final memberById = {for (final m in membersAsync.value!) m.id: m};
  return AsyncValue.data(
    withLatest.value!
        .map((c) => CallingSummaryRow(
              calling: c.calling,
              member: memberById[c.calling.memberId],
              latestEvent: c.latestEvent,
            ))
        .toList(growable: false),
  );
});

/// Aggregate counts for the dashboard.
///
/// [byState] holds the current count for every [CallingState] (defaults
/// to 0 when nothing is in that state). [staleInPipeline] counts callings
/// whose latest event is `selected` or `extended` and older than the
/// stale threshold (see [dashboardStaleThreshold]).
///
/// Callings with no events at all are not counted anywhere. In practice
/// every calling has at least one event (the initial `selected` written
/// at creation time), but we don't rely on that invariant here.
class DashboardCounts {
  const DashboardCounts({
    required this.byState,
    required this.staleInPipeline,
    required this.totalWithState,
  });

  final Map<CallingState, int> byState;
  final int staleInPipeline;

  /// The number of callings that have any recorded state (denominator for
  /// percentages, and a sanity check).
  final int totalWithState;
}

/// How old a pipeline (selected / extended) event has to be before the
/// dashboard flags it as stale. Matches the threshold used by
/// SummaryScreen's "Needs attention" tab.
const Duration dashboardStaleThreshold = Duration(days: 14);

/// Live dashboard counts derived from [callingSummaryProvider].
final dashboardCountsProvider = Provider<AsyncValue<DashboardCounts>>((ref) {
  final summaryAsync = ref.watch(callingSummaryProvider);
  return summaryAsync.whenData((rows) {
    final counts = {for (final s in CallingState.values) s: 0};
    var stale = 0;
    var total = 0;
    final now = DateTime.now();

    for (final row in rows) {
      final event = row.latestEvent;
      if (event == null) continue;
      total += 1;
      counts[event.state] = counts[event.state]! + 1;

      final isPipeline = event.state == CallingState.selected ||
          event.state == CallingState.extended;
      if (isPipeline &&
          now.difference(event.occurredAt) >= dashboardStaleThreshold) {
        stale += 1;
      }
    }
    return DashboardCounts(
      byState: counts,
      staleInPipeline: stale,
      totalWithState: total,
    );
  });
});

/// All callings currently in a given state, joined with their member.
///
/// Rows are sorted by `occurredAt` ascending (oldest transitions first) so
/// the drill-down naturally surfaces the stalest cases at the top.
final callingsInStateProvider = Provider.family<
    AsyncValue<List<CallingSummaryRow>>, CallingState>((ref, state) {
  final summaryAsync = ref.watch(callingSummaryProvider);
  return summaryAsync.whenData((rows) {
    final matches = rows
        .where((r) => r.latestEvent?.state == state)
        .toList(growable: false);
    matches.sort((a, b) =>
        a.latestEvent!.occurredAt.compareTo(b.latestEvent!.occurredAt));
    return matches;
  });
});

/// Distinct organization names already used across ward callings.
///
/// Feeds the "suggested organization" autocomplete on the add/edit calling
/// screens so users pick an existing spelling instead of coining a new one —
/// which keeps the Summary's group-by-organization view coherent.
///
/// Deduplication is case-insensitive. When variants exist (e.g. both
/// "Elders Quorum" and "elders quorum" have been entered historically), the
/// first casing encountered wins; that's good enough for a suggestion list.
/// Blank/null organizations are excluded. Result is sorted case-insensitively.
final distinctOrganizationsProvider = Provider<AsyncValue<List<String>>>((ref) {
  final callingsAsync = ref.watch(allCallingsStreamProvider);
  return callingsAsync.whenData((callings) {
    final seen = <String, String>{}; // lower-case key → original casing
    for (final c in callings) {
      final raw = c.organization?.trim();
      if (raw == null || raw.isEmpty) continue;
      seen.putIfAbsent(raw.toLowerCase(), () => raw);
    }
    final out = seen.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return out;
  });
});

/// One entry in the dashboard's "Recent activity" list — a state
/// transition joined with the calling it belongs to and the member who
/// received it.
///
/// Kept as a purpose-built view model (rather than piggybacking on
/// [CallingSummaryRow]) because the recent-activity list orders by event
/// time, not by member name, and never renders more than a handful of rows.
class RecentActivityRow {
  const RecentActivityRow({
    required this.event,
    required this.calling,
    required this.member,
  });

  final CallingEvent event;
  final Calling calling;
  final Member? member;
}

/// How many recent activity rows the dashboard shows. Small on purpose —
/// this is a "what changed lately" glance, not a history log.
const int dashboardRecentActivityLimit = 5;

/// The N most recent calling events ward-wide, each joined with its
/// calling and member. Live.
///
/// Feeds the dashboard's "Recent activity" section. Events are sourced
/// from [allEventsStreamProvider], which already emits newest-first
/// (occurred_at DESC, then created_at DESC). Rows whose calling has been
/// deleted are dropped defensively — an event with no calling has nothing
/// meaningful to display and can't be navigated to.
final recentActivityProvider =
    Provider<AsyncValue<List<RecentActivityRow>>>((ref) {
  final eventsAsync = ref.watch(allEventsStreamProvider);
  final callingsAsync = ref.watch(allCallingsStreamProvider);
  final membersAsync = ref.watch(allMembersProvider);

  if (eventsAsync.isLoading ||
      callingsAsync.isLoading ||
      membersAsync.isLoading) {
    return const AsyncValue.loading();
  }
  if (eventsAsync.hasError) {
    return AsyncValue.error(
      eventsAsync.error!,
      eventsAsync.stackTrace ?? StackTrace.current,
    );
  }
  if (callingsAsync.hasError) {
    return AsyncValue.error(
      callingsAsync.error!,
      callingsAsync.stackTrace ?? StackTrace.current,
    );
  }
  if (membersAsync.hasError) {
    return AsyncValue.error(
      membersAsync.error!,
      membersAsync.stackTrace ?? StackTrace.current,
    );
  }

  final callingsById = {for (final c in callingsAsync.value!) c.id: c};
  final membersById = {for (final m in membersAsync.value!) m.id: m};

  final rows = <RecentActivityRow>[];
  for (final event in eventsAsync.value!) {
    final calling = callingsById[event.callingId];
    if (calling == null) continue; // orphan — calling was deleted
    rows.add(RecentActivityRow(
      event: event,
      calling: calling,
      member: membersById[calling.memberId],
    ));
    if (rows.length >= dashboardRecentActivityLimit) break;
  }
  return AsyncValue.data(rows);
});

/// The set of calling states that mean the member is currently serving.
///
/// Kept in one place so the Members list, Summary "By organization" view,
/// and any future "who's serving?" view stay in sync. Terminal states
/// (`declined`, `released`) and pipeline states (`selected`, `extended`)
/// are intentionally excluded — a calling that hasn't been accepted yet
/// isn't "in service" from the ward's point of view.
const Set<CallingState> memberInServiceStates = {
  CallingState.accepted,
  CallingState.sustained,
  CallingState.setApart,
  CallingState.active,
};

/// Live map of `memberId → currently-in-service callings for that member`.
///
/// Built as a single provider (instead of a family, one per member id) so
/// the Members list can annotate every row with a lookup rather than
/// spinning up N subscriptions. One join, one rebuild whenever the
/// callings or events stream ticks.
///
/// The returned map only contains members who have at least one in-service
/// calling — callers should treat a missing key as "no callings", not "no
/// data". Callings inside each list are sorted by title (case-insensitive)
/// so the UI can render them stably.
final membersWithCallingsProvider =
    Provider<AsyncValue<Map<String, List<Calling>>>>((ref) {
  final callingsAsync = ref.watch(allCallingsStreamProvider);
  final eventsAsync = ref.watch(allEventsStreamProvider);
  final joined = _joinCallingsWithLatestEvent(callingsAsync, eventsAsync);
  return joined.whenData((list) {
    final byMember = <String, List<Calling>>{};
    for (final row in list) {
      final state = row.latestEvent?.state;
      if (state == null || !memberInServiceStates.contains(state)) continue;
      byMember.putIfAbsent(row.calling.memberId, () => []).add(row.calling);
    }
    for (final callings in byMember.values) {
      callings.sort((a, b) =>
          a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    }
    return byMember;
  });
});
