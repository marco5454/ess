import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/supabase_config.dart';
import '../../data/repositories/callings_repository.dart';
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
