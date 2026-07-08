import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../auth/presentation/providers/auth_repository_provider.dart';
import '../../domain/entities/app_user.dart';
import '../providers/admin_providers.dart';

/// Admin-only screen listing all registered application users, with actions
/// to promote / revoke admin, delete users, and send password-reset emails.
///
/// Data comes from the `list_users()` RPC. Mutations go through
/// `AdminRepository` and invalidate [usersProvider] on success.
///
/// Guardrails are enforced server-side by the RPCs (cannot revoke or delete
/// the last remaining admin; cannot delete self). The client also hides the
/// obviously-unavailable actions from the row's overflow menu so admins get
/// consistent feedback without a server round-trip.
class AdminUsersScreen extends ConsumerWidget {
  const AdminUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(usersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Users')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(usersProvider),
        child: usersAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              const SizedBox(height: 120),
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Failed to load users:\n$e',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
          data: (users) {
            if (users.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No users yet.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              );
            }
            final adminCount = users.where((u) => u.isAdmin).length;
            final currentUserId = supabase.auth.currentUser?.id;
            return ListView.separated(
              itemCount: users.length,
              separatorBuilder: (_, _) => const Divider(height: 0),
              itemBuilder: (context, i) => _UserTile(
                user: users[i],
                adminCount: adminCount,
                isSelf: users[i].id == currentUserId,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Menu action ids for a user row. Kept enum-shaped so the switch in
/// [_UserTile._runAction] is exhaustive.
enum _UserAction { promote, revoke, resetPassword, delete }

class _UserTile extends ConsumerWidget {
  const _UserTile({
    required this.user,
    required this.adminCount,
    required this.isSelf,
  });

  final AppUser user;

  /// Total number of admins currently in the system. Used to hide the
  /// "revoke" / "delete" actions when they would leave zero admins.
  final int adminCount;

  /// True when this row is the currently-signed-in user. Disables the
  /// "delete" action; still allows the user to send themselves a
  /// password-reset (harmless).
  final bool isSelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final subtitleParts = <String>[
      'Joined ${_formatDate(user.createdAt)}',
      if (user.lastSignInAt != null)
        'Last seen ${_relative(user.lastSignInAt!)}'
      else
        'Never signed in',
    ];

    // Determine which actions are available for this user.
    final wouldDropLastAdmin = user.isAdmin && adminCount <= 1;
    final actions = <_UserAction>[
      if (!user.isAdmin) _UserAction.promote,
      if (user.isAdmin && !wouldDropLastAdmin) _UserAction.revoke,
      if (user.email.isNotEmpty) _UserAction.resetPassword,
      if (!isSelf && !wouldDropLastAdmin) _UserAction.delete,
    ];

    return ListTile(
      title: Row(
        children: [
          Expanded(
            child: Text(
              user.email.isEmpty ? '(no email)' : user.email,
              style: theme.textTheme.bodyLarge,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (user.isAdmin) ...[
            const SizedBox(width: 8),
            _Chip(
              label: 'Admin',
              foreground: scheme.onPrimaryContainer,
              background: scheme.primaryContainer,
            ),
          ],
        ],
      ),
      subtitle: Text(subtitleParts.join(' • ')),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          user.isConfirmed
              ? _Chip(
                  label: 'Confirmed',
                  foreground: scheme.onSecondaryContainer,
                  background: scheme.secondaryContainer,
                )
              : _Chip(
                  label: 'Pending',
                  foreground: scheme.onErrorContainer,
                  background: scheme.errorContainer,
                ),
          if (actions.isNotEmpty)
            PopupMenuButton<_UserAction>(
              tooltip: 'Actions',
              onSelected: (action) => _runAction(context, ref, action),
              itemBuilder: (context) => [
                for (final a in actions)
                  PopupMenuItem<_UserAction>(
                    value: a,
                    child: Row(
                      children: [
                        Icon(_iconFor(a), size: 20),
                        const SizedBox(width: 12),
                        Text(_labelFor(a)),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
      isThreeLine: false,
    );
  }

  IconData _iconFor(_UserAction a) => switch (a) {
    _UserAction.promote => Icons.shield_outlined,
    _UserAction.revoke => Icons.shield_moon_outlined,
    _UserAction.resetPassword => Icons.lock_reset_outlined,
    _UserAction.delete => Icons.delete_outline,
  };

  String _labelFor(_UserAction a) => switch (a) {
    _UserAction.promote => 'Promote to admin',
    _UserAction.revoke => 'Revoke admin',
    _UserAction.resetPassword => 'Send password reset',
    _UserAction.delete => 'Delete user…',
  };

  Future<void> _runAction(
    BuildContext context,
    WidgetRef ref,
    _UserAction action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final adminRepo = ref.read(adminRepositoryProvider);
    final authRepo = ref.read(authRepositoryProvider);

    switch (action) {
      case _UserAction.promote:
        try {
          await adminRepo.grantAdmin(user.id);
          ref.invalidate(usersProvider);
          messenger.showSnackBar(
            SnackBar(content: Text('Promoted ${user.email} to admin.')),
          );
        } catch (e) {
          messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
        }
        break;

      case _UserAction.revoke:
        final confirmed = await _confirm(
          context,
          title: 'Revoke admin?',
          message: 'Remove admin rights from ${user.email}?',
          destructive: false,
          confirmLabel: 'Revoke',
        );
        if (!confirmed) return;
        try {
          await adminRepo.revokeAdmin(user.id);
          ref.invalidate(usersProvider);
          messenger.showSnackBar(
            SnackBar(content: Text('Revoked admin from ${user.email}.')),
          );
        } catch (e) {
          messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
        }
        break;

      case _UserAction.resetPassword:
        try {
          await authRepo.sendPasswordResetEmail(user.email);
          messenger.showSnackBar(
            SnackBar(
              content: Text('Password-reset email sent to ${user.email}.'),
            ),
          );
        } catch (e) {
          messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
        }
        break;

      case _UserAction.delete:
        final confirmed = await _confirm(
          context,
          title: 'Delete user?',
          message:
              'This permanently removes ${user.email} from the app. Their '
              'recorded actions stay in the log, but they will no longer '
              'be able to sign in. This cannot be undone.',
          destructive: true,
          confirmLabel: 'Delete',
        );
        if (!confirmed) return;
        try {
          await adminRepo.deleteUser(user.id);
          ref.invalidate(usersProvider);
          messenger.showSnackBar(
            SnackBar(content: Text('Deleted ${user.email}.')),
          );
        } catch (e) {
          messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
        }
        break;
    }
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required bool destructive,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error,
                    foregroundColor: Theme.of(ctx).colorScheme.onError,
                  )
                : null,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.foreground,
    required this.background,
  });

  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: foreground),
      ),
    );
  }
}

String _formatDate(DateTime d) {
  final local = d.toLocal();
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

/// Loose "n days ago" style timestamp for last-sign-in. Anything within
/// the last minute rounds to "just now"; days beyond ~30 collapse to a
/// full date so the labels stay short.
String _relative(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) {
    return '${diff.inMinutes} min ago';
  }
  if (diff.inHours < 24) {
    return '${diff.inHours} h ago';
  }
  if (diff.inDays < 30) {
    return '${diff.inDays} d ago';
  }
  return _formatDate(d);
}
