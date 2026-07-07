import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';

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

/// `true` when a valid session exists.
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(currentSessionProvider) != null;
});
