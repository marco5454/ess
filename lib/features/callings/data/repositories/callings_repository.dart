import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/calling.dart';
import '../../domain/entities/calling_event.dart';
import '../../domain/entities/calling_state.dart';

/// Data-layer facade over the `callings` and `calling_events` Postgres tables.
class CallingsRepository {
  CallingsRepository(this._client);

  final SupabaseClient _client;

  static const _callings = 'callings';
  static const _events = 'calling_events';

  /// All callings for [memberId] paired with each calling's most recent event.
  ///
  /// Ordered by calling `created_at` descending (newest first). The two-query
  /// approach (callings, then events for that set) keeps things simple; a
  /// single member's calling count is small.
  Future<List<CallingWithLatestEvent>> listCallingsForMember(
    String memberId,
  ) async {
    final callingRows = await _client
        .from(_callings)
        .select()
        .eq('member_id', memberId)
        .order('created_at', ascending: false);

    final callings = (callingRows as List)
        .cast<Map<String, dynamic>>()
        .map(Calling.fromMap)
        .toList(growable: false);

    if (callings.isEmpty) return const [];

    final callingIds = callings.map((c) => c.id).toList(growable: false);
    final eventRows = await _client
        .from(_events)
        .select()
        .inFilter('calling_id', callingIds)
        .order('occurred_at', ascending: false)
        .order('created_at', ascending: false);

    // First event we see per calling_id is the latest (thanks to the ordering).
    final latestByCalling = <String, CallingEvent>{};
    for (final row in (eventRows as List).cast<Map<String, dynamic>>()) {
      final event = CallingEvent.fromMap(row);
      latestByCalling.putIfAbsent(event.callingId, () => event);
    }

    return callings
        .map((c) => CallingWithLatestEvent(
              calling: c,
              latestEvent: latestByCalling[c.id],
            ))
        .toList(growable: false);
  }

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

    final now = DateTime.now().toUtc();
    await _client.from(_events).insert({
      'calling_id': calling.id,
      'state': CallingState.selected.wireName,
      'occurred_at': now.toIso8601String(),
      'recorded_by': _client.auth.currentUser?.id,
    });

    return calling;
  }
}
