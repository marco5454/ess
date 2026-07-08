import 'package:drift/drift.dart';

import '../../../../core/db/app_database.dart';
import '../../domain/entities/calling.dart';
import '../../domain/entities/calling_event.dart';
import '../../domain/entities/calling_state.dart';

/// Local (Drift/SQLite) data access for `callings` and `calling_events`.
///
/// Reads are the source of truth for the UI. Writes here are called by
/// [SyncService] when Supabase realtime brings server changes; user-facing
/// mutations on `CallingsRepository` still round-trip to Supabase (local
/// optimistic writes + outbox arrive in Phase 3).
///
/// Both tables carry a nullable `deletedAt` tombstone; every read filters
/// `deletedAt IS NULL` so soft-deleted rows disappear from the UI without
/// forgetting the row exists (needed for reconciliation).
class CallingsDao {
  CallingsDao(this._db);

  final AppDatabase _db;

  // -------------------------------------------------------------------------
  // Reads

  /// Live stream of every non-deleted calling, newest-first by `created_at`.
  Stream<List<Calling>> watchAllCallings() {
    final query = _db.select(_db.callings)
      ..where((c) => c.deletedAt.isNull())
      ..orderBy([
        (c) => OrderingTerm(
              expression: c.createdAt,
              mode: OrderingMode.desc,
            ),
      ]);
    return query.watch().map(
          (rows) => rows.map(_callingToDomain).toList(growable: false),
        );
  }

  /// Live stream of every non-deleted calling event, newest-first by
  /// `occurred_at` (tie-broken by `created_at`).
  ///
  /// Matches the ordering used by the old Supabase-backed stream so any
  /// "current state = events.first" logic on top of this keeps working.
  Stream<List<CallingEvent>> watchAllEvents() {
    final query = _db.select(_db.callingEvents)
      ..where((e) => e.deletedAt.isNull())
      ..orderBy([
        (e) => OrderingTerm(
              expression: e.occurredAt,
              mode: OrderingMode.desc,
            ),
        (e) => OrderingTerm(
              expression: e.createdAt,
              mode: OrderingMode.desc,
            ),
      ]);
    return query.watch().map(
          (rows) => rows.map(_eventToDomain).toList(growable: false),
        );
  }

  /// One-shot fetch of a single calling. Returns null if absent or deleted.
  Future<Calling?> getCallingById(String id) async {
    final row = await (_db.select(_db.callings)
          ..where((c) => c.id.equals(id) & c.deletedAt.isNull()))
        .getSingleOrNull();
    return row == null ? null : _callingToDomain(row);
  }

  /// One-shot fetch of all non-deleted events for a single calling,
  /// newest-first.
  Future<List<CallingEvent>> listEventsForCalling(String callingId) async {
    final rows = await (_db.select(_db.callingEvents)
          ..where((e) =>
              e.callingId.equals(callingId) & e.deletedAt.isNull())
          ..orderBy([
            (e) => OrderingTerm(
                  expression: e.occurredAt,
                  mode: OrderingMode.desc,
                ),
            (e) => OrderingTerm(
                  expression: e.createdAt,
                  mode: OrderingMode.desc,
                ),
          ]))
        .get();
    return rows.map(_eventToDomain).toList(growable: false);
  }

  // -------------------------------------------------------------------------
  // Writes (server -> local)

  /// Upsert a calling row from a decoded PostgREST payload.
  Future<void> upsertCallingFromServerMap(Map<String, dynamic> map) {
    return _db.into(_db.callings).insertOnConflictUpdate(
          CallingsCompanion.insert(
            id: map['id'] as String,
            memberId: map['member_id'] as String,
            title: map['title'] as String,
            organization: Value(map['organization'] as String?),
            notes: Value(map['notes'] as String?),
            createdAt: _parseTimestamp(map['created_at'])!,
            updatedAt: _parseTimestamp(map['updated_at'])!,
            deletedAt: Value(_parseTimestamp(map['deleted_at'])),
          ),
        );
  }

  /// Batch upsert used by the initial seed.
  Future<void> replaceAllCallingsFromServer(
    List<Map<String, dynamic>> rows,
  ) {
    return _db.batch((batch) {
      for (final map in rows) {
        batch.insert(
          _db.callings,
          CallingsCompanion.insert(
            id: map['id'] as String,
            memberId: map['member_id'] as String,
            title: map['title'] as String,
            organization: Value(map['organization'] as String?),
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

  /// Upsert an event row from a decoded PostgREST payload.
  ///
  /// Falls back to `created_at` when `updated_at` is missing — this happens
  /// on databases that haven't yet applied the phase-1 server migration
  /// which added the column.
  Future<void> upsertEventFromServerMap(Map<String, dynamic> map) {
    return _db.into(_db.callingEvents).insertOnConflictUpdate(
          CallingEventsCompanion.insert(
            id: map['id'] as String,
            callingId: map['calling_id'] as String,
            state: map['state'] as String,
            occurredAt: _parseTimestamp(map['occurred_at'])!,
            notes: Value(map['notes'] as String?),
            recordedBy: Value(map['recorded_by'] as String?),
            createdAt: _parseTimestamp(map['created_at'])!,
            updatedAt: _parseTimestamp(map['updated_at']) ??
                _parseTimestamp(map['created_at'])!,
            deletedAt: Value(_parseTimestamp(map['deleted_at'])),
          ),
        );
  }

  /// Batch upsert used by the initial seed.
  Future<void> replaceAllEventsFromServer(
    List<Map<String, dynamic>> rows,
  ) {
    return _db.batch((batch) {
      for (final map in rows) {
        batch.insert(
          _db.callingEvents,
          CallingEventsCompanion.insert(
            id: map['id'] as String,
            callingId: map['calling_id'] as String,
            state: map['state'] as String,
            occurredAt: _parseTimestamp(map['occurred_at'])!,
            notes: Value(map['notes'] as String?),
            recordedBy: Value(map['recorded_by'] as String?),
            createdAt: _parseTimestamp(map['created_at'])!,
            updatedAt: _parseTimestamp(map['updated_at']) ??
                _parseTimestamp(map['created_at'])!,
            deletedAt: Value(_parseTimestamp(map['deleted_at'])),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  /// Hard-delete a calling row locally.
  ///
  /// Used when the realtime stream reports a server DELETE. Soft deletes
  /// (`deletedAt IS NOT NULL`) arrive as an update via
  /// [upsertCallingFromServerMap] and stay in the DB as tombstones — they
  /// just fall out of the [watchAllCallings] filter.
  Future<int> deleteCallingById(String id) {
    return (_db.delete(_db.callings)..where((c) => c.id.equals(id))).go();
  }

  /// Hard-delete an event row locally. Same rules as [deleteCallingById].
  Future<int> deleteEventById(String id) {
    return (_db.delete(_db.callingEvents)..where((e) => e.id.equals(id))).go();
  }

  /// Wipes every calling and event row. Called on sign-out.
  Future<void> deleteAll() async {
    await _db.delete(_db.callingEvents).go();
    await _db.delete(_db.callings).go();
  }

  // -------------------------------------------------------------------------
  // Row -> domain mappers

  Calling _callingToDomain(CallingRow row) {
    return Calling(
      id: row.id,
      memberId: row.memberId,
      title: row.title,
      organization: row.organization,
      notes: row.notes,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  CallingEvent _eventToDomain(CallingEventRow row) {
    return CallingEvent(
      id: row.id,
      callingId: row.callingId,
      state: CallingState.fromWire(row.state),
      occurredAt: row.occurredAt,
      notes: row.notes,
      recordedBy: row.recordedBy,
      createdAt: row.createdAt,
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
