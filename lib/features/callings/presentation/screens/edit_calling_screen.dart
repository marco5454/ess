import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/calling.dart';
import '../providers/callings_providers.dart';
import '../widgets/organization_field.dart';

/// Form for editing an existing calling's descriptive fields.
///
/// State (via `calling_events`) is deliberately not touched here — that
/// lives on the record-state flow. Only title/organization/notes are
/// editable; reassignment to another member is not supported in this slice.
class EditCallingScreen extends ConsumerStatefulWidget {
  const EditCallingScreen({
    super.key,
    required this.memberId,
    required this.callingId,
  });

  final String memberId;
  final String callingId;

  @override
  ConsumerState<EditCallingScreen> createState() => _EditCallingScreenState();
}

class _EditCallingScreenState extends ConsumerState<EditCallingScreen> {
  final _formKey = GlobalKey<FormState>();

  final _title = TextEditingController();
  final _organization = TextEditingController();
  final _notes = TextEditingController();

  bool _initialized = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _title.dispose();
    _organization.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _populate(Calling calling) {
    _title.text = calling.title;
    _organization.text = calling.organization ?? '';
    _notes.text = calling.notes ?? '';
    _initialized = true;
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(callingsRepositoryProvider);

    try {
      await repo.updateCalling(
        widget.callingId,
        CallingUpdate(
          title: _title.text,
          organization: _organization.text,
          notes: _notes.text,
        ),
      );
      ref.invalidate(callingByIdProvider(widget.callingId));
      ref.invalidate(callingsForMemberProvider(widget.memberId));
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Calling updated')));
      router.pop();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Failed to update: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final callingAsync = ref.watch(callingByIdProvider(widget.callingId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit calling'),
        actions: [
          TextButton(
            onPressed: (_isSaving || !_initialized) ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: SafeArea(
        child: callingAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: Text('Failed to load calling:\n$e')),
          ),
          data: (calling) {
            if (!_initialized) _populate(calling);
            return Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _title,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Title *',
                      hintText: 'e.g. Elders Quorum President',
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  OrganizationField(controller: _organization),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _notes,
                    decoration: const InputDecoration(labelText: 'Notes'),
                    minLines: 2,
                    maxLines: 5,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save changes'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
