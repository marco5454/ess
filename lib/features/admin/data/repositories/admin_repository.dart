import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/app_user.dart';
import '../../domain/entities/audit_log_entry.dart';
import '../../domain/entities/invite_code.dart';

/// Data-layer facade over the admin RPCs.
///
/// All methods hit SECURITY DEFINER Postgres functions that enforce
/// admin-only access; unauthorized callers get a `not authorized`
/// exception from the DB.
class AdminRepository {
  AdminRepository(this._client);

  final SupabaseClient _client;

  /// Whether the current auth user is an admin.
  Future<bool> isAdmin() async {
    final result = await _client.rpc('is_admin');
    return result == true;
  }

  /// All invite codes, newest first.
  Future<List<InviteCode>> listInviteCodes() async {
    final rows = await _client.rpc('list_invite_codes');
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(InviteCode.fromMap)
        .toList(growable: false);
  }

  /// Generate and persist a new random invite code. Returns the raw code.
  Future<String> createInviteCode({String? note}) async {
    final trimmed = note?.trim();
    final result = await _client.rpc(
      'create_invite_code',
      params: {
        'note_input': trimmed == null || trimmed.isEmpty ? null : trimmed,
      },
    );
    return result as String;
  }

  /// Delete an unused invite code. Returns true if a row was actually
  /// removed. Used codes cannot be revoked.
  Future<bool> revokeInviteCode(String code) async {
    final result = await _client.rpc(
      'revoke_invite_code',
      params: {'code_input': code},
    );
    return result == true;
  }

  /// All registered application users, most recently created first.
  Future<List<AppUser>> listUsers() async {
    final rows = await _client.rpc('list_users');
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(AppUser.fromMap)
        .toList(growable: false);
  }

  /// Promote [userId] to admin. Idempotent — succeeds silently if already
  /// an admin.
  Future<void> grantAdmin(String userId) async {
    await _client.rpc(
      'grant_admin',
      params: {'target_user': userId},
    );
  }

  /// Demote [userId] from admin. Throws on the server if this would leave
  /// zero admins.
  Future<void> revokeAdmin(String userId) async {
    await _client.rpc(
      'revoke_admin',
      params: {'target_user': userId},
    );
  }

  /// Hard-delete [userId] from `auth.users`. Server refuses to delete self
  /// or the last remaining admin.
  Future<void> deleteUser(String userId) async {
    await _client.rpc(
      'delete_user',
      params: {'target_user': userId},
    );
  }

  /// Bootstrap the very first admin. Only succeeds while `public.admins`
  /// is empty; used by the "no admins yet" UI on a fresh install.
  Future<void> bootstrapFirstAdmin(String userId) async {
    await _client.rpc(
      'bootstrap_first_admin',
      params: {'target_user': userId},
    );
  }

  /// Read a page of the audit log, newest-first. Keyset-paginated on
  /// `(occurred_at desc, id desc)`.
  ///
  /// Pass [before] and [beforeId] from the last entry of the previous page
  /// to fetch older rows. Omit both for the first page.
  ///
  /// Filters:
  ///   - [actionLike]: SQL LIKE pattern (e.g. `'member.%'`).
  ///   - [actorId]: restrict to a single actor.
  ///   - [entityType] / [entityId]: restrict to a single record (both
  ///     usually supplied together, but either can be used alone).
  ///   - [sinceAt] / [untilAt]: half-open date range on `occurred_at`
  ///     (`>= sinceAt` and `< untilAt`).
  Future<List<AuditLogEntry>> listAuditLog({
    DateTime? before,
    int? beforeId,
    int pageSize = 50,
    String? actionLike,
    String? actorId,
    String? entityType,
    String? entityId,
    DateTime? sinceAt,
    DateTime? untilAt,
  }) async {
    final rows = await _client.rpc(
      'list_audit_log',
      params: {
        'before_at': before?.toUtc().toIso8601String(),
        'before_id': beforeId,
        'page_size': pageSize,
        'action_like': actionLike,
        'actor': actorId,
        'entity_type_eq': entityType,
        'entity_id_eq': entityId,
        'since_at': sinceAt?.toUtc().toIso8601String(),
        'until_at': untilAt?.toUtc().toIso8601String(),
      },
    );
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(AuditLogEntry.fromMap)
        .toList(growable: false);
  }
}
