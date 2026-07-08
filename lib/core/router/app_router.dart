import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/providers/auth_state_provider.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../sync/connectivity_service.dart';
import '../../features/admin/presentation/screens/admin_invite_codes_screen.dart';
import '../../features/admin/presentation/screens/admin_users_screen.dart';
import '../../features/callings/domain/entities/calling_state.dart';
import '../../features/callings/presentation/screens/add_calling_screen.dart';
import '../../features/callings/presentation/screens/calling_detail_screen.dart';
import '../../features/callings/presentation/screens/callings_by_state_screen.dart';
import '../../features/callings/presentation/screens/edit_calling_screen.dart';
import '../../features/callings/presentation/screens/record_calling_event_screen.dart';
import '../../features/members/presentation/screens/add_member_screen.dart';
import '../../features/members/presentation/screens/edit_member_screen.dart';
import '../../features/members/presentation/screens/member_detail_screen.dart';
import '../shell/home_shell.dart';

/// Named routes.
class AppRoutes {
  const AppRoutes._();

  static const home = '/';
  static const login = '/login';
  static const adminInviteCodes = '/admin/invite-codes';
  static const adminUsers = '/admin/users';
  static const memberAdd = '/members/add';

  /// Build the detail path for a specific member.
  static String memberDetail(String id) => '/members/$id';

  /// Build the edit path for a specific member.
  static String memberEdit(String id) => '/members/$id/edit';

  /// Build the add-calling path for a specific member.
  static String callingAddFor(String memberId) =>
      '/members/$memberId/callings/add';

  /// Build the calling-detail path.
  static String callingDetail(String memberId, String callingId) =>
      '/members/$memberId/callings/$callingId';

  /// Build the edit path for a specific calling.
  static String callingEdit(String memberId, String callingId) =>
      '/members/$memberId/callings/$callingId/edit';

  /// Build the record-state path for a calling.
  static String callingRecordFor(String memberId, String callingId) =>
      '/members/$memberId/callings/$callingId/record';

  /// Build the drill-down list path for callings currently in [wireState].
  /// Accepts the Postgres wire value (e.g. `set_apart`, not `setApart`).
  static String callingsInState(String wireState) =>
      '/callings/state/$wireState';
}

/// Bridges a Riverpod provider into a [Listenable] so `go_router` can be told
/// to re-evaluate its redirect logic whenever auth or connectivity state
/// changes. Connectivity is watched too because
/// [isAuthenticatedProvider] can flip when the network returns and we can
/// finally confirm whether the session is really gone.
class _RiverpodRouterRefresh extends ChangeNotifier {
  _RiverpodRouterRefresh(Ref ref) {
    _authSub = ref.listen<AsyncValue>(
      authStateProvider,
      (_, _) => notifyListeners(),
      fireImmediately: false,
    );
    _connSub = ref.listen<AsyncValue<bool>>(
      connectivityStatusProvider,
      (_, _) => notifyListeners(),
      fireImmediately: false,
    );
  }

  late final ProviderSubscription<AsyncValue> _authSub;
  late final ProviderSubscription<AsyncValue<bool>> _connSub;

  @override
  void dispose() {
    _authSub.close();
    _connSub.close();
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
      final location = state.matchedLocation;
      final isPublic = location == AppRoutes.login;

      if (!isAuthenticated && !isPublic) return AppRoutes.login;
      if (isAuthenticated && isPublic) return AppRoutes.home;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (_, _) => const HomeShell(),
      ),
      GoRoute(
        path: AppRoutes.memberAdd,
        builder: (_, _) => const AddMemberScreen(),
      ),
      GoRoute(
        path: '/members/:id',
        builder: (_, state) =>
            MemberDetailScreen(memberId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/members/:id/edit',
        builder: (_, state) =>
            EditMemberScreen(memberId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/members/:id/callings/add',
        builder: (_, state) =>
            AddCallingScreen(memberId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/members/:memberId/callings/:callingId',
        builder: (_, state) => CallingDetailScreen(
          memberId: state.pathParameters['memberId']!,
          callingId: state.pathParameters['callingId']!,
        ),
      ),
      GoRoute(
        path: '/members/:memberId/callings/:callingId/edit',
        builder: (_, state) => EditCallingScreen(
          memberId: state.pathParameters['memberId']!,
          callingId: state.pathParameters['callingId']!,
        ),
      ),
      GoRoute(
        path: '/members/:memberId/callings/:callingId/record',
        builder: (_, state) => RecordCallingEventScreen(
          memberId: state.pathParameters['memberId']!,
          callingId: state.pathParameters['callingId']!,
        ),
      ),
      GoRoute(
        path: '/callings/state/:state',
        builder: (_, state) {
          final wire = state.pathParameters['state']!;
          return CallingsByStateScreen(
            state: CallingState.fromWire(wire),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (_, _) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminInviteCodes,
        builder: (_, _) => const AdminInviteCodesScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminUsers,
        builder: (_, _) => const AdminUsersScreen(),
      ),
    ],
  );
});
