import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/providers/auth_state_provider.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/admin/presentation/screens/admin_invite_codes_screen.dart';
import '../../features/admin/presentation/screens/admin_users_screen.dart';
import '../../features/callings/domain/entities/calling_state.dart';
import '../../features/callings/presentation/screens/add_calling_screen.dart';
import '../../features/callings/presentation/screens/calling_detail_screen.dart';
import '../../features/callings/presentation/screens/callings_by_state_screen.dart';
import '../../features/callings/presentation/screens/edit_calling_screen.dart';
import '../../features/callings/presentation/screens/record_calling_event_screen.dart';
import '../../features/legal/presentation/screens/about_screen.dart';
import '../../features/members/presentation/screens/add_member_screen.dart';
import '../../features/members/presentation/screens/edit_member_screen.dart';
import '../../features/members/presentation/screens/member_detail_screen.dart';
import '../motion/motion.dart';
import '../shell/home_shell.dart';

/// Standard push-style transition: cross-fade + a short slide from the
/// right. Used for detail / secondary screens.
CustomTransitionPage<T> _slidePage<T>({
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: MotionDurations.medium,
    reverseTransitionDuration: MotionDurations.medium,
    transitionsBuilder: (context, animation, secondary, child) {
      final fade = CurvedAnimation(
        parent: animation,
        curve: MotionCurves.enter,
        reverseCurve: MotionCurves.exit,
      );
      final slide = Tween<Offset>(
        begin: const Offset(0.08, 0),
        end: Offset.zero,
      ).animate(fade);
      return FadeTransition(
        opacity: fade,
        child: SlideTransition(position: slide, child: child),
      );
    },
  );
}

/// Root-surface transition: pure cross-fade with a subtle scale-in. Used
/// for the login screen and home shell — no directional metaphor because
/// there is no "back stack" to imply.
CustomTransitionPage<T> _rootPage<T>({
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: MotionDurations.medium,
    reverseTransitionDuration: MotionDurations.medium,
    transitionsBuilder: (context, animation, secondary, child) {
      final fade = CurvedAnimation(
        parent: animation,
        curve: MotionCurves.enter,
        reverseCurve: MotionCurves.exit,
      );
      final scale = Tween<double>(begin: 0.98, end: 1.0).animate(fade);
      return FadeTransition(
        opacity: fade,
        child: ScaleTransition(scale: scale, child: child),
      );
    },
  );
}

/// Named routes.
class AppRoutes {
  const AppRoutes._();

  static const home = '/';
  static const login = '/login';
  static const about = '/about';
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
/// to re-evaluate its redirect logic whenever the authentication verdict
/// changes.
///
/// We listen directly to [isAuthenticatedProvider] (the exact value the
/// redirect reads) rather than to the upstream Supabase stream. Listening to
/// the derived provider guarantees the notification fires *after* Riverpod
/// has propagated invalidation through the dependency graph — otherwise the
/// router could re-run its redirect on the raw stream event and still read
/// the stale (pre-invalidation) value.
class _RiverpodRouterRefresh extends ChangeNotifier {
  _RiverpodRouterRefresh(Ref ref) {
    _authedSub = ref.listen<bool>(
      isAuthenticatedProvider,
      (_, _) => notifyListeners(),
      fireImmediately: false,
    );
  }

  late final ProviderSubscription<bool> _authedSub;

  @override
  void dispose() {
    _authedSub.close();
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
      // Public routes are reachable whether or not the user is signed in.
      // `/about` is public so the disclaimer / legal notice is readable
      // from the login screen.
      final isPublic =
          location == AppRoutes.login || location == AppRoutes.about;

      if (!isAuthenticated && !isPublic) return AppRoutes.login;
      if (isAuthenticated && location == AppRoutes.login) {
        return AppRoutes.home;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.home,
        pageBuilder: (_, state) =>
            _rootPage(state: state, child: const HomeShell()),
      ),
      GoRoute(
        path: AppRoutes.memberAdd,
        pageBuilder: (_, state) =>
            _slidePage(state: state, child: const AddMemberScreen()),
      ),
      GoRoute(
        path: '/members/:id',
        pageBuilder: (_, state) => _slidePage(
          state: state,
          child: MemberDetailScreen(memberId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/members/:id/edit',
        pageBuilder: (_, state) => _slidePage(
          state: state,
          child: EditMemberScreen(memberId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/members/:id/callings/add',
        pageBuilder: (_, state) => _slidePage(
          state: state,
          child: AddCallingScreen(memberId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/members/:memberId/callings/:callingId',
        pageBuilder: (_, state) => _slidePage(
          state: state,
          child: CallingDetailScreen(
            memberId: state.pathParameters['memberId']!,
            callingId: state.pathParameters['callingId']!,
          ),
        ),
      ),
      GoRoute(
        path: '/members/:memberId/callings/:callingId/edit',
        pageBuilder: (_, state) => _slidePage(
          state: state,
          child: EditCallingScreen(
            memberId: state.pathParameters['memberId']!,
            callingId: state.pathParameters['callingId']!,
          ),
        ),
      ),
      GoRoute(
        path: '/members/:memberId/callings/:callingId/record',
        pageBuilder: (_, state) => _slidePage(
          state: state,
          child: RecordCallingEventScreen(
            memberId: state.pathParameters['memberId']!,
            callingId: state.pathParameters['callingId']!,
          ),
        ),
      ),
      GoRoute(
        path: '/callings/state/:state',
        pageBuilder: (_, state) {
          final wire = state.pathParameters['state']!;
          return _slidePage(
            state: state,
            child: CallingsByStateScreen(state: CallingState.fromWire(wire)),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.login,
        pageBuilder: (_, state) =>
            _rootPage(state: state, child: const LoginScreen()),
      ),
      GoRoute(
        path: AppRoutes.about,
        pageBuilder: (_, state) =>
            _slidePage(state: state, child: const AboutScreen()),
      ),
      GoRoute(
        path: AppRoutes.adminInviteCodes,
        pageBuilder: (_, state) =>
            _slidePage(state: state, child: const AdminInviteCodesScreen()),
      ),
      GoRoute(
        path: AppRoutes.adminUsers,
        pageBuilder: (_, state) =>
            _slidePage(state: state, child: const AdminUsersScreen()),
      ),
    ],
  );
});
