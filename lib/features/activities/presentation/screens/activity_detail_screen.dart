import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/chapel_theme.dart';
import '../../../members/presentation/providers/members_providers.dart';
import '../../domain/entities/activity_status.dart';
import '../../domain/entities/tracked_activity.dart';
import '../providers/tracked_activities_providers.dart';
import '../widgets/activity_status_chip.dart';

/// Read-only detail for a tracked activity, with an inline status picker
/// (segmented control of `ActivityStatus.values`) and edit/delete actions.
class ActivityDetailScreen extends ConsumerWidget {
  const ActivityDetailScreen({super.key, required this.activityId});

  final String activityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(activityByIdProvider(activityId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity'),
        actions: [
          async.maybeWhen(
            data: (_) => IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () =>
                  context.push(AppRoutes.activityEdit(activityId)),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          async.maybeWhen(
            data: (_) => IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDelete(context, ref),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (a) => _Body(activity: a),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete activity?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.onErrorContainer,
              backgroundColor: Theme.of(ctx).colorScheme.errorContainer,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(trackedActivitiesRepositoryProvider)
          .deleteActivity(activityId);
      if (!router.canPop()) return;
      router.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Activity deleted')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to delete: $e')),
      );
    }
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.activity});

  final TrackedActivity activity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberAsync = activity.memberId == null
        ? null
        : ref.watch(memberByIdProvider(activity.memberId!));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Icon(activity.kind.icon, size: 28, color: ChapelPalette.inkSoft),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activity.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    activity.kind.label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: ChapelPalette.inkSoft,
                        ),
                  ),
                ],
              ),
            ),
            ActivityStatusChip(status: activity.status),
          ],
        ),
        const SizedBox(height: 24),
        _SectionLabel('Status'),
        const SizedBox(height: 8),
        _StatusPicker(activity: activity),
        const SizedBox(height: 24),
        _SectionLabel('Details'),
        const SizedBox(height: 8),
        _DetailRow(
          icon: Icons.person_outline,
          label: 'Assigned to',
          value: activity.memberId == null
              ? 'None (ward-wide)'
              : (memberAsync?.maybeWhen(
                    data: (m) => m.displayName,
                    orElse: () => 'Loading…',
                  ) ??
                  'Loading…'),
        ),
        _DetailRow(
          icon: Icons.event_outlined,
          label: 'Due date',
          value:
              activity.dueAt == null ? 'None' : _formatDate(activity.dueAt!),
          valueColor: activity.isOverdue
              ? Theme.of(context).colorScheme.error
              : null,
        ),
        if (activity.completedAt != null)
          _DetailRow(
            icon: Icons.check_circle_outline,
            label: 'Completed',
            value: _formatDateTime(activity.completedAt!),
          ),
        _DetailRow(
          icon: Icons.schedule,
          label: 'Created',
          value: _formatDateTime(activity.createdAt),
        ),
        if (activity.notes != null && activity.notes!.trim().isNotEmpty) ...[
          const SizedBox(height: 16),
          _SectionLabel('Notes'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ChapelPalette.paperDeep,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: ChapelPalette.rule),
            ),
            child: Text(activity.notes!),
          ),
        ],
      ],
    );
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${_formatDate(dt)} $hh:$mm';
  }
}

class _StatusPicker extends ConsumerStatefulWidget {
  const _StatusPicker({required this.activity});
  final TrackedActivity activity;

  @override
  ConsumerState<_StatusPicker> createState() => _StatusPickerState();
}

class _StatusPickerState extends ConsumerState<_StatusPicker> {
  bool _busy = false;

  Future<void> _select(ActivityStatus next) async {
    if (next == widget.activity.status) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref
          .read(trackedActivitiesRepositoryProvider)
          .updateStatus(widget.activity.id, next);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to update status: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in ActivityStatus.values)
          ChoiceChip(
            label: Text(s.label),
            selected: widget.activity.status == s,
            onSelected: _busy ? null : (_) => _select(s),
          ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            letterSpacing: 1.2,
            color: ChapelPalette.inkSoft,
          ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: ChapelPalette.inkSoft),
          const SizedBox(width: 12),
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ChapelPalette.inkSoft,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}
