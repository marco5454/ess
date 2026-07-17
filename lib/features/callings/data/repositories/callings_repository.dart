// ignore_for_file: prefer_initializing_formals
//
// The private-underscore backing fields work better as plain fields with an
// explicit initializer list than as public initializing-formal parameters,
// since the ctor is called with named args and the linter can't reconcile
// that with private field names.

import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/sync/outbox_dao.dart';
import '../../domain/entities/calling.dart';
import '../../domain/entities/calling_event.dart';
import '../../domain/entities/calling_state.dart';
import '../local/callings_dao.dart';

/// Data-layer facade over the local Drift copy of `callings` and
/// `calling_events`, with pass-through writes to Supabase.
///
/// **Local-first** since Phase 3: every mutation writes to the local Drift
/// DB immediately (so the UI updates without waiting for the network), then
/// enqueues an outbox entry that the sync worker will push to Supabase.
/// When the realtime echo arrives it authoritative-overwrites the local row
/// via the DAO's `upsert...FromServerMap`.
///
/// Deletes are represented locally as *soft* deletes (a `deleted_at`
/// tombstone) so they disappear from the UI immediately without discarding
/// the row that the outbox still needs to reference. The server-side push,
/// however, is still a HARD DELETE — this keeps the drainer compatible with
/// the initial schema until the phase-1 server migration is applied.
class CallingsRepository {
  CallingsRepository({
    required SupabaseClient client,
    required CallingsDao dao,
    required OutboxDao outbox,
    required Future<void> Function() kickDrain,
    Uuid? uuid,
  })  : _client = client,
        _dao = dao,
        _outbox = outbox,
        _kickDrain = kickDrain,
        _uuid = uuid ?? const Uuid();

  final SupabaseClient _client;
  final CallingsDao _dao;
  final OutboxDao _outbox;
  final Future<void> Function() _kickDrain;
  final Uuid _uuid;

  // ---------------------------------------------------------------------------
  // Reads (local, live)

  /// All callings for [memberId] paired with each calling's most recent event.
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
  // Writes (local-first + outbox)

  /// Create a new calling and its initial `selected` event.
  ///
  /// Both rows are written locally in a Drift transaction, then two outbox
  /// entries are enqueued (calling insert, event insert) so they are pushed
  /// in order.
  Future<Calling> addCalling(NewCalling input) async {
    final now = DateTime.now().toUtc();
    final callingId = _uuid.v4();
    final eventId = _uuid.v4();

    final calling = Calling(
      id: callingId,
      memberId: input.memberId,
      title: input.title.trim(),
      organization: _blankToNull(input.organization),
      notes: _blankToNull(input.notes),
      createdAt: now,
      updatedAt: now,
    );
    final event = CallingEvent(
      id: eventId,
      callingId: callingId,
      state: CallingState.selected,
      occurredAt: now,
      notes: null,
      recordedBy: _client.auth.currentUser?.id,
      createdAt: now,
    );

    await _dao.insertCallingLocal(calling);
    await _dao.insertEventLocal(event);

    final callingPayload = <String, dynamic>{
      'id': callingId,
      ...input.toInsert(),
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };
    await _outbox.enqueue(
      opId: _uuid.v4(),
      entityType: OutboxEntityType.calling,
      entityId: callingId,
      operation: OutboxOp.insert,
      payloadJson: jsonEncode(callingPayload),
    );

    final eventPayload = <String, dynamic>{
      'id': eventId,
      'calling_id': callingId,
      'state': CallingState.selected.wireName,
      'occurred_at': now.toIso8601String(),
      'recorded_by': _client.auth.currentUser?.id,
      'created_at': now.toIso8601String(),
    };
    await _outbox.enqueue(
      opId: _uuid.v4(),
      entityType: OutboxEntityType.callingEvent,
      entityId: eventId,
      operation: OutboxOp.insert,
      payloadJson: jsonEncode(eventPayload),
    );

    _fireDrain();
    return calling;
  }

