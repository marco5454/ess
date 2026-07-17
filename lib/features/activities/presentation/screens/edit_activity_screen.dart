import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/activity_kind.dart';
import '../../domain/entities/tracked_activity.dart';
import '../providers/tracked_activities_providers.dart';
import '../widgets/member_picker_field.dart';

/// Form to edit an existing tracked activity.
///
/// Status is NOT edited here — that goes through the inline picker on the
/// detail screen so we can consistently stamp `completed_at`.
class EditActivityScreen extends ConsumerStatefulWidget {
  const EditActivityScreen({super.key, required this.activityId});

  final String activityId;

  @override
  ConsumerState<EditActivityScreen> createState() =>
      _EditActivityScreenState();
}

class _EditActivityScreenState extends ConsumerState<EditActivityScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  ActivityKind _kind = ActivityKind.other;
  String? _memberId;
  DateTime? _dueAt;
  bool _initialized = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _hydrateOnce(TrackedActivity a) {
    if (_initialized) return;
    _initialized = true;
    _titleCtrl.text = a.title;
    _notesCtrl.text = a.notes ?? '';
    _kind = a.kind;
    _memberId = a.memberId;
    _dueAt = a.dueAt;
  }

  Future<void> _save(TrackedActivity original) async {
    if (!_formKey.currentState!.validate()) return;
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isSaving = true);
    try {
      // If the original had a due date and the user cleared it, use
      // `clearDueAt` so the repository sends an explicit null.
      final clear = original.dueAt != null && _dueAt == null;
      await ref.read(trackedActivitiesRepositoryProvider).updateActivity(
            widget.activityId,
            TrackedActivityUpdate(
              memberId: _memberId,
              title: _titleCtrl.text,
              kind: _kind,
              dueAt: _dueAt,
              clearDueAt: clear,
              notes: _notesCtrl.text,
            ),
          );
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Changes saved')),
      );
      router.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to save: $e')),
      );
    }
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final initial = _dueAt ?? now;
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      initialDate: initial,
    );
    if (picked == null) return;
    setState(() {
      _dueAt = DateTime(picked.year, picked.month, picked.day);
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(activityByIdProvider(widget.activityId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit activity'),
        actions: [
          async.maybeWhen(
            data: (a) => TextButton(
              onPressed: _isSaving ? null : () => _save(a),
              child: const Text('Save'),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (a) {
          _hydrateOnce(a);
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<ActivityKind>(
                  initialValue: _kind,
                  decoration: const InputDecoration(labelText: 'Type *'),
                  items: [
                    for (final k in ActivityKind.values)
                      DropdownMenuItem(
                        value: k,
                        child: Row(
                          children: [
                            Icon(k.icon, size: 18),
                            const SizedBox(width: 8),
                            Text(k.label),
                          ],
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _kind = v);
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(labelText: 'Title *'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                MemberPickerField(
                  selectedMemberId: _memberId,
                  onChanged: (id) => setState(() => _memberId = id),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: _pickDueDate,
                  borderRadius: BorderRadius.circular(4),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Due date',
                      suffixIcon: _dueAt == null
                          ? const Icon(Icons.calendar_today_outlined)
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              tooltip: 'Clear',
                              onPressed: () =>
                                  setState(() => _dueAt = null),
                            ),
                    ),
                    child: Text(
                      _dueAt == null
                          ? 'No due date'
                          : _formatDate(_dueAt!),
                      style: TextStyle(
                        color: _dueAt == null
                            ? Theme.of(context).hintColor
                            : null,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _notesCtrl,
                  decoration: const InputDecoration(labelText: 'Notes'),
                  maxLines: 4,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _isSaving ? null : () => _save(a),
                  child: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
