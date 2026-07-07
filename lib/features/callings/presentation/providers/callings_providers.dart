import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../members/domain/entities/member.dart';
import '../../../members/presentation/providers/members_providers.dart';
import '../../data/repositories/callings_repository.dart';
import '../../domain/entities/calling.dart';
import '../../domain/entities/calling_event.dart';

/// Provides the singleton [CallingsRepository].
final callingsRepositoryProvider = Provider<CallingsRepository>((ref) {
  return CallingsRepository(supabase);
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
