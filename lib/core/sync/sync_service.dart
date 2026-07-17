import 'dart:async';
import 'dart:io' show SocketException;

import 'package:drift/drift.dart' show InsertMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/audit/presentation/providers/audit_providers.dart';
import '../../features/auth/presentation/providers/auth_state_provider.dart';
import '../../features/callings/data/local/callings_dao.dart';
import '../../features/members/data/local/members_dao.dart';
import '../db/app_database.dart';
import '../db/app_database_provider.dart';
import 'connectivity_service.dart';
import 'outbox_dao.dart';
import 'outbox_pusher.dart';

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
    required this.callingsDao,
    required this.outboxDao,
    required this.outboxPusher,
  });

  final AppDatabase db;
  final SupabaseClient client;
  final MembersDao membersDao;
  final CallingsDao callingsDao;
  final OutboxDao outboxDao;
  final OutboxPusher outboxPusher;

  static const _keyLastPullMembers = 'last_pull.members';
  static const _keyLastPullCallings = 'last_pull.callings';
  static const _keyLastPullCallingEvents = 'last_pull.calling_events';

  RealtimeChannel? _membersChannel;
  RealtimeChannel? _callingsChannel;
  RealtimeChannel? _callingEventsChannel;

  /// Pulls every visible row from the three server tables and mirrors them
  /// into the local database. Safe to call repeatedly — the DAO upserts use
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
    _callingsChannel ??= _subscribeCallings();
    _callingEventsChannel ??= _subscribeCallingEvents();
  }

  /// Tear down all realtime subscriptions. Called on sign-out and by the
  /// service disposer.
  Future<void> stopRealtime() async {
    final channels = <RealtimeChannel?>[
      _membersChannel,
      _callingsChannel,
      _callingEventsChannel,
    ];
    _membersChannel = null;
    _callingsChannel = null;
    _callingEventsChannel = null;
    for (final ch in channels) {
      if (ch != null) {
        await client.removeChannel(ch);
      }
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

  RealtimeChannel _subscribeCallings() {
    return client
        .channel('public:callings')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'callings',
          callback: (payload) {
            switch (payload.eventType) {
              case PostgresChangeEvent.insert:
              case PostgresChangeEvent.update:
                final row = payload.newRecord;
                // ignore: discarded_futures
                callingsDao.upsertCallingFromServerMap(row);
                break;
              case PostgresChangeEvent.delete:
                final id = payload.oldRecord['id'] as String?;
                if (id != null) {
                  // ignore: discarded_futures
                  callingsDao.deleteCallingById(id);
                }
                break;
              case PostgresChangeEvent.all:
                break;
            }
          },
        )
        .subscribe();
  }

  RealtimeChannel _subscribeCallingEvents() {
    return client
        .channel('public:calling_events')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'calling_events',
          callback: (payload) {
            switch (payload.eventType) {
              case PostgresChangeEvent.insert:
              case PostgresChangeEvent.update:
                final row = payload.newRecord;
                // ignore: discarded_futures
                callingsDao.upsertEventFromServerMap(row);
                break;
              case PostgresChangeEvent.delete:
                final id = payload.oldRecord['id'] as String?;
                if (id != null) {
                  // ignore: discarded_futures
                  callingsDao.deleteEventById(id);
                }
                break;
              case PostgresChangeEvent.all:
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
    final list = (rows as List).cast<Map<String, dynamic>>();
    await callingsDao.replaceAllCallingsFromServer(list);
    await _touchLastPull(_keyLastPullCallings, DateTime.now().toUtc());
  }

  Future<void> _pullCallingEvents() async {
    final rows = await client.from('calling_events').select();
    final list = (rows as List).cast<Map<String, dynamic>>();
    await callingsDao.replaceAllEventsFromServer(list);
    await _touchLastPull(_keyLastPullCallingEvents, DateTime.now().toUtc());
  }

  Future<void> _touchLastPull(String key, DateTime at) async {
    await db.into(db.syncMeta).insert(
          SyncMetaCompanion.insert(
            key: key,
            value: at.toIso8601String(),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  /// Attempt to push every pending outbox entry to Supabase in FIFO order.
  ///
  /// Concurrency-safe: only one drain runs at a time; a second call while
  /// a drain is in progress awaits the same future. Aborts the batch (but
  /// keeps entries in the queue) as soon as we hit something that looks
  /// like a network failure so we don't hammer a dead connection. Other
  /// failures (server 400/403/etc.) are recorded on the entry and the
  /// drain continues.
  Future<void> drainOutbox() {
    return _drain ??= _doDrain().whenComplete(() => _drain = null);
  }

  Future<void>? _drain;

  Future<void> _doDrain() async {
    final pending = await outboxDao.listPending();
    for (final entry in pending) {
      try {
        await outboxPusher.push(entry);
        await outboxDao.deleteById(entry.id);
      } on SocketException catch (e) {
        // Network is down — stop the batch, leave the entry in the queue.
        await outboxDao.recordAttempt(entry.id, e.toString());
        return;
      } on TimeoutException catch (e) {
        await outboxDao.recordAttempt(entry.id, e.toString());
        return;
      } catch (e) {
        // Server-side error (constraint violation, 4xx, etc.). Record and
        // move on so one bad entry doesn't block the queue.
        await outboxDao.recordAttempt(entry.id, e.toString());
      }
    }
  }

  /// Sign the user out cleanly, wiping local state.
  ///
  /// Order of operations matters:
  ///   1. Tear down realtime channels so no incoming rows write into DAOs
  ///      after we've already dropped their tables.
  ///   2. Delete outbox rows first — any pending mutations belong to the
  ///      signed-out user and would be pushed under a stale JWT if we ran
  ///      a drain in between.
  ///   3. Delete cached rows in FK-safe order (events → callings → members).
  ///   4. Sign out of Supabase. Catches errors so a network failure at the
  ///      end of sign-out (device already offline) doesn't leave local
  ///      state half-cleared.
  ///
  /// After this returns, the caller should also flip the sticky offline-
  /// authed flag; see [performSignOut] which wraps both steps.
  Future<void> signOutAndWipeLocal() async {
    await stopRealtime();
    await outboxDao.deleteAll();
    await callingsDao.deleteAll();
    await membersDao.deleteAll();
    try {
      await client.auth.signOut();
    } catch (_) {
      // Best-effort. Even if the server round-trip fails, local state is
      // already cleared and the sticky flag reset below will send the
      // router to /login.
    }
  }
}

/// Riverpod handle for [SyncService].
///
/// Depends on [appDatabaseProvider]; consumers should watch this rather than
/// constructing the service directly so hot-reload keeps working.
final syncServiceProvider = Provider<SyncService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final client = Supabase.instance.client;
  final service = SyncService(
    db: db,
    client: client,
    membersDao: MembersDao(db),
    callingsDao: CallingsDao(db),
    outboxDao: OutboxDao(db),
    outboxPusher: OutboxPusher(client: client),
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

  // Kick a drain any time the device transitions offline → online while the
  // user is still signed in. Pending mutations made while offline will flush
  // without requiring a fresh mutation or a restart.
  ref.listen<AsyncValue<bool>>(connectivityStatusProvider, (previous, next) {
    final wasOnline = previous?.value ?? false;
    final isOnline = next.value ?? false;
    if (isOnline && !wasOnline && ref.read(isAuthenticatedProvider)) {
      // ignore: discarded_futures
      ref.read(syncServiceProvider).drainOutbox();
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
  // Best-effort drain: any writes made while offline (or that failed to
  // flush on the previous session) go out here. Errors are handled inside
  // the drainer; nothing to catch.
  // ignore: discarded_futures
  sync.drainOutbox();
}

void _tearDown(Ref ref) {
  final sync = ref.read(syncServiceProvider);
  // ignore: discarded_futures
  sync.stopRealtime();
}

/// Public re-export so `main.dart` can watch it to activate the listener.
final seedOnLoginProvider = _syncLifecycleProvider;

/// Cleanly sign the current user out.
///
/// Wipes local Drift caches + outbox, calls `supabase.auth.signOut()`, and
/// resets the sticky offline-authed flag so the router redirect flips to
/// `/login` on the next refresh.
///
/// Call from any Riverpod-aware widget or provider; the two AppBar
/// sign-out buttons are the primary call sites.
Future<void> performSignOut(WidgetRef ref) async {
  // Best-effort audit before we tear down the session — after signOut,
  // auth.uid() is null and the server-side helper rejects the call.
  await ref.read(auditRepositoryProvider).logAuthEvent('user.signout');
  final sync = ref.read(syncServiceProvider);
  await sync.signOutAndWipeLocal();
  markSignedOut(ref);
}

/// [Ref]-based variant of [performSignOut] for use inside providers/services.
Future<void> performSignOutFromRef(Ref ref) async {
  await ref.read(auditRepositoryProvider).logAuthEvent('user.signout');
  final sync = ref.read(syncServiceProvider);
  await sync.signOutAndWipeLocal();
  markSignedOutFromRef(ref);
}
