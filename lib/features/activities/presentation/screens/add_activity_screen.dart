import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/activity_kind.dart';
import '../../domain/entities/tracked_activity.dart';
import '../providers/tracked_activities_providers.dart';
import '../widgets/member_picker_field.dart';

/// Form to create a new tracked activity.
///
/// Mirrors the shape and interaction of [AddCallingScreen]: form key +
/// controllers + `_isSaving` guard, GoRouter/ScaffoldMessenger captured
/// before await, `mounted` check after.
class AddActivityScreen extends ConsumerStatefulWidget {
  const AddActivityScreen({super.key});

  @override
  ConsumerState<AddActivityScreen> createState() => _AddActivityScreenState();
}

class _AddActivityScreenState extends ConsumerState<AddActivityScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  ActivityKind _kind = ActivityKind.templeRecommend;
  String? _memberId;
  DateTime? _dueAt;
  bool _isSaving = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isSaving = true);
    try {
      await ref.read(trackedActivitiesRepositoryProvider).addActivity(
            NewTrackedActivity(
              memberId: _memberId,
              title: _titleCtrl.text,
              kind: _kind,
              dueAt: _dueAt,
              notes: _notesCtrl.text,
            ),
          );
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Activity added')),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add activity'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: Form(
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
                setState(() {
                  _kind = v;
                  // Autofill title when the user hasn't typed anything
                  // yet — nudge them toward a sensible default.
                  if (_titleCtrl.text.trim().isEmpty) {
                    _titleCtrl.text = v.label;
                  }
                });
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
                          onPressed: () => setState(() => _dueAt = null),
                        ),
                ),
                child: Text(
                  _dueAt == null ? 'No due date' : _formatDate(_dueAt!),
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
              onPressed: _isSaving ? null : _save,
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
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
