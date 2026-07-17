import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../admin/domain/entities/entity_history_entry.dart';

/// Read-side facade over audit-log RPCs that any authenticated user can
/// invoke.
///
/// This intentionally does not depend on [AdminRepository] because these
/// endpoints are not admin-gated:
///   - `list_audit_log_for_entity` returns a redacted per-record history
///     to any signed-in user (see migration
///     `20260717210000_audit_log_extensions.sql` for the security model).
///   - `log_auth_event` lets clients self-report sign-in / sign-out /
///     password-reset requests; the server authoritatively attaches
///     `auth.uid()` as actor.
class AuditRepository {
  AuditRepository(this._client);

  final SupabaseClient _client;

  /// Redacted, per-entity history. Newest-first. Keyset-paginated on
  /// `(occurred_at desc, id desc)`.
  ///
  /// The server strips actor identity and metadata diffs before returning
  /// rows, so this is safe to expose in non-admin UIs (member detail,
  /// calling detail).
  Future<List<EntityHistoryEntry>> listForEntity({
    required String entityType,
    required String entityId,
    DateTime? before,
    int? beforeId,
    int pageSize = 50,
  }) async {
    final rows = await _client.rpc(
      'list_audit_log_for_entity',
      params: {
        'entity_type_in': entityType,
        'entity_id_in': entityId,
        'before_at': before?.toUtc().toIso8601String(),
        'before_id': beforeId,
        'page_size': pageSize,
      },
    );
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(EntityHistoryEntry.fromMap)
        .toList(growable: false);
  }

  /// Fire-and-forget: log an auth-adjacent event about the current user.
  ///
  /// The server whitelists [action] to `user.signin`, `user.signout`, or
  /// `user.password_reset_request`; anything else raises.
  ///
  /// Exceptions are swallowed intentionally: a failed audit write must
  /// never break sign-in / sign-out for the user.
  Future<void> logAuthEvent(
    String action, {
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await _client.rpc(
        'log_auth_event',
        params: {'action_in': action, 'metadata_in': metadata},
      );
    } catch (_) {
      // Best-effort telemetry; ignore.
    }
  }
}
