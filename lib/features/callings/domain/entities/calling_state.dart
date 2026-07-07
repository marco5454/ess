/// The eight states a calling can be in.
///
/// Order matches the typical lifecycle. Mirrors the Postgres enum
/// `public.calling_state` (see `docs/phase-2-schema.md`).
enum CallingState {
  selected,
  extended,
  accepted,
  declined,
  sustained,
  setApart,
  active,
  released;

  /// The exact string used by Postgres (snake_case).
  String get wireName => switch (this) {
        CallingState.selected => 'selected',
        CallingState.extended => 'extended',
        CallingState.accepted => 'accepted',
        CallingState.declined => 'declined',
        CallingState.sustained => 'sustained',
        CallingState.setApart => 'set_apart',
        CallingState.active => 'active',
        CallingState.released => 'released',
      };

  /// Human-friendly label.
  String get label => switch (this) {
        CallingState.selected => 'Selected',
        CallingState.extended => 'Extended',
        CallingState.accepted => 'Accepted',
        CallingState.declined => 'Declined',
        CallingState.sustained => 'Sustained',
        CallingState.setApart => 'Set apart',
        CallingState.active => 'Active',
        CallingState.released => 'Released',
      };

  /// `declined` and `released` end a calling's life. No further transitions.
  bool get isTerminal =>
      this == CallingState.declined || this == CallingState.released;

  /// Parse the Postgres wire value into a [CallingState].
  ///
  /// Throws [ArgumentError] on an unrecognized value so we notice schema
  /// drift immediately rather than silently defaulting.
  static CallingState fromWire(String value) {
    return switch (value) {
      'selected' => CallingState.selected,
      'extended' => CallingState.extended,
      'accepted' => CallingState.accepted,
      'declined' => CallingState.declined,
      'sustained' => CallingState.sustained,
      'set_apart' => CallingState.setApart,
      'active' => CallingState.active,
      'released' => CallingState.released,
      _ => throw ArgumentError('Unknown calling_state: $value'),
    };
  }
}
