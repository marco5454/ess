// ignore_for_file: prefer_initializing_formals
//
// The private-underscore backing fields work better as plain fields with an
// explicit initializer list than as public initializing-formal parameters,
// since the ctor is called with named args and the linter can't reconcile
// that with private field names.

import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../../core/sync/outbox_dao.dart';
import '../../domain/entities/activity_status.dart';
import '../../domain/entities/tracked_activity.dart';
import '../local/tracked_activities_dao.dart';

/// Data-layer facade over the local Drift copy of `tracked_activities`,
/// with local-first writes + outbox push to Supabase.
///
/// Mirrors [CallingsRepository]'s pattern:
///   1. Write to local Drift immediately (UI updates without waiting).
///   2. Enqueue an outbox entry.
///   3. Kick the drainer.
///   4. When the realtime echo arrives, the DAO's `upsertFromServerMap`
///      authoritative-overwrites the local row.
///
/// The specialized [updateStatus] helper stamps `completedAt` when moving
/// into `completed`, and clears it when moving back out — so the field
/// stays consistent without callers having to remember.
class TrackedActivitiesRepository {
  TrackedActivitiesRepository({
    required TrackedActivitiesDao dao,
    required OutboxDao outbox,
    required Future<void> Function() kickDrain,
    Uuid? uuid,
  })  : _dao = dao,
        _outbox = outbox,
        _kickDrain = kickDrain,
        _uuid = uuid ?? const Uuid();

  final TrackedActivitiesDao _dao;
  final OutboxDao _outbox;
  final Future<void> Function() _kickDrain;
  final Uuid _uuid;

  // ---------------------------------------------------------------------------
  // Reads (local, live)

  Stream<List<TrackedActivity>> watchAll() => _dao.watchAll();

  Future<TrackedActivity> get(String id) async {
    final activity = await _dao.getById(id);
    if (activity == null) {
      throw StateError('Activity $id not found in local database');
    }
    return activity;
  }

  // ---------------------------------------------------------------------------
  // Writes (local-first + outbox)

  Future<TrackedActivity> addActivity(NewTrackedActivity input) async {
    final now = DateTime.now().toUtc();
    final id = _uuid.v4();

    final activity = TrackedActivity(
      id: id,
      memberId: _blankToNull(input.memberId),
      title: input.title.trim(),
      kind: input.kind,
      status: input.status,
      dueAt: input.dueAt?.toUtc(),
      completedAt:
          input.status == ActivityStatus.completed ? now : null,
      notes: _blankToNull(input.notes),
      createdAt: now,
      updatedAt: now,
    );
    await _dao.insertLocal(activity);

    final payload = <String, dynamic>{
      'id': id,
      ...input.toInsert(),
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      if (activity.completedAt != null)
        'completed_at': activity.completedAt!.toIso8601String(),
    };
    await _outbox.enqueue(
      opId: _uuid.v4(),
      entityType: OutboxEntityType.trackedActivity,
      entityId: id,
      operation: OutboxOp.insert,
      payloadJson: jsonEncode(payload),
    );

    _fireDrain();
    return activity;
  }

  Future<TrackedActivity> updateActivity(
    String id,
    TrackedActivityUpdate update,
  ) async {
    final existing = await _dao.getById(id);
    if (existing == null) {
      throw StateError('Activity $id not found in local database');
    }
    final now = DateTime.now().toUtc();
    final resolvedDueAt = update.clearDueAt ? null : (update.dueAt?.toUtc());

    final activity = TrackedActivity(
      id: id,
      memberId: _blankToNull(update.memberId),
      title: update.title.trim(),
      kind: update.kind,
      status: existing.status,
      dueAt: resolvedDueAt,
      completedAt: existing.completedAt,
      notes: _blankToNull(update.notes),
      createdAt: existing.createdAt,
      updatedAt: now,
    );
    await _dao.updateLocal(activity);

    final payload = <String, dynamic>{
      ...update.toUpdate(),
      'updated_at': now.toIso8601String(),
    };
    await _outbox.enqueue(
      opId: _uuid.v4(),
      entityType: OutboxEntityType.trackedActivity,
      entityId: id,
      operation: OutboxOp.update,
      payloadJson: jsonEncode(payload),
    );
    _fireDrain();
    return activity;
  }

  /// Update just the status of an activity.
  ///
  /// Stamps `completedAt = now` when transitioning INTO `completed`; clears
  /// `completedAt` when transitioning OUT of `completed` (in case someone
  /// reopens the item by moving it back to `pending`/`inProgress`).
  Future<TrackedActivity> updateStatus(
    String id,
    ActivityStatus newStatus,
  ) async {
    final existing = await _dao.getById(id);
    if (existing == null) {
      throw StateError('Activity $id not found in local database');
    }
    final now = DateTime.now().toUtc();
    final DateTime? completedAt;
    if (newStatus == ActivityStatus.completed) {
      completedAt = existing.completedAt ?? now;
    } else {
      // Reopened, or moved into cancelled — either way, no longer completed.
      completedAt = null;
    }

    final activity = TrackedActivity(
      id: id,
      memberId: existing.memberId,
      title: existing.title,
      kind: existing.kind,
      status: newStatus,
      dueAt: existing.dueAt,
      completedAt: completedAt,
      notes: existing.notes,
      createdAt: existing.createdAt,
      updatedAt: now,
    );
    await _dao.updateLocal(activity);

    final payload = <String, dynamic>{
      'status': newStatus.wireName,
      'completed_at': completedAt?.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };
    await _outbox.enqueue(
      opId: _uuid.v4(),
      entityType: OutboxEntityType.trackedActivity,
      entityId: id,
      operation: OutboxOp.update,
      payloadJson: jsonEncode(payload),
    );
    _fireDrain();
    return activity;
  }

  Future<void> deleteActivity(String id) async {
    final now = DateTime.now().toUtc();
    await _dao.softDeleteLocal(id, now);
    await _outbox.enqueue(
      opId: _uuid.v4(),
      entityType: OutboxEntityType.trackedActivity,
      entityId: id,
      operation: OutboxOp.delete,
      payloadJson: '{}',
    );
    _fireDrain();
  }

  void _fireDrain() {
    // ignore: discarded_futures
    _kickDrain();
  }

  static String? _blankToNull(String? value) {
    if (value == null) return null;
    final t = value.trim();
    return t.isEmpty ? null : t;
  }
}
