import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/calling.dart';
import '../providers/callings_providers.dart';

/// Form for creating a new calling for a given member.
///
/// Only [title] is required. On save, the repository also inserts the
/// initial `selected` event on `calling_events`.
class AddCallingScreen extends ConsumerStatefulWidget {
  const AddCallingScreen({super.key, required this.memberId});

  final String memberId;

  @override
  ConsumerState<AddCallingScreen> createState() => _AddCallingScreenState();
}

class _AddCallingScreenState extends ConsumerState<AddCallingScreen> {
  final _formKey = GlobalKey<FormState>();

  final _title = TextEditingController();
  final _organization = TextEditingController();
  final _notes = TextEditingController();

  bool _isSaving = false;

  @override
  void dispose() {
    _title.dispose();
    _organization.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(callingsRepositoryProvider);

    try {
      await repo.addCalling(NewCalling(
        memberId: widget.memberId,
        title: _title.text,
        organization: _organization.text,
        notes: _notes.text,
      ));
      ref.invalidate(callingsForMemberProvider(widget.memberId));
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Calling added')));
      router.pop();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Failed to add: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add calling'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
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
              TextFormField(
                controller: _organization,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Organization',
                  hintText: 'e.g. Elders Quorum, Primary, Ward',
                ),
              ),
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
                    : const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
