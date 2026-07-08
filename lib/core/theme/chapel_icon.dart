import 'package:flutter/material.dart';

import 'chapel_theme.dart';

/// The Bishopric Tracker mark: an open book with a gold bookmark ribbon.
///
/// Rendered from a [CustomPainter] so it stays crisp at every size —
/// from a 16 px AppBar leading widget up through a 512 px launcher-icon
/// bake. The silhouette is deliberately simple: two filled pages
/// meeting at a spine, four evenly spaced text lines, and a gold
/// bookmark ribbon draped over the right page.
///
/// Callers can override [foreground] and [accent] to render the icon on
/// arbitrary backgrounds (e.g. cream/navy tiles). The default pairing
/// is `foreground: Colors.white` + `accent: ChapelPalette.gold`, which
/// looks right on the navy hero tile used by the login screen.
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
        painter: _ChapelIconPainter(fg: foreground, accent: accent),
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

    // ── Pages ────────────────────────────────────────────────────────
    // Solid-filled pages. Filling reads better than an outline once the
    // icon shrinks to 16-24 px on an AppBar; outlines get muddy under
    // Impeller's edge AA.
    final pageFill = Paint()
      ..color = fg
      ..style = PaintingStyle.fill;

    // Subtle shadow ridge under the spine gives the book a bit of
    // three-dimensionality without needing a real drop shadow.
    final gutter = Paint()
      ..color = fg.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w * 0.03;

    final leftPage = Path()
      ..moveTo(w * 0.09, h * 0.30)
      ..quadraticBezierTo(w * 0.28, h * 0.22, w * 0.49, h * 0.30)
      ..lineTo(w * 0.49, h * 0.82)
      ..quadraticBezierTo(w * 0.28, h * 0.74, w * 0.09, h * 0.80)
      ..close();

    final rightPage = Path()
      ..moveTo(w * 0.91, h * 0.30)
      ..quadraticBezierTo(w * 0.72, h * 0.22, w * 0.51, h * 0.30)
      ..lineTo(w * 0.51, h * 0.82)
      ..quadraticBezierTo(w * 0.72, h * 0.74, w * 0.91, h * 0.80)
      ..close();

    canvas.drawPath(leftPage, pageFill);
    canvas.drawPath(rightPage, pageFill);

    // Center spine gutter — draws over the join between the two pages.
    canvas.drawLine(
      Offset(w * 0.50, h * 0.30),
      Offset(w * 0.50, h * 0.82),
      gutter,
    );

    // ── Text lines on the pages ──────────────────────────────────────
    // Four evenly spaced lines per side, drawn in the inverse (i.e.
    // background) direction using a color that reads as "empty page".
    // Since pages are filled with `fg`, we knock out the lines by
    // painting them in the accent's darker cousin only for the ribbon
    // area — here we simply cut them from the page with a very slight
    // alpha of `fg` (giving grey ruled lines on white pages that still
    // read as printed text at small sizes).
    final line = Paint()
      ..color = fg.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w * 0.04;

    const lineStops = <double>[0.40, 0.50, 0.60, 0.70];
    for (final t in lineStops) {
      // Left page line — angled to follow the page's slight curl.
      canvas.drawLine(
        Offset(w * 0.16, h * (t + 0.005)),
        Offset(w * 0.43, h * (t - 0.005)),
        line,
      );
      // Right page line — mirrored.
      canvas.drawLine(
        Offset(w * 0.57, h * (t - 0.005)),
        Offset(w * 0.84, h * (t + 0.005)),
        line,
      );
    }

    // ── Bookmark ribbon ──────────────────────────────────────────────
    // Draped over the right page. Solid gold with a subtle darker
    // highlight at the fold to give it depth.
    final ribbon = Paint()..color = accent;
    final ribbonShade = Paint()..color = accent.withValues(alpha: 0.55);

    final ribbonPath = Path()
      ..moveTo(w * 0.66, h * 0.20)
      ..lineTo(w * 0.66, h * 0.54)
      ..lineTo(w * 0.71, h * 0.46)
      ..lineTo(w * 0.76, h * 0.54)
      ..lineTo(w * 0.76, h * 0.20)
      ..close();
    canvas.drawPath(ribbonPath, ribbon);

    // Narrow shaded strip down the right side of the ribbon to hint at
    // a shadow / fold. Runs from top edge down to the V-notch bottom.
    final ribbonHighlight = Path()
      ..moveTo(w * 0.735, h * 0.20)
      ..lineTo(w * 0.76, h * 0.20)
      ..lineTo(w * 0.76, h * 0.54)
      ..lineTo(w * 0.735, h * 0.505)
      ..close();
    canvas.drawPath(ribbonHighlight, ribbonShade);
  }

  @override
  bool shouldRepaint(covariant _ChapelIconPainter old) =>
      old.fg != fg || old.accent != accent;
}
