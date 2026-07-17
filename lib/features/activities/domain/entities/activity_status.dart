/// The lifecycle statuses a tracked activity can be in.
///
/// Deliberately simple compared to [CallingState]: activities are
/// lightweight bookkeeping tasks (temple recommend interviews, ministering
/// interviews, follow-ups) whose status is a mutable column, not an
/// append-only event stream.
///
/// Mirrors the Postgres enum `public.activity_status` — see
/// `supabase/migrations/20260718000000_tracked_activities.sql`.
enum ActivityStatus {
  pending,
  inProgress,
  completed,
  cancelled;

  /// The exact string used by Postgres (snake_case).
  String get wireName => switch (this) {
        ActivityStatus.pending => 'pending',
        ActivityStatus.inProgress => 'in_progress',
        ActivityStatus.completed => 'completed',
        ActivityStatus.cancelled => 'cancelled',
      };

  /// Human-friendly label.
  String get label => switch (this) {
        ActivityStatus.pending => 'Pending',
        ActivityStatus.inProgress => 'In progress',
        ActivityStatus.completed => 'Completed',
        ActivityStatus.cancelled => 'Cancelled',
      };

  /// `completed` and `cancelled` end the activity's life. The UI still
  /// allows moving an activity back to `pending` / `inProgress` if the user
  /// changes their mind — status is a mutable column, not an append-only
  /// log — but "terminal" here means the item drops out of the default
  /// (active-only) filters.
  bool get isTerminal =>
      this == ActivityStatus.completed || this == ActivityStatus.cancelled;

  /// Parse the Postgres wire value into an [ActivityStatus].
  ///
  /// Throws [ArgumentError] on an unrecognized value so we notice schema
  /// drift immediately rather than silently defaulting.
  static ActivityStatus fromWire(String value) {
    return switch (value) {
      'pending' => ActivityStatus.pending,
      'in_progress' => ActivityStatus.inProgress,
      'completed' => ActivityStatus.completed,
      'cancelled' => ActivityStatus.cancelled,
      _ => throw ArgumentError('Unknown activity_status: $value'),
    };
  }
}
