#!/usr/bin/env python3
"""
Bake the Bishopric Tracker launcher icon.

Renders the same open-book-with-bookmark composition as
`lib/core/theme/chapel_icon.dart`, but drawn onto a navy background
tile so it can be used as a launcher icon on light OS home screens.

Emits three files under `branding/`:

    icon-1024.png              — 1024x1024, fully-bled (matches
                                  Android 8+ full-bleed / iOS legacy)
    icon-adaptive-fg-1024.png  — 1024x1024, transparent, foreground
                                  only, padded to the Android
                                  adaptive-icon safe zone (66% of the
                                  1024 box, per Android spec)
    icon-adaptive-bg.png       — 1024x1024 solid navy background

The Android adaptive-icon spec expects both layers at the same 108dp
size with the safe visible area sized 72dp/108dp = 66.6%. We render
the foreground into a 682-px inset so the OS-side circular / squircle
mask never clips the book.
"""

from PIL import Image, ImageDraw

# ── Palette (mirrors ChapelPalette in Dart) ─────────────────────────
NAVY = (46, 64, 87, 255)        # #2E4057
NAVY_DARK = (31, 46, 63, 255)   # #1F2E3F (edge / shadow)
WHITE = (255, 255, 255, 255)
GOLD = (176, 138, 62, 255)      # #B08A3E
GOLD_DARK = (135, 104, 43, 255) # #87682B
TRANSPARENT = (0, 0, 0, 0)


def _hex(color, alpha):
    r, g, b = color[:3]
    return (r, g, b, alpha)


def draw_chapel_icon(draw, x, y, w, h):
    """Draw the open-book-and-bookmark mark inside the (x, y, w, h) box."""

    def px(fx):
        return x + int(round(fx * w))

    def py(fy):
        return y + int(round(fy * h))

    # ── Pages ──────────────────────────────────────────────────────
    # Filled pages that meet at a spine. We approximate the Dart
    # quadratic bezier with a small polyline for portability with PIL.
    def curve(x0, y0, cx, cy, x1, y1, steps=32):
        """Sample a quadratic bezier (P0, C, P1)."""
        pts = []
        for i in range(steps + 1):
            t = i / steps
            xt = (1 - t) ** 2 * x0 + 2 * (1 - t) * t * cx + t * t * x1
            yt = (1 - t) ** 2 * y0 + 2 * (1 - t) * t * cy + t * t * y1
            pts.append((px(xt), py(yt)))
        return pts

    left_page = (
        curve(0.09, 0.30, 0.28, 0.22, 0.49, 0.30)
        + [(px(0.49), py(0.82))]
        + list(reversed(curve(0.09, 0.80, 0.28, 0.74, 0.49, 0.82)))
    )
    right_page = (
        curve(0.51, 0.30, 0.72, 0.22, 0.91, 0.30)
        + [(px(0.91), py(0.80))]
        + list(reversed(curve(0.51, 0.82, 0.72, 0.74, 0.91, 0.80)))
    )

    draw.polygon(left_page, fill=WHITE)
    draw.polygon(right_page, fill=WHITE)

    # ── Spine gutter (subtle darker ridge) ────────────────────────
    gutter_w = max(2, int(round(w * 0.03)))
    draw.line(
        [(px(0.50), py(0.30)), (px(0.50), py(0.82))],
        fill=(0, 0, 0, 60),
        width=gutter_w,
    )

    # ── Text lines on the pages ────────────────────────────────────
    line_w = max(2, int(round(w * 0.04)))
    line_col = (0, 0, 0, 55)  # dark grey, low alpha — "printed text"
    for t in (0.40, 0.50, 0.60, 0.70):
        # Left page (slight angle down toward spine)
        draw.line(
            [(px(0.16), py(t + 0.005)), (px(0.43), py(t - 0.005))],
            fill=line_col,
            width=line_w,
        )
        # Right page (mirrored)
        draw.line(
            [(px(0.57), py(t - 0.005)), (px(0.84), py(t + 0.005))],
            fill=line_col,
            width=line_w,
        )

    # ── Bookmark ribbon ────────────────────────────────────────────
    ribbon = [
        (px(0.66), py(0.20)),
        (px(0.66), py(0.54)),
        (px(0.71), py(0.46)),
        (px(0.76), py(0.54)),
        (px(0.76), py(0.20)),
    ]
    draw.polygon(ribbon, fill=GOLD)

    # Narrow shaded strip on the right edge of the ribbon
    ribbon_hi = [
        (px(0.735), py(0.20)),
        (px(0.76), py(0.20)),
        (px(0.76), py(0.54)),
        (px(0.735), py(0.505)),
    ]
    draw.polygon(ribbon_hi, fill=GOLD_DARK)


def rounded_tile(size, radius, fill):
    tile = Image.new("RGBA", (size, size), TRANSPARENT)
    draw = ImageDraw.Draw(tile)
    draw.rounded_rectangle([(0, 0), (size, size)], radius=radius, fill=fill)
    return tile


def main():
    size = 1024

    # ── (1) Full-bleed icon (navy tile + book) ────────────────────
    # 22% corner radius matches the Material-3 look Google uses
    # internally when auto-masking a legacy square icon into the
    # adaptive-icon squircle. iOS ignores this radius and applies its
    # own mask, which is why we still ship the layer as a filled
    # rounded square.
    icon = rounded_tile(size, int(size * 0.22), NAVY)
    draw = ImageDraw.Draw(icon)
    # Book fills roughly the middle 72% of the tile
    inset = int(size * 0.14)
    draw_chapel_icon(
        draw, inset, inset, size - 2 * inset, size - 2 * inset,
    )
    icon.save("branding/icon-1024.png")

    # ── (2) Android adaptive foreground ───────────────────────────
    # Fully transparent background. Book is centered in the inner
    # 66% safe zone so no launcher mask ever clips it.
    fg = Image.new("RGBA", (size, size), TRANSPARENT)
    fg_draw = ImageDraw.Draw(fg)
    safe = int(size * 0.66)
    fg_inset = (size - safe) // 2
    draw_chapel_icon(fg_draw, fg_inset, fg_inset, safe, safe)
    fg.save("branding/icon-adaptive-fg-1024.png")

    # ── (3) Android adaptive background ───────────────────────────
    bg = Image.new("RGBA", (size, size), NAVY)
    bg.save("branding/icon-adaptive-bg.png")

    print("Wrote branding/icon-1024.png")
    print("Wrote branding/icon-adaptive-fg-1024.png")
    print("Wrote branding/icon-adaptive-bg.png")


if __name__ == "__main__":
    main()
