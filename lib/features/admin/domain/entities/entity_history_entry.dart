/// A single redacted history row for one entity (member/calling/…).
///
/// Materialised from the `list_audit_log_for_entity()` RPC. Compared to
/// the admin-only [AuditLogEntry], actor identity and metadata diff are
/// intentionally not returned by the server: any authenticated user can
/// call this RPC for a record they can already see, so leaking who
/// performed each edit or the before/after values would be a privacy
/// regression relative to just letting them view the record itself.
class EntityHistoryEntry {
  const EntityHistoryEntry({
    required this.id,
    required this.action,
    required this.occurredAt,
    this.summary,
  });

  /// Server-side bigint id. Used together with [occurredAt] for keyset
  /// pagination.
  final int id;

  /// Domain event name, e.g. `member.update`, `calling.create`.
  final String action;

  /// Server timestamp of the event.
  final DateTime occurredAt;

  /// Human-readable one-liner (already computed server-side).
  final String? summary;

  factory EntityHistoryEntry.fromMap(Map<String, dynamic> map) {
    return EntityHistoryEntry(
      id: (map['id'] as num).toInt(),
      action: map['action'] as String,
      occurredAt: DateTime.parse(map['occurred_at'] as String),
      summary: map['summary'] as String?,
    );
  }
}