  /// Update a calling's descriptive fields. Does not touch state / events.
  Future<Calling> updateCalling(String id, CallingUpdate update) async {
    final now = DateTime.now().toUtc();
    final existing = await _dao.getCallingById(id);
    if (existing == null) {
      throw StateError('Calling $id not found in local database');
    }
    final calling = Calling(
      id: id,
      memberId: existing.memberId,
      title: update.title.trim(),
      organization: _blankToNull(update.organization),
      notes: _blankToNull(update.notes),
      createdAt: existing.createdAt,
      updatedAt: now,
    );
    await _dao.updateCallingLocal(calling);

    final payload = <String, dynamic>{
      ...update.toUpdate(),
      'updated_at': now.toIso8601String(),
    };
    await _outbox.enqueue(
      opId: _uuid.v4(),
      entityType: OutboxEntityType.calling,
      entityId: id,
      operation: OutboxOp.update,
      payloadJson: jsonEncode(payload),
    );
    _fireDrain();
    return calling;
  }

  /// Append a new state event to a calling's history.
  ///
  /// [performedBy] is an optional free-text attribution (e.g. "Bishop Smith")
  /// shown in the timeline. It is independent from the auth `recordedBy` id.
  Future<CallingEvent> addEvent({
    required String callingId,
    required CallingState state,
    required DateTime occurredAt,
    String? notes,
    String? performedBy,
  }) async {
    final trimmedNotes = notes?.trim();
    final trimmedPerformedBy = performedBy?.trim();
    final normalizedPerformedBy =
        (trimmedPerformedBy != null && trimmedPerformedBy.isNotEmpty)
            ? trimmedPerformedBy
            : null;
    final now = DateTime.now().toUtc();
    final eventId = _uuid.v4();
    final recordedBy = _client.auth.currentUser?.id;

    final event = CallingEvent(
      id: eventId,
      callingId: callingId,
      state: state,
      occurredAt: occurredAt.toUtc(),
      notes: (trimmedNotes != null && trimmedNotes.isNotEmpty)
          ? trimmedNotes
          : null,
      recordedBy: recordedBy,
      performedBy: normalizedPerformedBy,
      createdAt: now,
    );
    await _dao.insertEventLocal(event);

    final payload = <String, dynamic>{
      'id': eventId,
      'calling_id': callingId,
      'state': state.wireName,
      'occurred_at': occurredAt.toUtc().toIso8601String(),
      'recorded_by': recordedBy,
      'created_at': now.toIso8601String(),
      if (trimmedNotes != null && trimmedNotes.isNotEmpty)
        'notes': trimmedNotes,
      'performed_by': ?normalizedPerformedBy,
    };
    await _outbox.enqueue(
      opId: _uuid.v4(),
      entityType: OutboxEntityType.callingEvent,
      entityId: eventId,
      operation: OutboxOp.insert,
      payloadJson: jsonEncode(payload),
    );
    _fireDrain();
    return event;
  }

  /// Delete a single event by id.
  ///
  /// Local: soft-delete (stamps `deleted_at`) so it disappears from the UI
  /// immediately. Server: enqueued as a delete op; the drainer issues a
  /// hard DELETE until the phase-1 server migration is applied.
  Future<void> deleteEvent(String id) async {
    final now = DateTime.now().toUtc();
    await _dao.softDeleteEventLocal(id, now);
    await _outbox.enqueue(
      opId: _uuid.v4(),
      entityType: OutboxEntityType.callingEvent,
      entityId: id,
      operation: OutboxOp.delete,
      payloadJson: '{}',
    );
    _fireDrain();
  }

  /// Delete a calling by id. Same rules as [deleteEvent].
  Future<void> deleteCalling(String id) async {
    final now = DateTime.now().toUtc();
    await _dao.softDeleteCallingLocal(id, now);
    await _outbox.enqueue(
      opId: _uuid.v4(),
      entityType: OutboxEntityType.calling,
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
