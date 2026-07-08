import 'package:supabase_flutter/supabase_flutter.dart';

/// Data-layer facade for Supabase auth operations that need business logic
/// on top of the raw SDK (invite-code redemption, password reset).
///
/// Bare sign-in stays inline in `LoginScreen` since it's a single call.
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  /// Non-authoritative pre-flight check: returns true if [code] appears to
  /// be valid and unused. Racy — the ground truth is `consumeInviteCode`
  /// below, which atomically validates and marks the code consumed.
  Future<bool> checkInviteCode(String code) async {
    final result = await _client.rpc(
      'check_invite_code',
      params: {'code_input': code},
    );
    return result == true;
  }

  /// Atomically validate [code] and mark it consumed for [userId]. Returns
  /// true when a row was updated; false if the code was missing or already
  /// used.
  Future<bool> consumeInviteCode(String code, String userId) async {
    final result = await _client.rpc(
      'consume_invite_code',
      params: {
        'code_input': code,
        'user_id': userId,
      },
    );
    return result == true;
  }

  /// Create a new user with [email] / [password] gated by [inviteCode].
  ///
  /// Flow:
  ///   1. Pre-flight [checkInviteCode] to avoid burning an auth.users row
  ///      on an obviously invalid code.
  ///   2. `auth.signUp` — creates the user. With email confirmations off
  ///      (see supabase/config.toml) a session is returned immediately.
  ///   3. [consumeInviteCode] — atomic redemption on the server.
  ///
  /// Throws [SignUpFailure] with a specific [SignUpFailureKind] on failure
  /// so the UI can surface a targeted message.
  Future<AuthResponse> signUpWithInvite({
    required String email,
    required String password,
    required String inviteCode,
  }) async {
    // Step 1: cheap pre-flight.
    final looksValid = await checkInviteCode(inviteCode);
    if (!looksValid) {
      throw const SignUpFailure(SignUpFailureKind.inviteInvalid);
    }

    // Step 2: create the user.
    final AuthResponse response;
    try {
      response = await _client.auth.signUp(email: email, password: password);
    } on AuthException catch (e) {
      // The Supabase client surfaces "already registered" as an AuthException
      // whose exact message varies by version; treat weak-password and
      // already-registered specifically, everything else generically.
      final msg = e.message.toLowerCase();
      if (msg.contains('already') && msg.contains('registered')) {
        throw SignUpFailure(SignUpFailureKind.emailInUse, cause: e);
      }
      if (msg.contains('password')) {
        throw SignUpFailure(SignUpFailureKind.weakPassword, cause: e);
      }
      throw SignUpFailure(SignUpFailureKind.other, cause: e);
    }

    final user = response.user;
    if (user == null) {
      // Signup succeeded server-side but returned no user — should only
      // happen when email confirmation is enabled. Treat as a config bug.
      throw const SignUpFailure(SignUpFailureKind.other);
    }

    // Step 3: atomic redemption. If this fails we leave the user account
    // in place — they can retry redemption from the "redeem invite" screen
    // on next login, and any admin can revoke the orphan account if needed.
    final consumed = await consumeInviteCode(inviteCode, user.id);
    if (!consumed) {
      throw SignUpFailure(
        SignUpFailureKind.inviteConsumeRaced,
        cause: null,
        userId: user.id,
      );
    }

    return response;
  }

  /// Redeem an invite code for the currently-signed-in user. Used by the
  /// small "orphan account" recovery flow when the initial signup succeeded
  /// but the consume step failed (race, network drop between calls).
  Future<bool> redeemInviteForCurrentUser(String code) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;
    return consumeInviteCode(code, userId);
  }

  /// Trigger Supabase's password-reset email. Returns silently on success;
  /// throws [AuthException] on server errors.
  ///
  /// Note: the reset link Supabase sends targets the site URL configured in
  /// the project's Auth settings. For deep-link handling into the app, see
  /// docs/admin-setup.md.
  Future<void> sendPasswordResetEmail(String email) async {
    await _client.auth.resetPasswordForEmail(email);
  }
}

/// Structured failure surface for [AuthRepository.signUpWithInvite].
enum SignUpFailureKind {
  /// The invite code pre-flight returned false. No user was created.
  inviteInvalid,

  /// Supabase reports the email is already registered.
  emailInUse,

  /// Supabase rejected the password (too short / too weak).
  weakPassword,

  /// The user was created but the atomic invite consumption failed
  /// (concurrent consumption, or the code was revoked between check and
  /// consume). The account exists and is signed in.
  inviteConsumeRaced,

  /// Anything else. See [SignUpFailure.cause] for the underlying error.
  other,
}

class SignUpFailure implements Exception {
  const SignUpFailure(this.kind, {this.cause, this.userId});

  final SignUpFailureKind kind;
  final Object? cause;

  /// Populated only when [kind] is [SignUpFailureKind.inviteConsumeRaced] —
  /// the account was created and needs manual redemption or cleanup.
  final String? userId;

  @override
  String toString() =>
      'SignUpFailure($kind${cause == null ? '' : ', cause: $cause'})';
}
