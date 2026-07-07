import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/member.dart';

/// Data-layer facade over the `members` Postgres table.
///
/// Wraps `SupabaseClient` calls so higher layers (providers, screens) do not
/// depend on Supabase specifics.
class MembersRepository {
  MembersRepository(this._client);

  final SupabaseClient _client;

  static const _table = 'members';

  /// Returns all members, alphabetical by last then first name.
  ///
  /// [activeOnly] defaults to `true` — matches the default list-view use case;
  /// pass `false` when you want to include moved-out / archived members.
  Future<List<Member>> listMembers({bool activeOnly = true}) async {
    final query = _client.from(_table).select();
    final filtered = activeOnly ? query.eq('is_active', true) : query;
    final rows = await filtered
        .order('last_name', ascending: true)
        .order('first_name', ascending: true);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(Member.fromMap)
        .toList(growable: false);
  }

  /// Fetch a single member by id. Throws if the row is missing.
  Future<Member> getMember(String id) async {
    final row = await _client.from(_table).select().eq('id', id).single();
    return Member.fromMap(row);
  }

  /// Live stream of every member row. RLS gates who can see what; the app's
  /// current policy is "any authenticated user sees everything".
  ///
  /// The stream emits the full table snapshot on subscribe and whenever any
  /// row changes. Callers filter / sort client-side. Ordering here matches
  /// what [listMembers] returned (last name then first name).
  Stream<List<Member>> watchMembers() {
    return _client
        .from(_table)
        .stream(primaryKey: ['id'])
        .order('last_name')
        .map(
          (rows) => rows.map(Member.fromMap).toList(growable: false)
            ..sort((a, b) {
              final byLast = a.lastName.toLowerCase().compareTo(
                b.lastName.toLowerCase(),
              );
              if (byLast != 0) return byLast;
              return a.firstName.toLowerCase().compareTo(
                b.firstName.toLowerCase(),
              );
            }),
        );
  }

  /// Insert a new member and return the persisted row.
  Future<Member> addMember(NewMember input) async {
    final row = await _client
        .from(_table)
        .insert(input.toInsert())
        .select()
        .single();
    return Member.fromMap(row);
  }

  /// Update an existing member and return the persisted row.
  ///
  /// All editable columns are written — optional fields set to `null` in
  /// [update] will be nulled in the database. Use [MemberUpdate.isActive] to
  /// archive (`false`) or restore (`true`) a member.
  Future<Member> updateMember(String id, MemberUpdate update) async {
    final row = await _client
        .from(_table)
        .update(update.toUpdate())
        .eq('id', id)
        .select()
        .single();
    return Member.fromMap(row);
  }
}
