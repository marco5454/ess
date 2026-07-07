/// Domain model for a calling assigned to a member.
///
/// Mirrors `public.callings`. A calling's *state* lives in the separate
/// `calling_events` table (see [CallingEvent]) — this row only holds the
/// identity + descriptive fields.
class Calling {
  const Calling({
    required this.id,
    required this.memberId,
    required this.title,
    this.organization,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String memberId;
  final String title;
  final String? organization;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Calling.fromMap(Map<String, dynamic> map) {
    return Calling(
      id: map['id'] as String,
      memberId: map['member_id'] as String,
      title: map['title'] as String,
      organization: map['organization'] as String?,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}

/// Fields required/allowed when creating a new calling.
///
/// Creation also implicitly writes the first `calling_events` row with state
/// `selected` — see `CallingsRepository.addCalling`.
class NewCalling {
  const NewCalling({
    required this.memberId,
    required this.title,
    this.organization,
    this.notes,
  });

  final String memberId;
  final String title;
  final String? organization;
  final String? notes;

  Map<String, dynamic> toInsert() {
    final map = <String, dynamic>{
      'member_id': memberId,
      'title': title.trim(),
    };
    void put(String key, String? value) {
      final v = value?.trim();
      if (v != null && v.isNotEmpty) map[key] = v;
    }

    put('organization', organization);
    put('notes', notes);
    return map;
  }
}

/// Fields allowed when editing an existing calling.
///
/// Unlike [NewCalling], all optional fields are always written on save: an
/// empty string becomes `null` so the user can clear a value that was
/// previously set.
class CallingUpdate {
  const CallingUpdate({
    required this.title,
    this.organization,
    this.notes,
  });

  final String title;
  final String? organization;
  final String? notes;

  Map<String, dynamic> toUpdate() {
    String? nullIfBlank(String? v) {
      final t = v?.trim();
      return (t == null || t.isEmpty) ? null : t;
    }

    return <String, dynamic>{
      'title': title.trim(),
      'organization': nullIfBlank(organization),
      'notes': nullIfBlank(notes),
    };
  }
}
