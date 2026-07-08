import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/sync/connectivity_service.dart';

/// Streams Supabase auth state changes.
///
/// Emits an [AuthState] whenever the user signs in, signs out, has their token
/// refreshed, etc. Consumers can watch this to react to session changes (for
/// example, the router's redirect logic).
final authStateProvider = StreamProvider<AuthState>((ref) {
  return supabase.auth.onAuthStateChange;
});

/// Convenience provider: the currently-signed-in [Session], or `null` if the
/// user is signed out.
///
/// Uses [authStateProvider] as its trigger and reads the current session
/// directly from the Supabase client. This avoids stale values on first
/// subscription (the auth stream does not replay the last event).
final currentSessionProvider = Provider<Session?>((ref) {
  // Rebuild whenever auth state changes.
  ref.watch(authStateProvider);
  return supabase.auth.currentSession;
});

/// `true` when a valid session exists, OR when we previously had one and
/// we're currently offline.
///
/// This is the router's authentication gate. It stays sticky while offline
/// so that a Supabase-internal token-refresh failure (which can null out
/// [Session] without a real sign-out) does not kick the user back to
/// `/login` when they can't do anything about it. When connectivity returns,
/// if the session is genuinely gone, this flips to `false` and the router
/// redirects to `/login` on the next refresh.
final isAuthenticatedProvider = Provider<bool>((ref) {
  final session = ref.watch(currentSessionProvider);
  if (session != null) return true;

  // No session. Buffer the answer while offline: only flip to unauthenticated
  // once we're online and can trust that "no session" means "really signed out".
  final connectivity = ref.watch(connectivityStatusProvider);
  final isOnline = connectivity.value ?? true;
  if (isOnline) return false;

  // Offline with no session in memory. We keep the previous verdict from the
  // sticky notifier: authenticated iff we've ever been authenticated in this
  // app instance. On a totally fresh install with no cached session and no
  // network, this will correctly stay `false`.
  return ref.watch(_wasAuthenticatedProvider);
});

/// Tracks whether we've ever observed a live session in this process. Sticky
/// once flipped to `true`; only cleared by explicit sign-out flow (see
/// [markSignedOut]).
final _wasAuthenticatedProvider =
    NotifierProvider<_WasAuthenticatedNotifier, bool>(
      _WasAuthenticatedNotifier.new,
    );

class _WasAuthenticatedNotifier extends Notifier<bool> {
  @override
  bool build() {
    // Seed from the current session, then watch for changes.
    final seeded = supabase.auth.currentSession != null;
    // Listen to auth stream to flip `true` on first sign-in.
    ref.listen<AsyncValue<AuthState>>(authStateProvider, (_, _) {
      final session = supabase.auth.currentSession;
      if (session != null && !state) state = true;
    });
    return seeded;
  }

  /// Explicit sign-out: clear the sticky flag so we route back to `/login`.
  void clear() => state = false;
}

/// Call this from the sign-out flow to reset the sticky offline-authed flag.
void markSignedOut(WidgetRef ref) {
  ref.read(_wasAuthenticatedProvider.notifier).clear();
}

/// Ref-based variant for use inside providers/services.
void markSignedOutFromRef(Ref ref) {
  ref.read(_wasAuthenticatedProvider.notifier).clear();
}
