import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/app_user.dart';
import '../providers/admin_providers.dart';

/// Admin-only screen listing all registered application users.
///
/// Read-only. Data comes from the `list_users()` SECURITY DEFINER RPC,
/// which joins `auth.users` with `public.admins` server-side.
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
            return ListView.separated(
              itemCount: users.length,
              separatorBuilder: (_, _) => const Divider(height: 0),
              itemBuilder: (context, i) => _UserTile(user: users[i]),
            );
          },
        ),
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final subtitleParts = <String>[
      'Joined ${_formatDate(user.createdAt)}',
      if (user.lastSignInAt != null)
        'Last seen ${_relative(user.lastSignInAt!)}'
      else
        'Never signed in',
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
      trailing: user.isConfirmed
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
      isThreeLine: false,
    );
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
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
            ),
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
