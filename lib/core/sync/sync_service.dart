import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/presentation/providers/auth_state_provider.dart';
import '../../features/members/data/local/members_dao.dart';
import '../db/app_database.dart';
import '../db/app_database_provider.dart';

/// Orchestrates the client's copy of the server tables.
///
/// Two responsibilities:
///
///   * **Seed** — a one-shot `select *` per server table on login, mirrored
///     into the local Drift DB via each feature's DAO. Volumes are small
///     (single ward, thousands of rows at most) so we favor simplicity over
///     incremental strategies.
///   * **Realtime** — long-lived Supabase realtime subscriptions per table
///     that upsert (or delete) rows into Drift as the server emits changes.
///     Screens watch the local DB so any device's edits propagate here
///     automatically.
///
/// Local optimistic writes and the outbox drain arrive in Phase 3.
class SyncService {
  SyncService({
    required this.db,
    required this.client,
    required this.membersDao,
  });

  final AppDatabase db;
  final SupabaseClient client;
  final MembersDao membersDao;

  static const _keyLastPullMembers = 'last_pull.members';
  static const _keyLastPullCallings = 'last_pull.callings';
  static const _keyLastPullCallingEvents = 'last_pull.calling_events';

  RealtimeChannel? _membersChannel;

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

  /// Subscribe to server row changes and mirror them into Drift.
  ///
  /// Idempotent: calling `startRealtime` twice reuses existing channels.
  /// Call [stopRealtime] on sign-out.
  Future<void> startRealtime() async {
    _membersChannel ??= _subscribeMembers();
  }

  /// Tear down all realtime subscriptions. Called on sign-out and by the
  /// service disposer.
  Future<void> stopRealtime() async {
    final ch = _membersChannel;
    _membersChannel = null;
    if (ch != null) {
      await client.removeChannel(ch);
    }
  }

  RealtimeChannel _subscribeMembers() {
    return client
        .channel('public:members')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'members',
          callback: (payload) {
            switch (payload.eventType) {
              case PostgresChangeEvent.insert:
              case PostgresChangeEvent.update:
                final row = payload.newRecord;
                // ignore: discarded_futures
                membersDao.upsertFromServerMap(row);
                break;
              case PostgresChangeEvent.delete:
                final id = payload.oldRecord['id'] as String?;
                if (id != null) {
                  // ignore: discarded_futures
                  membersDao.deleteById(id);
                }
                break;
              case PostgresChangeEvent.all:
                // Not emitted — the union sentinel used only for the filter.
                break;
            }
          },
        )
        .subscribe();
  }

  Future<void> _pullMembers() async {
    final rows = await client.from('members').select();
    final list = (rows as List).cast<Map<String, dynamic>>();
    await membersDao.replaceAllFromServer(list);
    await _touchLastPull(_keyLastPullMembers, DateTime.now().toUtc());
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
  final service = SyncService(
    db: db,
    client: Supabase.instance.client,
    membersDao: MembersDao(db),
  );
  ref.onDispose(service.stopRealtime);
  return service;
});

/// Fire-and-forget provider: seeds + starts realtime whenever the user
/// becomes authenticated; tears realtime down on sign-out. Intended to be
/// watched once at app startup (see `BishopricTrackerApp.build`).
///
/// Seed errors are swallowed with a debug log — a failed initial pull is
/// non-fatal because the realtime subscription will still populate rows as
/// they change, and later phases will add proper retry/reconciliation.
final _syncLifecycleProvider = Provider<void>((ref) {
  // Prime once on first construction if we already have a session
  // (cold-start with cached auth).
  final initiallyAuthed = ref.read(isAuthenticatedProvider);
  if (initiallyAuthed) {
    _bringUp(ref);
  }
  ref.listen<bool>(isAuthenticatedProvider, (previous, next) {
    if (next && !(previous ?? false)) {
      _bringUp(ref);
    } else if (!next && (previous ?? false)) {
      _tearDown(ref);
    }
  });
});

void _bringUp(Ref ref) {
  final sync = ref.read(syncServiceProvider);
  // Deliberately not awaited; this is a background side effect.
  // ignore: discarded_futures
  sync.seed().catchError((Object err, StackTrace st) {
    // Non-fatal; realtime will still deliver ongoing changes.
    // A structured logger will replace this in a later phase.
    // ignore: avoid_print
    print('SyncService.seed() failed: $err');
  });
  // ignore: discarded_futures
  sync.startRealtime();
}

void _tearDown(Ref ref) {
  final sync = ref.read(syncServiceProvider);
  // ignore: discarded_futures
  sync.stopRealtime();
}

/// Public re-export so `main.dart` can watch it to activate the listener.
final seedOnLoginProvider = _syncLifecycleProvider;
