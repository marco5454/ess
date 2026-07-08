// ignore_for_file: prefer_initializing_formals
//
// The private-underscore backing fields (`_client`, `_dao`) work better as
// plain fields with an explicit initializer list than as public
// initializing-formal parameters, since the ctor is called with named args
// and the linter can't reconcile that with private field names.

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/calling.dart';
import '../../domain/entities/calling_event.dart';
import '../../domain/entities/calling_state.dart';
import '../local/callings_dao.dart';

/// Data-layer facade over the local Drift copy of `callings` and
/// `calling_events`, with pass-through writes to Supabase.
///
/// Reads (list / watch / get) go against the local database — that's the
/// single-source-of-truth for the UI so screens keep working offline.
/// Writes still round-trip to Supabase; on success the returned row is
/// mirrored locally so the UI updates immediately without waiting for the
/// realtime echo. Local optimistic writes and an outbox drain arrive in
/// Phase 3.
class CallingsRepository {
  CallingsRepository({
    required SupabaseClient client,
    required CallingsDao dao,
  })  : _client = client,
        _dao = dao;

  final SupabaseClient _client;
  final CallingsDao _dao;

  static const _callings = 'callings';
  static const _events = 'calling_events';

  // ---------------------------------------------------------------------------
  // Reads (local, live)

  /// All callings for [memberId] paired with each calling's most recent event.
  ///
  /// One-shot: takes the current snapshot from the live DB streams and joins
  /// callings + events in-memory. Callers that want live updates should watch
  /// the streams directly via the providers layer.
  Future<List<CallingWithLatestEvent>> listCallingsForMember(
    String memberId,
  ) async {
    final allCallings = await _dao.watchAllCallings().first;
    final callings = allCallings
        .where((c) => c.memberId == memberId)
        .toList(growable: false);
    if (callings.isEmpty) return const [];

    final allEvents = await _dao.watchAllEvents().first;
    final latestByCalling = <String, CallingEvent>{};
    for (final event in allEvents) {
      latestByCalling.putIfAbsent(event.callingId, () => event);
    }
    return callings
        .map((c) => CallingWithLatestEvent(
              calling: c,
              latestEvent: latestByCalling[c.id],
            ))
        .toList(growable: false);
  }

  /// Fetch a single calling by id. Throws if not found locally.
  Future<Calling> getCalling(String id) async {
    final calling = await _dao.getCallingById(id);
    if (calling == null) {
      throw StateError('Calling $id not found in local database');
    }
    return calling;
  }

  /// All non-deleted events for a calling, newest first.
  Future<List<CallingEvent>> listEventsForCalling(String callingId) {
    return _dao.listEventsForCalling(callingId);
  }

  /// All callings (ward-wide) paired with each calling's most recent event.
  ///
  /// One-shot snapshot equivalent to the old two-query fold; used by list
  /// screens that don't want to watch. The join is done in-memory over the
  /// current DB state.
  Future<List<CallingWithLatestEvent>> listAllWithLatestEvent() async {
    final callings = await _dao.watchAllCallings().first;
    if (callings.isEmpty) return const [];
    final events = await _dao.watchAllEvents().first;
    final latestByCalling = <String, CallingEvent>{};
    for (final event in events) {
      latestByCalling.putIfAbsent(event.callingId, () => event);
    }
    return callings
        .map((c) => CallingWithLatestEvent(
              calling: c,
              latestEvent: latestByCalling[c.id],
            ))
        .toList(growable: false);
  }

  /// Live stream of every non-deleted calling row.
  Stream<List<Calling>> watchAllCallings() => _dao.watchAllCallings();

  /// Live stream of every non-deleted calling_events row.
  Stream<List<CallingEvent>> watchAllEvents() => _dao.watchAllEvents();

  // ---------------------------------------------------------------------------
  // Writes (round-trip to Supabase, then mirror locally)

  /// Create a new calling and its initial `selected` event.
  ///
  /// Not transactional across the two tables — if the event insert fails, an
  /// orphan calling row remains. Acceptable trade-off for Phase 2; can be
  /// upgraded to a Postgres function later if it becomes a real problem.
  Future<Calling> addCalling(NewCalling input) async {
    final callingRow = await _client
        .from(_callings)
        .insert(input.toInsert())
        .select()
        .single();
    final calling = Calling.fromMap(callingRow);
    await _dao.upsertCallingFromServerMap(callingRow);

    final now = DateTime.now().toUtc();
    final eventRow = await _client.from(_events).insert({
      'calling_id': calling.id,
      'state': CallingState.selected.wireName,
      'occurred_at': now.toIso8601String(),
      'recorded_by': _client.auth.currentUser?.id,
    }).select().single();
    await _dao.upsertEventFromServerMap(eventRow);

    return calling;
  }

  /// Update a calling's descriptive fields. Does not touch state / events.
  Future<Calling> updateCalling(String id, CallingUpdate update) async {
    final row = await _client
        .from(_callings)
        .update(update.toUpdate())
        .eq('id', id)
        .select()
        .single();
    await _dao.upsertCallingFromServerMap(row);
    return Calling.fromMap(row);
  }

  /// Append a new state event to a calling's history.
  Future<CallingEvent> addEvent({
    required String callingId,
    required CallingState state,
    required DateTime occurredAt,
    String? notes,
  }) async {
    final trimmedNotes = notes?.trim();
    final payload = <String, dynamic>{
      'calling_id': callingId,
      'state': state.wireName,
      'occurred_at': occurredAt.toUtc().toIso8601String(),
      'recorded_by': _client.auth.currentUser?.id,
      if (trimmedNotes != null && trimmedNotes.isNotEmpty)
        'notes': trimmedNotes,
    };
    final row =
        await _client.from(_events).insert(payload).select().single();
    await _dao.upsertEventFromServerMap(row);
    return CallingEvent.fromMap(row);
  }

  /// Delete a single event by id.
  ///
  /// NOTE: still a hard DELETE against the server so this works against the
  /// initial schema (which lacked `deleted_at` on `calling_events`). The
  /// phase-1 migration adds the column and Phase 3 will switch this to a
  /// soft-delete + outbox flow. Locally we hard-delete on the realtime echo.
  Future<void> deleteEvent(String id) async {
    await _client.from(_events).delete().eq('id', id);
    await _dao.deleteEventById(id);
  }

  /// Delete a calling by id.
  ///
  /// Hard DELETE server-side; associated `calling_events` rows are removed
  /// via `ON DELETE CASCADE`. Same rationale as [deleteEvent] for keeping
  /// this a hard delete for now.
  Future<void> deleteCalling(String id) async {
    await _client.from(_callings).delete().eq('id', id);
    // Cascade locally too; the realtime DELETE payloads may or may not
    // arrive quickly for the cascaded events.
    await _dao.deleteCallingById(id);
  }
}
