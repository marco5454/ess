import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/supabase_config.dart';
import '../../data/repositories/members_repository.dart';
import '../../domain/entities/member.dart';

/// Provides the singleton [MembersRepository].
final membersRepositoryProvider = Provider<MembersRepository>((ref) {
  return MembersRepository(supabase);
});

/// The list of active members, alphabetized. UI screens watch this.
///
/// This is a [FutureProvider] rather than a stream: Phase 2 does not use
/// realtime. Invalidate the provider (`ref.invalidate(activeMembersProvider)`)
/// after mutations to trigger a refetch.
final activeMembersProvider = FutureProvider<List<Member>>((ref) async {
  final repo = ref.watch(membersRepositoryProvider);
  return repo.listMembers();
});

/// A single member by id. `.family` because it's parameterized.
final memberByIdProvider = FutureProvider.family<Member, String>((
  ref,
  id,
) async {
  final repo = ref.watch(membersRepositoryProvider);
  return repo.getMember(id);
});
