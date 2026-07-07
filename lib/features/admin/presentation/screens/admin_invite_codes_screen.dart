import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/invite_code.dart';
import '../providers/admin_providers.dart';

/// Admin-only screen for managing invite codes.
///
/// Lists every existing code (used and unused), lets the admin generate a
/// new random code, and revoke unused ones. All actions go through
/// SECURITY DEFINER RPCs; non-admins who somehow reach this screen will
/// get `not authorized` errors from the DB.
class AdminInviteCodesScreen extends ConsumerWidget {
  const AdminInviteCodesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final codesAsync = ref.watch(inviteCodesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Invite codes')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(inviteCodesProvider),
        child: codesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              const SizedBox(height: 120),
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Failed to load codes:\n$e',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
          data: (codes) {
            if (codes.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No invite codes yet.\nTap + to generate one.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              );
            }
            final unused =
                codes.where((c) => !c.isUsed).toList(growable: false);
            final used = codes.where((c) => c.isUsed).toList(growable: false);
            return ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                if (unused.isNotEmpty)
                  _Section(
                    title: 'Available (${unused.length})',
                    children: unused
                        .map((c) => _CodeTile(code: c, isUsed: false))
                        .toList(growable: false),
                  ),
                if (used.isNotEmpty)
                  _Section(
                    title: 'Used (${used.length})',
                    children: used
                        .map((c) => _CodeTile(code: c, isUsed: true))
                        .toList(growable: false),
                  ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _generate(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Generate'),
      ),
    );
  }

  Future<void> _generate(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final noteController = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Generate invite code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Optional note — who is this for?',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              autofocus: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'e.g. first counselor',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(noteController.text),
            child: const Text('Generate'),
          ),
        ],
      ),
    );

    noteController.dispose();
    if (note == null) return; // Cancelled.

    try {
      final code = await ref
          .read(adminRepositoryProvider)
          .createInviteCode(note: note);
      ref.invalidate(inviteCodesProvider);
      if (!context.mounted) return;
      await _showCodeDialog(context, code);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to generate: $e')),
      );
    }
  }

  Future<void> _showCodeDialog(BuildContext context, String code) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New invite code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SelectableText(
              code,
              textAlign: TextAlign.center,
              style: Theme.of(ctx).textTheme.headlineMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    letterSpacing: 2,
                  ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Share this code out-of-band. It can be used exactly once.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Copy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ),
        ...children,
        const SizedBox(height: 8),
      ],
    );
  }
}

class _CodeTile extends ConsumerWidget {
  const _CodeTile({required this.code, required this.isUsed});

  final InviteCode code;
  final bool isUsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subtitleParts = <String>[
      if (code.note != null && code.note!.isNotEmpty) code.note!,
      'Created ${_formatDate(code.createdAt)}',
      if (code.usedAt != null) 'Used ${_formatDate(code.usedAt!)}',
    ];
    return ListTile(
      title: SelectableText(
        code.code,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
              letterSpacing: 1.5,
            ),
      ),
      subtitle: Text(subtitleParts.join(' \u2022 ')),
      trailing: isUsed
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: 'Copy',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: code.code));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Code copied')),
                      );
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Revoke',
                  onPressed: () => _confirmRevoke(context, ref),
                ),
              ],
            ),
    );
  }

  Future<void> _confirmRevoke(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke this code?'),
        content: Text(
          'This will permanently delete "${code.code}". '
          'It can\u2019t be used to register after that.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref
          .read(adminRepositoryProvider)
          .revokeInviteCode(code.code);
      ref.invalidate(inviteCodesProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Code revoked')));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to revoke: $e')),
      );
    }
  }
}

String _formatDate(DateTime d) {
  final local = d.toLocal();
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}
