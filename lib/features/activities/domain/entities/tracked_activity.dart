import 'activity_kind.dart';
import 'activity_status.dart';

/// Domain model for a lightweight, generic ward activity.
///
/// Mirrors `public.tracked_activities`. Unlike a [Calling], the status here
/// is a mutable field (see [ActivityStatus]) — activities are simple tasks
/// that don't warrant an append-only history.
class TrackedActivity {
  const TrackedActivity({
    required this.id,
    required this.memberId,
    required this.title,
    required this.kind,
    required this.status,
    this.dueAt,
    this.completedAt,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// Nullable — a ward-wide activity has no single candidate.
  final String? memberId;

  final String title;
  final ActivityKind kind;
  final ActivityStatus status;
  final DateTime? dueAt;
  final DateTime? completedAt;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isOverdue {
    final due = dueAt;
    if (due == null) return false;
    if (status.isTerminal) return false;
    return due.isBefore(DateTime.now());
  }
}

/// Fields required/allowed when creating a new tracked activity.
class NewTrackedActivity {
  const NewTrackedActivity({
    this.memberId,
    required this.title,
    required this.kind,
    this.status = ActivityStatus.pending,
    this.dueAt,
    this.notes,
  });

  final String? memberId;
  final String title;
  final ActivityKind kind;
  final ActivityStatus status;
  final DateTime? dueAt;
  final String? notes;

  /// Payload for a PostgREST `insert`. `id`, `created_at`, `updated_at`,
  /// and `completed_at` are populated by the caller.
  Map<String, dynamic> toInsert() {
    final map = <String, dynamic>{
      'title': title.trim(),
      'kind': kind.wireName,
      'status': status.wireName,
    };
    if (memberId != null && memberId!.isNotEmpty) {
      map['member_id'] = memberId;
    }
    if (dueAt != null) {
      map['due_at'] = dueAt!.toUtc().toIso8601String();
    }
    final trimmedNotes = notes?.trim();
    if (trimmedNotes != null && trimmedNotes.isNotEmpty) {
      map['notes'] = trimmedNotes;
    }
    return map;
  }
}

/// Fields allowed when editing an existing activity (excluding the status
/// transition, which goes through a dedicated repository helper so
/// `completed_at` can be stamped consistently).
///
/// Every optional column is always written — an empty string becomes `null`
/// so the user can clear a value they had previously set.
class TrackedActivityUpdate {
  const TrackedActivityUpdate({
    this.memberId,
    required this.title,
    required this.kind,
    this.dueAt,
    this.clearDueAt = false,
    this.notes,
  });

  final String? memberId;
  final String title;
  final ActivityKind kind;
  final DateTime? dueAt;

  /// If true, `dueAt` is intentionally being cleared. Distinguishes
  /// "user unset the due date" from "form omitted the field".
  final bool clearDueAt;

  final String? notes;

  Map<String, dynamic> toUpdate() {
    String? nullIfBlank(String? v) {
      final t = v?.trim();
      return (t == null || t.isEmpty) ? null : t;
    }

    return <String, dynamic>{
      'member_id': (memberId != null && memberId!.isNotEmpty) ? memberId : null,
      'title': title.trim(),
      'kind': kind.wireName,
      'due_at': clearDueAt ? null : dueAt?.toUtc().toIso8601String(),
      'notes': nullIfBlank(notes),
    };
  }
}
