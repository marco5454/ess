import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// Entity types recognized by the outbox.
///
/// String values map 1:1 to Postgres table names so the drainer can dispatch
/// on `entityType` without an extra lookup.
class OutboxEntityType {
  const OutboxEntityType._();
  static const String member = 'members';
  static const String calling = 'callings';
  static const String callingEvent = 'calling_events';
}

/// Operations recognized by the outbox drainer.
class OutboxOp {
  const OutboxOp._();
  static const String insert = 'insert';
  static const String update = 'update';
  static const String delete = 'delete';
}

/// Data access for the local outbox queue.
///
/// The outbox records pending server mutations produced by user actions on
/// this device. Rows are added by the repositories when the user mutates
/// state; the sync worker drains them in FIFO order.
class OutboxDao {
  OutboxDao(this._db);

  final AppDatabase _db;

  /// Append a new pending mutation to the queue.
  ///
  /// [opId] must be a client-generated unique id (uuid v4) that stays stable
  /// across retries — the server-side write will use it as an idempotency
  /// key.
  Future<int> enqueue({
    required String opId,
    required String entityType,
    required String entityId,
    required String operation,
    required String payloadJson,
  }) {
    return _db.into(_db.outbox).insert(
          OutboxCompanion.insert(
            opId: opId,
            entityType: entityType,
            entityId: entityId,
            operation: operation,
            payload: payloadJson,
          ),
        );
  }

  /// Every pending entry in FIFO order (oldest first).
  Future<List<OutboxEntry>> listPending() {
    return (_db.select(_db.outbox)
          ..orderBy([
            (o) => OrderingTerm(expression: o.id),
          ]))
        .get();
  }

  /// Live count of pending entries. Used by the UI status pill.
  Stream<int> watchPendingCount() {
    final query = _db.selectOnly(_db.outbox)
      ..addColumns([_db.outbox.id.count()]);
    return query.watchSingle().map(
          (row) => row.read(_db.outbox.id.count()) ?? 0,
        );
  }

  /// Remove an entry after it was successfully pushed to the server.
  Future<int> deleteById(int id) {
    return (_db.delete(_db.outbox)..where((o) => o.id.equals(id))).go();
  }

  /// Record a failed flush attempt without removing the entry.
  Future<int> markFailure(int id, String error) {
    return (_db.update(_db.outbox)..where((o) => o.id.equals(id))).write(
      OutboxCompanion(
        attempts: Value.absent(), // incremented via custom below
        lastError: Value(error),
      ),
    );
  }

  /// Atomically increment `attempts` and record the last error.
  Future<void> recordAttempt(int id, String error) async {
    await _db.customStatement(
      'UPDATE outbox SET attempts = attempts + 1, last_error = ? WHERE id = ?',
      [error, id],
    );
  }

  /// Wipes every queued entry. Called on sign-out.
  Future<int> deleteAll() => _db.delete(_db.outbox).go();
}
