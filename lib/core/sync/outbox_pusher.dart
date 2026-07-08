import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../db/app_database.dart';
import 'outbox_dao.dart';

/// Pushes a single [OutboxEntry] to Supabase and returns whether it was
/// successfully written server-side.
///
/// The pusher deliberately swallows *nothing*: on network failure it
/// re-throws the [SocketException]/[TimeoutException]/[HttpException] so the
/// caller can distinguish "try again later" from a hard server-side error
/// that should still remove the entry. The caller is responsible for calling
/// [OutboxDao.recordAttempt] on failure and [OutboxDao.deleteById] on
/// success.
///
/// The payload is decoded and dispatched based on
/// `entity_type` + `operation`:
///   - members / insert  -> INSERT into `members`
///   - members / update  -> UPDATE `members` WHERE id = ...
///   - callings / insert -> INSERT into `callings`
///   - callings / update -> UPDATE `callings` WHERE id = ...
///   - callings / delete -> hard DELETE from `callings` WHERE id = ...
///   - calling_events / insert -> INSERT into `calling_events`
///   - calling_events / delete -> hard DELETE from `calling_events` WHERE id = ...
///
/// Server-side soft-deletes (setting `deleted_at`) are not yet used because
/// the phase-1 schema migration has not been applied to the deployed
/// Supabase project. When it is applied, `delete` ops will be flipped to
/// `update {deleted_at: now}` and this dispatcher will need to change
/// accordingly.
class OutboxPusher {
  OutboxPusher({required this.client});

  final SupabaseClient client;

  Future<void> push(OutboxEntry entry) async {
    final payload =
        entry.payload.isEmpty ? const <String, dynamic>{} : jsonDecode(entry.payload) as Map<String, dynamic>;

    switch (entry.entityType) {
      case OutboxEntityType.member:
        await _pushMember(entry, payload);
      case OutboxEntityType.calling:
        await _pushCalling(entry, payload);
      case OutboxEntityType.callingEvent:
        await _pushCallingEvent(entry, payload);
      default:
        // Unknown entity types are treated as a hard failure — bubble up so
        // the drainer can log and drop the entry.
        throw StateError('Unknown outbox entity_type: ${entry.entityType}');
    }
  }

  Future<void> _pushMember(OutboxEntry entry, Map<String, dynamic> payload) async {
    switch (entry.operation) {
      case OutboxOp.insert:
        await client.from('members').insert(payload);
      case OutboxOp.update:
        await client.from('members').update(payload).eq('id', entry.entityId);
      case OutboxOp.delete:
        // Members are archived via is_active=false, never hard-deleted.
        throw StateError('DELETE op not supported for members');
      default:
        throw StateError('Unknown outbox op: ${entry.operation}');
    }
  }

  Future<void> _pushCalling(OutboxEntry entry, Map<String, dynamic> payload) async {
    switch (entry.operation) {
      case OutboxOp.insert:
        await client.from('callings').insert(payload);
      case OutboxOp.update:
        await client.from('callings').update(payload).eq('id', entry.entityId);
      case OutboxOp.delete:
        // Hard DELETE — cascades to calling_events server-side. Will switch
        // to soft-delete once the phase-1 server migration is applied.
        await client.from('callings').delete().eq('id', entry.entityId);
      default:
        throw StateError('Unknown outbox op: ${entry.operation}');
    }
  }

  Future<void> _pushCallingEvent(
    OutboxEntry entry,
    Map<String, dynamic> payload,
  ) async {
    switch (entry.operation) {
      case OutboxOp.insert:
        await client.from('calling_events').insert(payload);
      case OutboxOp.delete:
        // Hard DELETE for now (matches current server schema).
        await client.from('calling_events').delete().eq('id', entry.entityId);
      case OutboxOp.update:
        // Not currently produced — calling_events is append-only for now.
        throw StateError('UPDATE op not supported for calling_events');
      default:
        throw StateError('Unknown outbox op: ${entry.operation}');
    }
  }
}
