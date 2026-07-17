import 'package:flutter/material.dart';

import '../../../../core/theme/chapel_theme.dart';
import '../../domain/entities/activity_status.dart';

/// Compact colored pill for [ActivityStatus].
///
/// Distinct-but-related look to [StateChip] used for callings. Uses the
/// existing [ChapelPalette] tones so we don't invent new colors.
class ActivityStatusChip extends StatelessWidget {
  const ActivityStatusChip({
    super.key,
    required this.status,
    this.dense = false,
  });

  final ActivityStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final tone = _toneFor(status);
    final vertical = dense ? 2.0 : 4.0;
    final horizontal = dense ? 8.0 : 10.0;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical),
      decoration: BoxDecoration(
        color: tone.background,
        border: Border.all(color: tone.border, width: 0.6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: dense ? 11 : 12,
          fontWeight: FontWeight.w600,
          color: tone.foreground,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  _Tone _toneFor(ActivityStatus status) {
    switch (status) {
      case ActivityStatus.pending:
        // Neutral / paper: waiting to be picked up.
        return const _Tone(
          background: ChapelPalette.paperDeep,
          border: ChapelPalette.rule,
          foreground: ChapelPalette.inkSoft,
        );
      case ActivityStatus.inProgress:
        // Gold / warm: active work.
        return const _Tone(
          background: ChapelPalette.goldLight,
          border: ChapelPalette.gold,
          foreground: ChapelPalette.goldDark,
        );
      case ActivityStatus.completed:
        // Sage / calm: done.
        return const _Tone(
          background: ChapelPalette.sageLight,
          border: ChapelPalette.sage,
          foreground: ChapelPalette.sage,
        );
      case ActivityStatus.cancelled:
        // Muted paper: closed but not done.
        return const _Tone(
          background: ChapelPalette.paperDeep,
          border: ChapelPalette.rule,
          foreground: ChapelPalette.inkSoft,
        );
    }
  }
}

class _Tone {
  const _Tone({
    required this.background,
    required this.border,
    required this.foreground,
  });
  final Color background;
  final Color border;
  final Color foreground;
}
