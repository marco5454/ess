import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/presentation/providers/auth_state_provider.dart';
import '../db/app_database.dart';
import '../db/app_database_provider.dart';

/// Orchestrates the client's copy of the server tables.
///
/// Phase 2a scope (this file): a single "seed everything" pull that runs
/// after login. Called once on cold-start when we already have a session,
/// and once whenever a fresh sign-in happens. Later phases will layer on
/// realtime writes, incremental pulls, and the outbox drain.
///
/// The pull is intentionally naive: it fetches all rows and upserts each one.
/// The app is single-ward and volumes are small (thousands of rows at most),
/// so this pays for itself in simplicity.
class SyncService {
  SyncService({required this.db, required this.client});

  final AppDatabase db;
  final SupabaseClient client;

  static const _keyLastPullMembers = 'last_pull.members';
  static const _keyLastPullCallings = 'last_pull.callings';
  static const _keyLastPullCallingEvents = 'last_pull.calling_events';

  /// Pulls every visible row from the three server tables and mirrors them
  /// into the local database. Safe to call repeatedly — inserts use
  /// [InsertMode.insertOrReplace] so a re-pull is idempotent.
  ///
  /// Rows marked as soft-deleted on the server (`deleted_at IS NOT NULL`) are
  /// still copied down; local queries filter them out. Keeping them lets a
  /// later reconciliation pass detect tombstones without a separate delete
  /// endpoint.
  ///
  /// Errors are propagated so callers can surface them; this method does not
  /// retry.
  Future<void> seed() async {
    await _pullMembers();
    await _pullCallings();
    await _pullCallingEvents();
  }

  Future<void> _pullMembers() async {
    final rows = await client.from('members').select();
    final now = DateTime.now().toUtc();
    await db.batch((batch) {
      for (final raw in (rows as List).cast<Map<String, dynamic>>()) {
        batch.insert(
          db.members,
          MembersCompanion(
            id: Value(raw['id'] as String),
            firstName: Value(raw['first_name'] as String),
            lastName: Value(raw['last_name'] as String),
            preferredName: Value(raw['preferred_name'] as String?),
            phone: Value(raw['phone'] as String?),
            email: Value(raw['email'] as String?),
            notes: Value(raw['notes'] as String?),
            dateOfBirth: Value(_parseDate(raw['date_of_birth'])),
            sex: Value(raw['sex'] as String?),
            priesthoodOffice: Value(raw['priesthood_office'] as String?),
            isActive: Value(raw['is_active'] as bool? ?? true),
            createdAt:
                Value(DateTime.parse(raw['created_at'] as String).toUtc()),
            updatedAt:
                Value(DateTime.parse(raw['updated_at'] as String).toUtc()),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
    await _touchLastPull(_keyLastPullMembers, now);
  }

  Future<void> _pullCallings() async {
    final rows = await client.from('callings').select();
    final now = DateTime.now().toUtc();
    await db.batch((batch) {
      for (final raw in (rows as List).cast<Map<String, dynamic>>()) {
        batch.insert(
          db.callings,
          CallingsCompanion(
            id: Value(raw['id'] as String),
            memberId: Value(raw['member_id'] as String),
            title: Value(raw['title'] as String),
            organization: Value(raw['organization'] as String?),
            notes: Value(raw['notes'] as String?),
            createdAt:
                Value(DateTime.parse(raw['created_at'] as String).toUtc()),
            updatedAt:
                Value(DateTime.parse(raw['updated_at'] as String).toUtc()),
            deletedAt: Value(_parseTimestamp(raw['deleted_at'])),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
    await _touchLastPull(_keyLastPullCallings, now);
  }

  Future<void> _pullCallingEvents() async {
    final rows = await client.from('calling_events').select();
    final now = DateTime.now().toUtc();
    await db.batch((batch) {
      for (final raw in (rows as List).cast<Map<String, dynamic>>()) {
        batch.insert(
          db.callingEvents,
          CallingEventsCompanion(
            id: Value(raw['id'] as String),
            callingId: Value(raw['calling_id'] as String),
            state: Value(raw['state'] as String),
            occurredAt:
                Value(DateTime.parse(raw['occurred_at'] as String).toUtc()),
            notes: Value(raw['notes'] as String?),
            recordedBy: Value(raw['recorded_by'] as String?),
            createdAt:
                Value(DateTime.parse(raw['created_at'] as String).toUtc()),
            // `updated_at` was added by the phase-1 server migration and is
            // NOT NULL DEFAULT now(). If the migration hasn't been applied
            // yet the column is missing — fall back to created_at so we can
            // still seed against a legacy database during rollout.
            updatedAt: Value(
              DateTime.parse(
                (raw['updated_at'] ?? raw['created_at']) as String,
              ).toUtc(),
            ),
            deletedAt: Value(_parseTimestamp(raw['deleted_at'])),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
    await _touchLastPull(_keyLastPullCallingEvents, now);
  }

  Future<void> _touchLastPull(String key, DateTime at) async {
    await db.into(db.syncMeta).insert(
          SyncMetaCompanion(
            key: Value(key),
            value: Value(at.toIso8601String()),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    if (value is String && value.isNotEmpty) return DateTime.parse(value);
    return null;
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

/// Riverpod handle for [SyncService].
///
/// Depends on [appDatabaseProvider]; consumers should watch this rather than
/// constructing the service directly so hot-reload keeps working.
final syncServiceProvider = Provider<SyncService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return SyncService(db: db, client: Supabase.instance.client);
});

/// Fire-and-forget provider: runs a seed sync whenever the user becomes
/// authenticated. Intended to be watched once at app startup (see
/// `BishopricTrackerApp.build`).
///
/// Uses `ref.listen` rather than `ref.watch` on auth so we react to the
/// transition (unauthenticated -> authenticated) rather than every rebuild.
/// Seed errors are swallowed with a debug log — a failed initial pull is
/// non-fatal because Phase 2 screens still read live from Supabase, and later
/// phases will add proper retry/reconciliation.
final _seedOnLoginProvider = Provider<void>((ref) {
  // Prime once on first construction if we already have a session
  // (cold-start with cached auth).
  final initiallyAuthed = ref.read(isAuthenticatedProvider);
  if (initiallyAuthed) {
    _kickSeed(ref);
  }
  ref.listen<bool>(isAuthenticatedProvider, (previous, next) {
    if (next && !(previous ?? false)) {
      _kickSeed(ref);
    }
  });
});

void _kickSeed(Ref ref) {
  final sync = ref.read(syncServiceProvider);
  // Deliberately not awaited; this is a background side effect.
  // ignore: discarded_futures
  sync.seed().catchError((Object err, StackTrace st) {
    // Non-fatal; screens still read live from Supabase in Phase 2.
    // A structured logger will replace this in a later phase.
    // ignore: avoid_print
    print('SyncService.seed() failed: $err');
  });
}

/// Public re-export so `main.dart` can watch it to activate the listener.
final seedOnLoginProvider = _seedOnLoginProvider;
