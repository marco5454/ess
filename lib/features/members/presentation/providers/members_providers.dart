import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/db/app_database_provider.dart';
import '../../data/local/members_dao.dart';
import '../../data/repositories/members_repository.dart';
import '../../domain/entities/member.dart';

/// Provides the local Drift-backed [MembersDao].
final membersDaoProvider = Provider<MembersDao>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return MembersDao(db);
});

/// Provides the singleton [MembersRepository].
final membersRepositoryProvider = Provider<MembersRepository>((ref) {
  return MembersRepository(
    client: supabase,
    dao: ref.watch(membersDaoProvider),
  );
});

/// Live ward-wide members stream (both active and archived).
///
/// This is the single upstream source: everything else in the app derives
/// filtered / mapped views from it. Backed by Supabase realtime replication;
/// updates from any device propagate here automatically.
///
/// Exported (not private) so pull-to-refresh gestures can force a
/// resubscribe via `ref.invalidate(allMembersStreamProvider)`.
final allMembersStreamProvider = StreamProvider<List<Member>>((ref) {
  final repo = ref.watch(membersRepositoryProvider);
  return repo.watchMembers();
});

/// Only active members, alphabetized. Used by the main members list.
final activeMembersProvider = Provider<AsyncValue<List<Member>>>((ref) {
  final all = ref.watch(allMembersStreamProvider);
  return all.whenData((list) =>
      list.where((m) => m.isActive).toList(growable: false));
});

/// All members (including archived), alphabetized.
///
/// Used by ward-wide views like the summary screen where a calling may
/// belong to a member who has since been archived.
final allMembersProvider = Provider<AsyncValue<List<Member>>>((ref) {
  return ref.watch(allMembersStreamProvider);
});

/// A single member by id. Derived from the ward-wide stream so it
/// updates live when any device edits the row.
final memberByIdProvider =
    Provider.family<AsyncValue<Member>, String>((ref, id) {
  final all = ref.watch(allMembersStreamProvider);
  return all.whenData((list) => list.firstWhere(
        (m) => m.id == id,
        orElse: () => throw StateError('Member $id not found'),
      ));
});
