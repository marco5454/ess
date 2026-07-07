/// A registered application user.
///
/// Materialised from the `list_users()` admin RPC, which joins
/// `auth.users` with `public.admins` server-side.
class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.createdAt,
    required this.isAdmin,
    this.emailConfirmedAt,
    this.lastSignInAt,
  });

  final String id;
  final String email;
  final DateTime createdAt;
  final bool isAdmin;
  final DateTime? emailConfirmedAt;
  final DateTime? lastSignInAt;

  /// True if the user has clicked the confirmation link in their email.
  bool get isConfirmed => emailConfirmedAt != null;

  factory AppUser.fromMap(Map<String, dynamic> map) {
    return AppUser(
      id: map['id'] as String,
      email: (map['email'] as String?) ?? '',
      createdAt: DateTime.parse(map['created_at'] as String),
      isAdmin: (map['is_admin'] as bool?) ?? false,
      emailConfirmedAt: map['email_confirmed_at'] == null
          ? null
          : DateTime.parse(map['email_confirmed_at'] as String),
      lastSignInAt: map['last_sign_in_at'] == null
          ? null
          : DateTime.parse(map['last_sign_in_at'] as String),
    );
  }
}
