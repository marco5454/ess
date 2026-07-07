import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/app_user.dart';
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
}
