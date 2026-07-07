import 'package:flutter/material.dart';

import '../../features/callings/domain/entities/calling_state.dart';
import 'chapel_theme.dart';

/// Visual grouping for a [CallingState].
///
/// Different states carry different meaning — pipeline (thinking about it),
/// in service (actively serving), or ended (declined or released). The
/// palette maps each group to a different tone so the eye immediately
/// reads the health of the ward:
///
/// * **pipeline** — soft gold. Something the bishopric owes attention to.
/// * **inService** — sage green. Everything is well.
/// * **ended** — muted paper. Historical, not actionable.
enum _StateTone { pipeline, inService, ended }

_StateTone _toneFor(CallingState s) {
  switch (s) {
    case CallingState.selected:
    case CallingState.extended:
    case CallingState.accepted:
      return _StateTone.pipeline;
    case CallingState.sustained:
    case CallingState.setApart:
    case CallingState.active:
      return _StateTone.inService;
    case CallingState.declined:
    case CallingState.released:
      return _StateTone.ended;
  }
}

/// A compact chip showing the current calling state with a consistent
/// color tone across every screen (Summary, Dashboard, Member Detail,
/// Calling Detail, drill-down lists).
class StateChip extends StatelessWidget {
  const StateChip({super.key, required this.state, this.dense = false});

  final CallingState state;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final tone = _toneFor(state);
    final (bg, fg, border) = switch (tone) {
      _StateTone.pipeline => (
          ChapelPalette.goldLight,
          ChapelPalette.goldDark,
          ChapelPalette.gold,
        ),
      _StateTone.inService => (
          ChapelPalette.sageLight,
          const Color(0xFF2E4A2E),
          ChapelPalette.sage,
        ),
      _StateTone.ended => (
          ChapelPalette.paperDeep,
          ChapelPalette.inkSoft,
          ChapelPalette.rule,
        ),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : 10,
        vertical: dense ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border, width: 0.75),
      ),
      child: Text(
        state.label,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w600,
          fontSize: dense ? 10 : 11,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
