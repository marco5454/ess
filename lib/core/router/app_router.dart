import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/providers/auth_state_provider.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/members/presentation/screens/add_member_screen.dart';
import '../../features/members/presentation/screens/members_list_screen.dart';

/// Named routes.
class AppRoutes {
  const AppRoutes._();

  static const home = '/';
  static const login = '/login';
  static const memberAdd = '/members/add';
}

/// Bridges a Riverpod provider into a [Listenable] so `go_router` can be told
/// to re-evaluate its redirect logic whenever auth state changes.
class _RiverpodRouterRefresh extends ChangeNotifier {
  _RiverpodRouterRefresh(Ref ref) {
    _sub = ref.listen<AsyncValue>(
      authStateProvider,
      (_, _) => notifyListeners(),
      fireImmediately: false,
    );
  }

  late final ProviderSubscription<AsyncValue> _sub;

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}

/// The application router.
///
/// Guards routes based on Supabase auth state: unauthenticated users are
/// redirected to [AppRoutes.login]; authenticated users hitting [AppRoutes.login]
/// are bounced to [AppRoutes.home].
final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _RiverpodRouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: AppRoutes.home,
    refreshListenable: refresh,
    redirect: (context, state) {
      final isAuthenticated = ref.read(isAuthenticatedProvider);
      final goingToLogin = state.matchedLocation == AppRoutes.login;

      if (!isAuthenticated && !goingToLogin) return AppRoutes.login;
      if (isAuthenticated && goingToLogin) return AppRoutes.home;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (_, _) => const MembersListScreen(),
      ),
      GoRoute(
        path: AppRoutes.memberAdd,
        builder: (_, _) => const AddMemberScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (_, _) => const LoginScreen(),
      ),
    ],
  );
});
