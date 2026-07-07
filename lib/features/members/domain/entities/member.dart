/// Domain model for a ward member the bishopric tracks.
///
/// Mirrors the `public.members` table (see `docs/phase-2-schema.md`).
///
/// Deliberately kept as a hand-rolled immutable class rather than pulling in
/// `freezed` / `json_serializable`. Small surface, easy to grok, no codegen.
class Member {
  const Member({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.preferredName,
    this.phone,
    this.email,
    this.notes,
    this.dateOfBirth,
    this.sex,
    this.priesthoodOffice,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String? preferredName;
  final String? phone;
  final String? email;
  final String? notes;
  final DateTime? dateOfBirth;
  final String? sex;
  final String? priesthoodOffice;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Convenience: `"Last, First"` for alphabetical list views.
  String get sortName => '$lastName, $firstName';

  /// Convenience: `"First Last"` (or `"Preferred Last"` if a preferred name is
  /// set) for display.
  String get displayName {
    final given = (preferredName?.trim().isNotEmpty ?? false)
        ? preferredName!.trim()
        : firstName;
    return '$given $lastName';
  }

  /// Build a [Member] from a Supabase row (a `Map<String, dynamic>` returned
  /// from PostgREST). Dates come across as ISO-8601 strings.
  factory Member.fromMap(Map<String, dynamic> map) {
    return Member(
      id: map['id'] as String,
      firstName: map['first_name'] as String,
      lastName: map['last_name'] as String,
      preferredName: map['preferred_name'] as String?,
      phone: map['phone'] as String?,
      email: map['email'] as String?,
      notes: map['notes'] as String?,
      dateOfBirth: _parseDate(map['date_of_birth']),
      sex: map['sex'] as String?,
      priesthoodOffice: map['priesthood_office'] as String?,
      isActive: map['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) return DateTime.parse(value);
    return null;
  }
}

/// Fields required/allowed when inserting a new member.
///
/// Separate from [Member] because inserts don't carry `id`, timestamps, or
/// (usually) `is_active`. Serializes to the exact column names Postgres
/// expects.
class NewMember {
  const NewMember({
    required this.firstName,
    required this.lastName,
    this.preferredName,
    this.phone,
    this.email,
    this.notes,
    this.dateOfBirth,
    this.sex,
    this.priesthoodOffice,
  });

  final String firstName;
  final String lastName;
  final String? preferredName;
  final String? phone;
  final String? email;
  final String? notes;
  final DateTime? dateOfBirth;
  final String? sex;
  final String? priesthoodOffice;

  /// Serialize for a PostgREST `insert`. Nulls and empty strings for optional
  /// text fields are dropped so the database defaults / NULLs apply cleanly.
  Map<String, dynamic> toInsert() {
    final map = <String, dynamic>{
      'first_name': firstName.trim(),
      'last_name': lastName.trim(),
    };
    void put(String key, String? value) {
      final v = value?.trim();
      if (v != null && v.isNotEmpty) map[key] = v;
    }

    put('preferred_name', preferredName);
    put('phone', phone);
    put('email', email);
    put('notes', notes);
    put('sex', sex);
    put('priesthood_office', priesthoodOffice);

    if (dateOfBirth != null) {
      // Postgres `date` column accepts YYYY-MM-DD.
      final d = dateOfBirth!;
      final iso =
          '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
      map['date_of_birth'] = iso;
    }
    return map;
  }
}
