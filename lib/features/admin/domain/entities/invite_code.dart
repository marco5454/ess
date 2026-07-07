/// An invite code row as returned by the `list_invite_codes` RPC.
class InviteCode {
  const InviteCode({
    required this.code,
    required this.createdAt,
    this.note,
    this.usedAt,
    this.usedBy,
  });

  final String code;
  final String? note;
  final DateTime createdAt;
  final DateTime? usedAt;
  final String? usedBy;

  bool get isUsed => usedAt != null;

  factory InviteCode.fromMap(Map<String, dynamic> map) {
    return InviteCode(
      code: map['code'] as String,
      note: map['note'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      usedAt: map['used_at'] == null
          ? null
          : DateTime.parse(map['used_at'] as String),
      usedBy: map['used_by'] as String?,
    );
  }
}
