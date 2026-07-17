import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/db/app_database_provider.dart';
import '../../../../core/sync/outbox_providers.dart';
import '../../../../core/sync/sync_service.dart';
import '../../../members/domain/entities/member.dart';
import '../../../members/presentation/providers/members_providers.dart';
import '../../data/local/tracked_activities_dao.dart';
import '../../data/repositories/tracked_activities_repository.dart';
import '../../domain/entities/activity_kind.dart';
import '../../domain/entities/activity_status.dart';
import '../../domain/entities/tracked_activity.dart';

/// Provides the singleton [TrackedActivitiesDao].
final trackedActivitiesDaoProvider = Provider<TrackedActivitiesDao>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return TrackedActivitiesDao(db);
});

/// Provides the singleton [TrackedActivitiesRepository].
final trackedActivitiesRepositoryProvider =
    Provider<TrackedActivitiesRepository>((ref) {
  return TrackedActivitiesRepository(
    dao: ref.watch(trackedActivitiesDaoProvider),
    outbox: ref.watch(outboxDaoProvider),
    kickDrain: () => ref.read(syncServiceProvider).drainOutbox(),
  );
});

/// Live ward-wide activities stream. Root source for every derived view.
final allActivitiesStreamProvider =
    StreamProvider<List<TrackedActivity>>((ref) {
  final repo = ref.watch(trackedActivitiesRepositoryProvider);
  return repo.watchAll();
});

/// A single activity by id. Live.
final activityByIdProvider =
    Provider.family<AsyncValue<TrackedActivity>, String>((ref, id) {
  final all = ref.watch(allActivitiesStreamProvider);
  return all.whenData((list) => list.firstWhere(
        (a) => a.id == id,
        orElse: () => throw StateError('Activity $id not found'),
      ));
});

/// A ward-wide row: an activity joined with its (optional) member.
///
/// [member] is null when the activity is ward-wide (no memberId) or the
/// referenced member is missing locally (edge case after a member archive).
class ActivityRow {
  const ActivityRow({required this.activity, this.member});

  final TrackedActivity activity;
  final Member? member;
}

/// All activities joined with their member. Live.
final activityRowsProvider = Provider<AsyncValue<List<ActivityRow>>>((ref) {
  final activitiesAsync = ref.watch(allActivitiesStreamProvider);
  final membersAsync = ref.watch(allMembersProvider);

  if (activitiesAsync.isLoading || membersAsync.isLoading) {
    return const AsyncValue.loading();
  }
  if (activitiesAsync.hasError) {
    return AsyncValue.error(
      activitiesAsync.error!,
      activitiesAsync.stackTrace ?? StackTrace.current,
    );
  }
  if (membersAsync.hasError) {
    return AsyncValue.error(
      membersAsync.error!,
      membersAsync.stackTrace ?? StackTrace.current,
    );
  }

  final membersById = {for (final m in membersAsync.value!) m.id: m};
  return AsyncValue.data(
    activitiesAsync.value!
        .map((a) => ActivityRow(
              activity: a,
              member: a.memberId == null ? null : membersById[a.memberId!],
            ))
        .toList(growable: false),
  );
});

/// Count of open (non-terminal) activities, for badges and headers.
final openActivityCountProvider = Provider<AsyncValue<int>>((ref) {
  final async = ref.watch(allActivitiesStreamProvider);
  return async.whenData((list) =>
      list.where((a) => !a.status.isTerminal).length);
});

/// Activities filtered by a specific kind. Live.
final activitiesByKindProvider =
    Provider.family<AsyncValue<List<TrackedActivity>>, ActivityKind>(
        (ref, kind) {
  final async = ref.watch(allActivitiesStreamProvider);
  return async.whenData((list) =>
      list.where((a) => a.kind == kind).toList(growable: false));
});

/// Activities filtered by a specific status. Live.
final activitiesByStatusProvider =
    Provider.family<AsyncValue<List<TrackedActivity>>, ActivityStatus>(
        (ref, status) {
  final async = ref.watch(allActivitiesStreamProvider);
  return async.whenData((list) =>
      list.where((a) => a.status == status).toList(growable: false));
});
