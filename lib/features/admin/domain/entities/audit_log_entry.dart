/// A single row from the server-side audit log.
///
/// Materialised from the `list_audit_log()` admin RPC. See the migration
/// `20260708170000_admin_actions_and_audit_log.sql` for the source schema.
class AuditLogEntry {
  const AuditLogEntry({
    required this.id,
    required this.action,
    required this.occurredAt,
    this.actorId,
    this.actorEmail,
    this.entityType,
    this.entityId,
    this.summary,
    this.metadata,
  });

  /// Server-side bigint id. Used together with [occurredAt] for keyset
  /// pagination.
  final int id;

  /// Domain event name, e.g. `member.update`, `admin.grant`, `invite.create`.
  /// Namespaced by entity so filters can match a prefix like `member.%`.
  final String action;

  /// Server timestamp of the event.
  final DateTime occurredAt;

  final String? actorId;

  /// Snapshot of the actor's email at the time of the event. Survives
  /// user deletion.
  final String? actorEmail;

  /// `'member' | 'calling' | 'calling_event' | 'admin' | 'invite_code' |
  /// 'user'` or null for global events.
  final String? entityType;

  /// UUID or code (for invite codes), stringified for polymorphism.
  final String? entityId;

  /// Human-readable one-liner for the row.
  final String? summary;

  /// Structured before/after diff or any action-specific detail.
  final Map<String, dynamic>? metadata;

  factory AuditLogEntry.fromMap(Map<String, dynamic> map) {
    return AuditLogEntry(
      id: (map['id'] as num).toInt(),
      action: map['action'] as String,
      occurredAt: DateTime.parse(map['occurred_at'] as String),
      actorId: map['actor_id'] as String?,
      actorEmail: map['actor_email'] as String?,
      entityType: map['entity_type'] as String?,
      entityId: map['entity_id'] as String?,
      summary: map['summary'] as String?,
      metadata: (map['metadata'] as Map?)?.cast<String, dynamic>(),
    );
  }
}
