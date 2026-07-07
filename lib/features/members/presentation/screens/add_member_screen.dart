import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/member.dart';
import '../providers/members_providers.dart';

/// Form for adding a new member.
///
/// Required fields: first name, last name. All other fields are optional and
/// mirror the columns modeled in Phase 2.
class AddMemberScreen extends ConsumerStatefulWidget {
  const AddMemberScreen({super.key});

  @override
  ConsumerState<AddMemberScreen> createState() => _AddMemberScreenState();
}

class _AddMemberScreenState extends ConsumerState<AddMemberScreen> {
  final _formKey = GlobalKey<FormState>();

  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _preferredName = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _notes = TextEditingController();

  DateTime? _dateOfBirth;
  String? _sex;
  String? _priesthoodOffice;

  bool _isSaving = false;

  // Values mirror those documented in docs/phase-2-schema.md. UI constrains;
  // the DB accepts free-form text.
  static const _sexOptions = <String>['female', 'male'];
  static const _priesthoodOptions = <String>[
    'none',
    'deacon',
    'teacher',
    'priest',
    'elder',
    'high_priest',
  ];

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _preferredName.dispose();
    _phone.dispose();
    _email.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 20, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) {
      setState(() => _dateOfBirth = picked);
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSaving = true);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    final input = NewMember(
      firstName: _firstName.text,
      lastName: _lastName.text,
      preferredName: _preferredName.text,
      phone: _phone.text,
      email: _email.text,
      notes: _notes.text,
      dateOfBirth: _dateOfBirth,
      sex: _sex,
      priesthoodOffice: _priesthoodOffice,
    );

    try {
      final repo = ref.read(membersRepositoryProvider);
      await repo.addMember(input);
      ref.invalidate(activeMembersProvider);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Member added')));
      router.pop();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Failed to add: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add member'),
        actions: [
          TextButton(
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
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _firstName,
                enabled: !_isSaving,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'First name *',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _lastName,
                enabled: !_isSaving,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Last name *',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _preferredName,
                enabled: !_isSaving,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Preferred name',
                  helperText: 'Optional — e.g. "Jim" for James',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                enabled: !_isSaving,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                enabled: !_isSaving,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date of birth',
                  border: OutlineInputBorder(),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _dateOfBirth == null
                            ? 'Not set'
                            : _formatDate(_dateOfBirth!),
                      ),
                    ),
                    if (_dateOfBirth != null)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'Clear',
                        onPressed: _isSaving
                            ? null
                            : () => setState(() => _dateOfBirth = null),
                      ),
                    TextButton(
                      onPressed: _isSaving ? null : _pickDateOfBirth,
                      child: const Text('Pick'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _sex,
                decoration: const InputDecoration(
                  labelText: 'Sex',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('—'),
                  ),
                  ..._sexOptions.map(
                    (v) => DropdownMenuItem<String>(value: v, child: Text(v)),
                  ),
                ],
                onChanged:
                    _isSaving ? null : (v) => setState(() => _sex = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _priesthoodOffice,
                decoration: const InputDecoration(
                  labelText: 'Priesthood office',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('—'),
                  ),
                  ..._priesthoodOptions.map(
                    (v) => DropdownMenuItem<String>(value: v, child: Text(v)),
                  ),
                ],
                onChanged: _isSaving
                    ? null
                    : (v) => setState(() => _priesthoodOffice = v),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                enabled: !_isSaving,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
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
                    : const Text('Save member'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
