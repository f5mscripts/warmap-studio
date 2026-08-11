#!/usr/bin/env python3
"""Generate the WarMap Studio app icon.

The mark is a gold compass rose on charcoal, sitting on a faint parchment disc that
carries a graticule, with a crimson advance arc sweeping across it — atlas plus
frontline in one glyph. Drawn at 4x and downsampled so the edges stay clean.

Usage:  python3 Tools/make_app_icon.py
Writes: Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png
"""

from __future__ import annotations

import json
import math
import os
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SS = 4  # supersampling factor
S = SIZE * SS

CHARCOAL = (20, 23, 28, 255)
ABYSS = (11, 13, 16, 255)
PARCHMENT = (232, 220, 192, 255)
GOLD = (201, 162, 39, 255)
GOLD_BRIGHT = (232, 197, 71, 255)
GOLD_DIM = (138, 111, 28, 255)
CRIMSON = (179, 66, 58, 255)

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT_DIR = os.path.join(ROOT, "Resources", "Assets.xcassets", "AppIcon.appiconset")


def radial_background(img: Image.Image) -> None:
    """Paint a soft radial vignette from charcoal centre to near-black corners."""
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, S, S], fill=ABYSS)
    steps = 90
    cx = cy = S / 2
    max_r = S * 0.78
    for i in range(steps, 0, -1):
        t = i / steps
        r = max_r * t
        blend = 1.0 - t
        col = tuple(
            int(ABYSS[c] + (CHARCOAL[c] - ABYSS[c]) * blend) for c in range(3)
        ) + (255,)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col)


def parchment_disc(img: Image.Image) -> None:
    """A dim parchment globe with a graticule, kept low-contrast so the rose leads."""
    disc = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(disc)
    cx = cy = S / 2
    r = S * 0.335

    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=PARCHMENT[:3] + (34,))

    line = PARCHMENT[:3] + (52,)
    w = max(1, int(S * 0.0022))
    # Parallels: horizontal chords of the sphere.
    for frac in (-0.62, -0.32, 0.0, 0.32, 0.62):
        y = cy + r * frac
        half = r * math.sqrt(max(0.0, 1.0 - frac * frac))
        d.line([cx - half, y, cx + half, y], fill=line, width=w)
    # Meridians: ellipses of varying width, the classic globe look.
    for frac in (0.28, 0.62, 1.0):
        rx = r * frac
        d.ellipse([cx - rx, cy - r, cx + rx, cy + r], outline=line, width=w)

    img.alpha_composite(disc)


def compass_rose(img: Image.Image) -> None:
    """Eight-point rose: four long cardinal spikes, four short ordinal ones."""
    rose = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(rose)
    cx = cy = S / 2
    long_r = S * 0.305
    short_r = S * 0.155
    waist = S * 0.040

    def spike(angle_deg: float, length: float, half_width: float, fill) -> None:
        a = math.radians(angle_deg)
        tip = (cx + length * math.cos(a), cy + length * math.sin(a))
        perp = a + math.pi / 2
        left = (cx + half_width * math.cos(perp), cy + half_width * math.sin(perp))
        right = (cx - half_width * math.cos(perp), cy - half_width * math.sin(perp))
        d.polygon([tip, left, (cx, cy), right], fill=fill)

    # Ordinals sit behind, in the dimmer gold, so the cardinals read first.
    for k in range(4):
        spike(45 + 90 * k, short_r, waist * 0.62, GOLD_DIM)
    # Cardinals: each drawn as two half-spikes so one side catches the light.
    for k in range(4):
        ang = 90 * k
        spike(ang, long_r, waist, GOLD)
    for k in range(4):
        ang = 90 * k
        a = math.radians(ang)
        perp = a + math.pi / 2
        tip = (cx + long_r * math.cos(a), cy + long_r * math.sin(a))
        left = (cx + waist * math.cos(perp), cy + waist * math.sin(perp))
        d.polygon([tip, left, (cx, cy)], fill=GOLD_BRIGHT)

    img.alpha_composite(rose)


def advance_arc(img: Image.Image) -> None:
    """A crimson arc with an arrowhead: the frontline sweeping across the map."""
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx = cy = S / 2
    r = S * 0.392
    w = int(S * 0.026)
    d.arc([cx - r, cy - r, cx + r, cy + r], start=205, end=330, fill=CRIMSON, width=w)

    # Arrowhead at the leading (330°) end, aligned to the local tangent.
    a = math.radians(330)
    tip_r = r
    tip = (cx + tip_r * math.cos(a), cy + tip_r * math.sin(a))
    tangent = a + math.pi / 2
    head = S * 0.052
    back = (tip[0] - head * math.cos(tangent), tip[1] - head * math.sin(tangent))
    perp = tangent + math.pi / 2
    hw = S * 0.030
    p1 = (back[0] + hw * math.cos(perp), back[1] + hw * math.sin(perp))
    p2 = (back[0] - hw * math.cos(perp), back[1] - hw * math.sin(perp))
    d.polygon([tip, p1, p2], fill=CRIMSON)

    img.alpha_composite(layer)


def gold_ring(img: Image.Image) -> None:
    d = ImageDraw.Draw(img)
    cx = cy = S / 2
    r = S * 0.445
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=GOLD_DIM, width=int(S * 0.010))
    r2 = S * 0.462
    d.ellipse([cx - r2, cy - r2, cx + r2, cy + r2], outline=GOLD[:3] + (90,), width=int(S * 0.004))


def build() -> Image.Image:
    img = Image.new("RGBA", (S, S), ABYSS)
    radial_background(img)
    parchment_disc(img)
    gold_ring(img)
    advance_arc(img)

    # Drop a soft shadow under the rose so it lifts off the disc: take the rose's own
    # silhouette, recolour it black, blur it, then draw the rose on top.
    silhouette = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    compass_rose(silhouette)
    alpha = silhouette.getchannel("A").point(lambda v: int(v * 0.55))
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow.putalpha(alpha)
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(S * 0.014)))
    compass_rose(img)

    return img.resize((SIZE, SIZE), Image.LANCZOS).convert("RGB")


CONTENTS = {
    "images": [
        {"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}
    ],
    "info": {"author": "xcode", "version": 1},
}


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    icon = build()
    icon.save(os.path.join(OUT_DIR, "icon-1024.png"), format="PNG")
    with open(os.path.join(OUT_DIR, "Contents.json"), "w", encoding="utf-8") as f:
        json.dump(CONTENTS, f, indent=2)
        f.write("\n")
    print(f"wrote {OUT_DIR}/icon-1024.png")


if __name__ == "__main__":
    main()
