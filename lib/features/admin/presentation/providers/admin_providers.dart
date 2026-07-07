import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../auth/presentation/providers/auth_state_provider.dart';
import '../../data/repositories/admin_repository.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/entities/invite_code.dart';

/// Provides the singleton [AdminRepository].
final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return AdminRepository(supabase);
});

/// Whether the currently-signed-in user is an admin.
///
/// Recomputed whenever the auth state changes (sign in / sign out). Backed
/// by the `is_admin` RPC. Non-admins get `false` — the underlying RPC is
/// callable by any authenticated user and simply returns false for
/// non-members.
final isAdminProvider = FutureProvider<bool>((ref) async {
  // Rebuild when the auth session changes.
  ref.watch(authStateProvider);
  final session = ref.watch(currentSessionProvider);
  if (session == null) return false;
  final repo = ref.watch(adminRepositoryProvider);
  return repo.isAdmin();
});

/// The list of all invite codes, newest first. Admin-only.
final inviteCodesProvider = FutureProvider<List<InviteCode>>((ref) async {
  final repo = ref.watch(adminRepositoryProvider);
  return repo.listInviteCodes();
});

/// The list of all registered users, newest first. Admin-only.
final usersProvider = FutureProvider<List<AppUser>>((ref) async {
  final repo = ref.watch(adminRepositoryProvider);
  return repo.listUsers();
});
