import 'package:drift/drift.dart';

import '../../../../core/db/app_database.dart';
import '../../domain/entities/member.dart';

/// Local (Drift/SQLite) data access for the `members` table.
///
/// Reads are the source of truth for the UI. Writes here are called by
/// [SyncService] when the Supabase realtime stream brings server changes; the
/// user-facing mutation methods on `MembersRepository` still round-trip to
/// Supabase (local optimistic writes arrive in Phase 3 with the outbox).
class MembersDao {
  MembersDao(this._db);

  final AppDatabase _db;

  /// Live stream of all members, alphabetized last-name-then-first-name.
  ///
  /// When [activeOnly] is true (the default), archived rows are hidden.
  Stream<List<Member>> watchAll({bool activeOnly = true}) {
    final query = _db.select(_db.members);
    if (activeOnly) {
      query.where((m) => m.isActive.equals(true));
    }
    query.orderBy([
      (m) => OrderingTerm(expression: m.lastName),
      (m) => OrderingTerm(expression: m.firstName),
    ]);
    return query.watch().map(
          (rows) => rows.map(_toDomain).toList(growable: false),
        );
  }

  /// One-shot read for a single member. Returns null if absent.
  Future<Member?> getById(String id) async {
    final row = await (_db.select(_db.members)..where((m) => m.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  /// Upsert a row from a decoded server payload (`Map<String, dynamic>` as
  /// returned by PostgREST). Called by the realtime subscription in
  /// `SyncService`.
  Future<void> upsertFromServerMap(Map<String, dynamic> map) {
    return _db.into(_db.members).insertOnConflictUpdate(
          MembersCompanion.insert(
            id: map['id'] as String,
            firstName: map['first_name'] as String,
            lastName: map['last_name'] as String,
            preferredName: Value(map['preferred_name'] as String?),
            phone: Value(map['phone'] as String?),
            email: Value(map['email'] as String?),
            notes: Value(map['notes'] as String?),
            dateOfBirth: Value(_parseDate(map['date_of_birth'])),
            sex: Value(map['sex'] as String?),
            priesthoodOffice: Value(map['priesthood_office'] as String?),
            isActive: Value((map['is_active'] as bool?) ?? true),
            createdAt: _parseTimestamp(map['created_at'])!,
            updatedAt: _parseTimestamp(map['updated_at'])!,
          ),
        );
  }

  /// Batch upsert used by the initial seed. Assumes [rows] came from a fresh
  /// PostgREST select and every column is present.
  Future<void> replaceAllFromServer(List<Map<String, dynamic>> rows) {
    return _db.batch((batch) {
      for (final map in rows) {
        batch.insert(
          _db.members,
          MembersCompanion.insert(
            id: map['id'] as String,
            firstName: map['first_name'] as String,
            lastName: map['last_name'] as String,
            preferredName: Value(map['preferred_name'] as String?),
            phone: Value(map['phone'] as String?),
            email: Value(map['email'] as String?),
            notes: Value(map['notes'] as String?),
            dateOfBirth: Value(_parseDate(map['date_of_birth'])),
            sex: Value(map['sex'] as String?),
            priesthoodOffice: Value(map['priesthood_office'] as String?),
            isActive: Value((map['is_active'] as bool?) ?? true),
            createdAt: _parseTimestamp(map['created_at'])!,
            updatedAt: _parseTimestamp(map['updated_at'])!,
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  /// Insert a locally-authored row (from a user action while online or
  /// offline). The caller has already generated the `id` and the timestamps
  /// are synthesized here. `isActive` defaults to true.
  ///
  /// Written with `insertOnConflictUpdate` so a duplicate id from a rapid
  /// double-tap or a stale realtime echo doesn't crash.
  Future<void> insertLocal(Member member) {
    return _db.into(_db.members).insertOnConflictUpdate(
          MembersCompanion.insert(
            id: member.id,
            firstName: member.firstName,
            lastName: member.lastName,
            preferredName: Value(member.preferredName),
            phone: Value(member.phone),
            email: Value(member.email),
            notes: Value(member.notes),
            dateOfBirth: Value(member.dateOfBirth),
            sex: Value(member.sex),
            priesthoodOffice: Value(member.priesthoodOffice),
            isActive: Value(member.isActive),
            createdAt: member.createdAt,
            updatedAt: member.updatedAt,
          ),
        );
  }

  /// Apply a locally-authored update to an existing row.
  ///
  /// Every column is written unconditionally, mirroring the semantics of the
  /// PostgREST `update` call: blank optional values become `null`. Timestamps
  /// come from the caller (typically `updatedAt = DateTime.now().toUtc()`).
  Future<void> updateLocal(Member member) {
    return (_db.update(_db.members)..where((m) => m.id.equals(member.id)))
        .write(
      MembersCompanion(
        firstName: Value(member.firstName),
        lastName: Value(member.lastName),
        preferredName: Value(member.preferredName),
        phone: Value(member.phone),
        email: Value(member.email),
        notes: Value(member.notes),
        dateOfBirth: Value(member.dateOfBirth),
        sex: Value(member.sex),
        priesthoodOffice: Value(member.priesthoodOffice),
        isActive: Value(member.isActive),
        updatedAt: Value(member.updatedAt),
      ),
    );
  }

  /// Hard-delete used when the server realtime stream reports a row was
  /// removed. Callers must be sure the row is truly gone server-side —
  /// members currently never soft-delete (they use `is_active=false`), but
  /// the API is here for parity.
  Future<int> deleteById(String id) {
    return (_db.delete(_db.members)..where((m) => m.id.equals(id))).go();
  }

  /// Wipes every member row. Used on sign-out to keep another user's data
  /// from being visible on the device.
  Future<int> deleteAll() => _db.delete(_db.members).go();

  Member _toDomain(MemberRow row) {
    return Member(
      id: row.id,
      firstName: row.firstName,
      lastName: row.lastName,
      preferredName: row.preferredName,
      phone: row.phone,
      email: row.email,
      notes: row.notes,
      dateOfBirth: row.dateOfBirth,
      sex: row.sex,
      priesthoodOffice: row.priesthoodOffice,
      isActive: row.isActive,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    if (value is String && value.isNotEmpty) return DateTime.parse(value).toUtc();
    return null;
  }

  static DateTime? _parseTimestamp(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    if (value is String && value.isNotEmpty) return DateTime.parse(value).toUtc();
    return null;
  }
}
