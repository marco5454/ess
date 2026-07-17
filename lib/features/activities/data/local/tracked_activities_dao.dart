import 'package:drift/drift.dart';

import '../../../../core/db/app_database.dart';
import '../../domain/entities/activity_kind.dart';
import '../../domain/entities/activity_status.dart';
import '../../domain/entities/tracked_activity.dart';

/// Local (Drift/SQLite) data access for `tracked_activities`.
///
/// Reads are the source of truth for the UI. Server->local writes come in
/// via [SyncService] (realtime + seed). Locally-authored writes come from
/// [TrackedActivitiesRepository].
///
/// Rows carry a nullable `deletedAt` tombstone; every UI read filters
/// `deletedAt IS NULL` so soft-deleted rows disappear without forgetting
/// that the row exists (still needed for reconciliation).
class TrackedActivitiesDao {
  TrackedActivitiesDao(this._db);

  final AppDatabase _db;

  // -------------------------------------------------------------------------
  // Reads

  /// Live stream of every non-deleted activity.
  ///
  /// Ordering: unfinished items first (pending/in-progress), then by due
  /// date ascending (nulls last), then by createdAt descending. This gives
  /// the list screen a sensible default without a filter.
  Stream<List<TrackedActivity>> watchAll() {
    final query = _db.select(_db.trackedActivities)
      ..where((a) => a.deletedAt.isNull())
      ..orderBy([
        // Terminal (completed/cancelled) sort after non-terminal.
        (a) => OrderingTerm(
              expression: a.status.equals(ActivityStatus.completed.wireName) |
                  a.status.equals(ActivityStatus.cancelled.wireName),
              mode: OrderingMode.asc,
            ),
        // Then earliest due date first (nulls last is default in SQLite
        // for ASC; drift wraps that).
        (a) => OrderingTerm(expression: a.dueAt, mode: OrderingMode.asc),
        (a) => OrderingTerm(
              expression: a.createdAt,
              mode: OrderingMode.desc,
            ),
      ]);
    return query.watch().map(
          (rows) => rows.map(_rowToDomain).toList(growable: false),
        );
  }

  /// One-shot fetch of a single activity. Returns null if absent or deleted.
  Future<TrackedActivity?> getById(String id) async {
    final row = await (_db.select(_db.trackedActivities)
          ..where((a) => a.id.equals(id) & a.deletedAt.isNull()))
        .getSingleOrNull();
    return row == null ? null : _rowToDomain(row);
  }

  // -------------------------------------------------------------------------
  // Writes (server -> local)

  /// Upsert an activity row from a decoded PostgREST payload.
  Future<void> upsertFromServerMap(Map<String, dynamic> map) {
    return _db.into(_db.trackedActivities).insertOnConflictUpdate(
          TrackedActivitiesCompanion.insert(
            id: map['id'] as String,
            memberId: Value(map['member_id'] as String?),
            title: map['title'] as String,
            kind: map['kind'] as String,
            status: map['status'] as String,
            dueAt: Value(_parseTimestamp(map['due_at'])),
            completedAt: Value(_parseTimestamp(map['completed_at'])),
            notes: Value(map['notes'] as String?),
            createdAt: _parseTimestamp(map['created_at'])!,
            updatedAt: _parseTimestamp(map['updated_at'])!,
            deletedAt: Value(_parseTimestamp(map['deleted_at'])),
          ),
        );
  }

  /// Batch upsert used by the initial seed.
  Future<void> replaceAllFromServer(List<Map<String, dynamic>> rows) {
    return _db.batch((batch) {
      for (final map in rows) {
        batch.insert(
          _db.trackedActivities,
          TrackedActivitiesCompanion.insert(
            id: map['id'] as String,
            memberId: Value(map['member_id'] as String?),
            title: map['title'] as String,
            kind: map['kind'] as String,
            status: map['status'] as String,
            dueAt: Value(_parseTimestamp(map['due_at'])),
            completedAt: Value(_parseTimestamp(map['completed_at'])),
            notes: Value(map['notes'] as String?),
            createdAt: _parseTimestamp(map['created_at'])!,
            updatedAt: _parseTimestamp(map['updated_at'])!,
            deletedAt: Value(_parseTimestamp(map['deleted_at'])),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  /// Hard-delete a row locally (used when realtime reports a DELETE).
  Future<int> deleteById(String id) {
    return (_db.delete(_db.trackedActivities)..where((a) => a.id.equals(id)))
        .go();
  }

  // -------------------------------------------------------------------------
  // Locally-authored writes

  /// Insert a locally-authored activity.
  Future<void> insertLocal(TrackedActivity activity) {
    return _db.into(_db.trackedActivities).insertOnConflictUpdate(
          TrackedActivitiesCompanion.insert(
            id: activity.id,
            memberId: Value(activity.memberId),
            title: activity.title,
            kind: activity.kind.wireName,
            status: activity.status.wireName,
            dueAt: Value(activity.dueAt),
            completedAt: Value(activity.completedAt),
            notes: Value(activity.notes),
            createdAt: activity.createdAt,
            updatedAt: activity.updatedAt,
            deletedAt: const Value(null),
          ),
        );
  }

  /// Apply a locally-authored update to an existing activity.
  Future<void> updateLocal(TrackedActivity activity) {
    return (_db.update(_db.trackedActivities)
          ..where((a) => a.id.equals(activity.id)))
        .write(
      TrackedActivitiesCompanion(
        memberId: Value(activity.memberId),
        title: Value(activity.title),
        kind: Value(activity.kind.wireName),
        status: Value(activity.status.wireName),
        dueAt: Value(activity.dueAt),
        completedAt: Value(activity.completedAt),
        notes: Value(activity.notes),
        updatedAt: Value(activity.updatedAt),
      ),
    );
  }

  /// Soft-delete an activity locally by stamping `deletedAt`.
  Future<int> softDeleteLocal(String id, DateTime deletedAt) {
    return (_db.update(_db.trackedActivities)..where((a) => a.id.equals(id)))
        .write(
      TrackedActivitiesCompanion(
        deletedAt: Value(deletedAt),
        updatedAt: Value(deletedAt),
      ),
    );
  }

  /// Wipes every activity row. Called on sign-out.
  Future<int> deleteAll() => _db.delete(_db.trackedActivities).go();

  // -------------------------------------------------------------------------
  // Row -> domain mappers

  TrackedActivity _rowToDomain(TrackedActivityRow row) {
    return TrackedActivity(
      id: row.id,
      memberId: row.memberId,
      title: row.title,
      kind: ActivityKind.fromWire(row.kind),
      status: ActivityStatus.fromWire(row.status),
      dueAt: row.dueAt,
      completedAt: row.completedAt,
      notes: row.notes,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  static DateTime? _parseTimestamp(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    if (value is String && value.isNotEmpty) {
      return DateTime.parse(value).toUtc();
    }
    return null;
  }
}
