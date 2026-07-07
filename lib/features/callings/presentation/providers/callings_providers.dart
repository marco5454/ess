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

/// Callings (with their latest event) for a given member.
///
/// Invalidate `callingsForMemberProvider(memberId)` after mutations to
/// trigger a refetch. `.family` because it's parameterized by member id.
final callingsForMemberProvider =
    FutureProvider.family<List<CallingWithLatestEvent>, String>(
  (ref, memberId) async {
    final repo = ref.watch(callingsRepositoryProvider);
    return repo.listCallingsForMember(memberId);
  },
);

/// A single calling by id.
final callingByIdProvider = FutureProvider.family<Calling, String>((
  ref,
  callingId,
) async {
  final repo = ref.watch(callingsRepositoryProvider);
  return repo.getCalling(callingId);
});

/// The full event timeline for a calling, newest first.
final eventsForCallingProvider =
    FutureProvider.family<List<CallingEvent>, String>((ref, callingId) async {
  final repo = ref.watch(callingsRepositoryProvider);
  return repo.listEventsForCalling(callingId);
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

/// All callings ward-wide, joined with their member and latest event.
///
/// Composes [allMembersProvider] with a fresh repo call to
/// [CallingsRepository.listAllWithLatestEvent]. Invalidate this provider
/// after any calling / event mutation to refresh the summary screen.
final callingSummaryProvider =
    FutureProvider<List<CallingSummaryRow>>((ref) async {
  final repo = ref.watch(callingsRepositoryProvider);
  final members = await ref.watch(allMembersProvider.future);
  final callings = await repo.listAllWithLatestEvent();
  final memberById = {for (final m in members) m.id: m};
  return callings
      .map((c) => CallingSummaryRow(
            calling: c.calling,
            member: memberById[c.calling.memberId],
            latestEvent: c.latestEvent,
          ))
      .toList(growable: false);
});
