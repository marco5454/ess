// ignore_for_file: prefer_initializing_formals
//
// Rationale: the private fields are named with underscores; using
// initializing formals here would force callers to pass `_client:` /
// `_dao:` because the parameter name would leak. Preferring the explicit
// assignment keeps the public constructor names clean (`client:`, `dao:`).

import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/members_dao.dart';
import '../../domain/entities/member.dart';

/// Data-layer facade over ward members.
///
/// Reads come from the local Drift database (populated by [SyncService]'s
/// initial seed and its realtime subscription). Writes still go straight to
/// Supabase; the returned row is mirrored into Drift so the UI updates
/// without waiting for the realtime echo. Optimistic offline writes arrive
/// with the outbox in Phase 3.
class MembersRepository {
  MembersRepository({
    required SupabaseClient client,
    required MembersDao dao,
  })  : _client = client,
        _dao = dao;

  final SupabaseClient _client;
  final MembersDao _dao;

  static const _table = 'members';

  /// Snapshot of members from the local DB. [activeOnly] defaults to true.
  Future<List<Member>> listMembers({bool activeOnly = true}) async {
    // One-shot: take the first emission from the live stream.
    return _dao.watchAll(activeOnly: activeOnly).first;
  }

  /// One-shot fetch for a single member by id. Throws if not found.
  Future<Member> getMember(String id) async {
    final row = await _dao.getById(id);
    if (row == null) {
      throw StateError('Member $id not found in local database');
    }
    return row;
  }

  /// Live stream of all members (active + archived), alphabetized. Callers
  /// filter client-side (see `activeMembersProvider`).
  ///
  /// Emits whenever the local DB row changes — from the initial seed, the
  /// realtime subscription, or a direct write from this device.
  Stream<List<Member>> watchMembers() {
    return _dao.watchAll(activeOnly: false);
  }

  /// Insert a new member on the server and mirror it locally.
  Future<Member> addMember(NewMember input) async {
    final row = await _client
        .from(_table)
        .insert(input.toInsert())
        .select()
        .single();
    await _dao.upsertFromServerMap(row);
    return Member.fromMap(row);
  }

  /// Update a member on the server and mirror the new row locally.
  Future<Member> updateMember(String id, MemberUpdate update) async {
    final row = await _client
        .from(_table)
        .update(update.toUpdate())
        .eq('id', id)
        .select()
        .single();
    await _dao.upsertFromServerMap(row);
    return Member.fromMap(row);
  }
}
