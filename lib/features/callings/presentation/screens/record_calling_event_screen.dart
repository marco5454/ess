import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/calling_state.dart';
import '../providers/callings_providers.dart';

/// Form for appending a new state event to a calling's history.
///
/// The set of choices is constrained to states legal from the current one
/// (see [CallingState.allowedNextStates]). occurred_at defaults to "now" but
/// can be edited. Notes are optional.
class RecordCallingEventScreen extends ConsumerStatefulWidget {
  const RecordCallingEventScreen({
    super.key,
    required this.memberId,
    required this.callingId,
  });

  final String memberId;
  final String callingId;

  @override
  ConsumerState<RecordCallingEventScreen> createState() =>
      _RecordCallingEventScreenState();
}

class _RecordCallingEventScreenState
    extends ConsumerState<RecordCallingEventScreen> {
  final _formKey = GlobalKey<FormState>();
  final _notes = TextEditingController();

  CallingState? _selectedState;
  DateTime _occurredAt = DateTime.now();
  bool _isSaving = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1),
      initialDate: _occurredAt,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_occurredAt),
    );
    if (time == null) return;
    setState(() {
      _occurredAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (_selectedState == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a state to record')),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(callingsRepositoryProvider);

    try {
      await repo.addEvent(
        callingId: widget.callingId,
        state: _selectedState!,
        occurredAt: _occurredAt,
        notes: _notes.text,
      );
      // Refresh both the calling's own event list and the member's list of
      // callings (so the state chip on the parent screens updates).
      ref.invalidate(eventsForCallingProvider(widget.callingId));
      ref.invalidate(callingsForMemberProvider(widget.memberId));
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('State recorded')));
      router.pop();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(eventsForCallingProvider(widget.callingId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Record state'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: SafeArea(
        child: eventsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Failed to load current state:\n$e'),
          ),
          data: (events) {
            final current = events.isEmpty ? null : events.first.state;
            final allowed =
                current?.allowedNextStates ?? const <CallingState>[];

            if (current != null && current.isTerminal) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'This calling is in a terminal state (${current.label}).\n'
                    'No further transitions are allowed.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            return Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (current != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Current: ${current.label}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  Text('New state',
                      style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in allowed)
                        ChoiceChip(
                          label: Text(s.label),
                          selected: _selectedState == s,
                          onSelected: (sel) =>
                              setState(() => _selectedState = sel ? s : null),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Occurred at',
                      border: OutlineInputBorder(),
                    ),
                    child: Row(
                      children: [
                        Expanded(child: Text(_fmt(_occurredAt))),
                        TextButton.icon(
                          onPressed: _pickDateTime,
                          icon: const Icon(Icons.edit),
                          label: const Text('Change'),
                        ),
                      ],
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
            );
          },
        ),
      ),
    );
  }

  static String _fmt(DateTime d) {
    final date = '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    final time = '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
    return '$date $time';
  }
}
