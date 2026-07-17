import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

/// Local SQLite mirror of the server tables plus offline-sync bookkeeping.
///
/// Column names and types mirror `supabase/migrations/*` exactly so a row can
/// be inserted from a decoded PostgREST response with minimal massaging.
/// See the two migrations:
///   - `20260707154823_initial_schema.sql`
///   - `20260708160000_offline_sync_columns.sql`
///
/// All timestamps are stored in UTC. All primary keys are the same UUID
/// strings the server issues (stored as `TEXT`). SQLite has no native UUID
/// or enum types, so both are represented as `TEXT`.
///
/// This file only defines the schema; wiring into the app happens in later
/// phases.

/// Ward members. Mirrors `public.members`.
///
/// The generated row class is renamed to `MemberRow` to avoid colliding with
/// the domain entity `Member` in `features/members/domain/entities/member.dart`.
@DataClassName('MemberRow')
class Members extends Table {
  TextColumn get id => text()();
  TextColumn get firstName => text().named('first_name')();
  TextColumn get lastName => text().named('last_name')();
  TextColumn get preferredName => text().named('preferred_name').nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get notes => text().nullable()();
  // Postgres `date` column; we store the same YYYY-MM-DD ISO date as a
  // midnight-UTC DateTime. Consumers should ignore the time component.
  DateTimeColumn get dateOfBirth => dateTime().named('date_of_birth').nullable()();
  TextColumn get sex => text().nullable()();
  TextColumn get priesthoodOffice => text().named('priesthood_office').nullable()();
  BoolColumn get isActive => boolean().named('is_active').withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().named('created_at')();
  DateTimeColumn get updatedAt => dateTime().named('updated_at')();

  @override
  Set<Column> get primaryKey => {id};
}

/// Callings assigned to members. Mirrors `public.callings`.
///
/// `deletedAt` is the client-side tombstone from the phase-1 server migration;
/// non-null means the row is soft-deleted and must be hidden from UI + not
/// re-inserted by a sync round.
///
/// Row class renamed to `CallingRow` to avoid colliding with the domain
/// entity `Calling`.
@DataClassName('CallingRow')
class Callings extends Table {
  TextColumn get id => text()();
  TextColumn get memberId => text().named('member_id')();
  TextColumn get title => text()();
  TextColumn get organization => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().named('created_at')();
  DateTimeColumn get updatedAt => dateTime().named('updated_at')();
  DateTimeColumn get deletedAt => dateTime().named('deleted_at').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Append-only calling lifecycle events. Mirrors `public.calling_events`.
///
/// `state` holds the raw enum wire value (e.g. `'selected'`, `'set_apart'`)
/// so the server enum can be round-tripped without a client-side mapping
/// table. `updatedAt` is only meaningful after the phase-1 server migration
/// (older rows get `now()` on backfill).
///
/// Row class renamed to `CallingEventRow` to avoid colliding with the domain
/// entity `CallingEvent`.
@DataClassName('CallingEventRow')
class CallingEvents extends Table {
  TextColumn get id => text()();
  TextColumn get callingId => text().named('calling_id')();
  TextColumn get state => text()();
  DateTimeColumn get occurredAt => dateTime().named('occurred_at')();
  TextColumn get notes => text().nullable()();
  TextColumn get recordedBy => text().named('recorded_by').nullable()();
  // Optional free-text attribution ("who did this action") shown in the UI.
  // Independent from `recordedBy`, which is the auth user id of whoever
  // saved the event on their device. Added in schemaVersion 2.
  TextColumn get performedBy => text().named('performed_by').nullable()();
  DateTimeColumn get createdAt => dateTime().named('created_at')();
  DateTimeColumn get updatedAt => dateTime().named('updated_at')();
  DateTimeColumn get deletedAt => dateTime().named('deleted_at').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Queue of pending server mutations produced while offline (or that failed
/// to flush online). Drained by the sync worker in FIFO order.
///
/// [opId] is a client-generated UUID used as an idempotency key so a
/// half-applied retry can't cause a duplicate write. [payload] is the JSON
/// body needed to replay the mutation (columns for insert/update, PK for
/// delete). [attempts] and [lastError] let us back off and eventually surface
/// stuck items to the user.
@DataClassName('OutboxEntry')
class Outbox extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get opId => text().named('op_id').unique()();
  // Entity: 'members' | 'callings' | 'calling_events'
  TextColumn get entityType => text().named('entity_type')();
  TextColumn get entityId => text().named('entity_id')();
  // Operation: 'insert' | 'update' | 'delete'
  TextColumn get operation => text()();
  // JSON-encoded body (see docstring).
  TextColumn get payload => text()();
  DateTimeColumn get createdAt => dateTime().named('created_at').withDefault(currentDateAndTime)();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().named('last_error').nullable()();
}

/// Key/value bag for sync bookkeeping (e.g. `last_pull.members`).
/// Values are opaque strings; callers encode/decode as needed.
@DataClassName('SyncMetaEntry')
class SyncMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [Members, Callings, CallingEvents, Outbox, SyncMeta])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'bishopric_tracker'));

  /// Test-only constructor. Allows injecting an in-memory executor.
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // Add optional `performed_by` free-text attribution to
            // calling_events. Mirrors the Supabase migration
            // 20260717200000_calling_events_performed_by.sql.
            await m.addColumn(callingEvents, callingEvents.performedBy);
          }
        },
      );
}
