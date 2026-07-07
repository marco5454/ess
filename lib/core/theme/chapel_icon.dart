import 'package:flutter/material.dart';

import 'chapel_theme.dart';

/// A small, tasteful open-book icon rendered from a [CustomPainter].
///
/// Deliberately simple silhouette: two rounded pages with a spine and a
/// subtle bookmark ribbon in the gold accent color. Designed to sit at
/// small sizes (16-24px) on an AppBar leading widget, and to scale up
/// cleanly for a login screen hero (60-96px).
class ChapelIcon extends StatelessWidget {
  const ChapelIcon({
    super.key,
    this.size = 24,
    this.foreground = Colors.white,
    this.accent = ChapelPalette.gold,
  });

  final double size;
  final Color foreground;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ChapelIconPainter(
          fg: foreground,
          accent: accent,
        ),
      ),
    );
  }
}

class _ChapelIconPainter extends CustomPainter {
  _ChapelIconPainter({required this.fg, required this.accent});

  final Color fg;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final stroke = Paint()
      ..color = fg
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = w * 0.08;

    // Two page arcs meeting at the spine.
    final leftPage = Path()
      ..moveTo(w * 0.10, h * 0.30)
      ..quadraticBezierTo(w * 0.28, h * 0.22, w * 0.50, h * 0.32)
      ..lineTo(w * 0.50, h * 0.82)
      ..quadraticBezierTo(w * 0.28, h * 0.72, w * 0.10, h * 0.80)
      ..close();

    final rightPage = Path()
      ..moveTo(w * 0.90, h * 0.30)
      ..quadraticBezierTo(w * 0.72, h * 0.22, w * 0.50, h * 0.32)
      ..lineTo(w * 0.50, h * 0.82)
      ..quadraticBezierTo(w * 0.72, h * 0.72, w * 0.90, h * 0.80)
      ..close();

    canvas.drawPath(leftPage, stroke);
    canvas.drawPath(rightPage, stroke);

    // A couple of subtle content lines on each page.
    final line = Paint()
      ..color = fg
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w * 0.05;

    for (final t in const [0.44, 0.58]) {
      canvas.drawLine(
        Offset(w * 0.20, h * t),
        Offset(w * 0.42, h * (t + 0.02)),
        line,
      );
      canvas.drawLine(
        Offset(w * 0.58, h * (t + 0.02)),
        Offset(w * 0.80, h * t),
        line,
      );
    }

    // Gold bookmark ribbon on the right page.
    final ribbon = Paint()..color = accent;
    final ribbonPath = Path()
      ..moveTo(w * 0.66, h * 0.22)
      ..lineTo(w * 0.66, h * 0.50)
      ..lineTo(w * 0.70, h * 0.44)
      ..lineTo(w * 0.74, h * 0.50)
      ..lineTo(w * 0.74, h * 0.22)
      ..close();
    canvas.drawPath(ribbonPath, ribbon);
  }

  @override
  bool shouldRepaint(covariant _ChapelIconPainter old) =>
      old.fg != fg || old.accent != accent;
}
