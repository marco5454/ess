import 'calling.dart';
import 'calling_state.dart';

/// A single append-only entry in a calling's lifecycle.
///
/// Mirrors `public.calling_events`. Together, the events for a calling form
/// its history; the most recent one (by `occurred_at`, tie-broken by
/// `created_at`) represents the current state.
class CallingEvent {
  const CallingEvent({
    required this.id,
    required this.callingId,
    required this.state,
    required this.occurredAt,
    this.notes,
    this.recordedBy,
    required this.createdAt,
  });

  final String id;
  final String callingId;
  final CallingState state;
  final DateTime occurredAt;
  final String? notes;
  final String? recordedBy;
  final DateTime createdAt;

  factory CallingEvent.fromMap(Map<String, dynamic> map) {
    return CallingEvent(
      id: map['id'] as String,
      callingId: map['calling_id'] as String,
      state: CallingState.fromWire(map['state'] as String),
      occurredAt: DateTime.parse(map['occurred_at'] as String),
      notes: map['notes'] as String?,
      recordedBy: map['recorded_by'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

/// A calling paired with its most recent event, for list rendering.
///
/// [latestEvent] is nullable only to be defensive; every calling gets a
/// `selected` event at creation time via `CallingsRepository.addCalling`.
class CallingWithLatestEvent {
  const CallingWithLatestEvent({required this.calling, this.latestEvent});

  final Calling calling;
  final CallingEvent? latestEvent;
}
