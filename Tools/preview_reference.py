#!/usr/bin/env python3
"""Reference renderer for the WarMap Studio map engine.

This is a development tool, not shipped code. It implements the same projection,
half-plane clipping and territory-fill algorithms that the Swift renderer uses, so
the geometry pipeline and the visual design can be checked as images before any of
it is ported. When the Swift output disagrees with these frames, one of the two is
wrong and this file is the reference.

Usage:  python3 Tools/preview_reference.py
Writes: Tools/out/*.png
"""

from __future__ import annotations

import json
import math
import os
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DATA = os.path.join(ROOT, "Resources", "MapData")
OUT = os.path.join(HERE, "out")

OCEAN = (18, 28, 38)
OCEAN_DEEP = (12, 20, 28)
BORDER = (14, 16, 20)
COAST = (60, 70, 82)
NEUTRAL = (104, 108, 116)
TEXT = (242, 237, 225)
GOLD = (201, 162, 39)


# ---------------------------------------------------------------------------
# Projection — mirrors Sources/Geo/Projection.swift
# ---------------------------------------------------------------------------

class Camera:
    """Maps lon/lat to pixels.

    `span` is the width of the viewport in degrees of longitude. Latitude is scaled
    by cos(centre latitude) so that Europe does not look stretched the way raw
    Plate Carrée makes it — the standard-parallel trick.
    """

    def __init__(self, center_lon, center_lat, span, width, height):
        self.center_lon = center_lon
        self.center_lat = center_lat
        self.span = span
        self.width = width
        self.height = height
        self.k = width / span
        self.aspect = 1.0 / max(0.2, math.cos(math.radians(center_lat)))

    def project(self, lon, lat):
        x = (lon - self.center_lon) * self.k + self.width / 2
        y = -(lat - self.center_lat) * self.k * self.aspect + self.height / 2
        return (x, y)

    @classmethod
    def fitting(cls, bbox, width, height, padding=0.06):
        min_lon, min_lat, max_lon, max_lat = bbox
        clon = (min_lon + max_lon) / 2
        clat = (min_lat + max_lat) / 2
        aspect = 1.0 / max(0.2, math.cos(math.radians(clat)))
        span_x = (max_lon - min_lon) * (1 + padding * 2)
        # Convert the latitude extent into the longitude units the camera works in.
        span_y = (max_lat - min_lat) * aspect * (1 + padding * 2) * (width / height)
        return cls(clon, clat, max(span_x, span_y), width, height)


# ---------------------------------------------------------------------------
# Half-plane clipping — mirrors Sources/Geo/Clipping.swift
# ---------------------------------------------------------------------------

def clip_half_plane(points, origin, normal):
    """Sutherland–Hodgman against one half-plane.

    Keeps the side where dot(p - origin, normal) >= 0. This single primitive drives
    every sweeping border animation in the app: advance `origin` along `normal` and
    the attacker's fill grows across the territory.
    """
    if not points:
        return []
    ox, oy = origin
    nx, ny = normal

    def side(p):
        return (p[0] - ox) * nx + (p[1] - oy) * ny

    out = []
    n = len(points)
    for i in range(n):
        cur = points[i]
        nxt = points[(i + 1) % n]
        dc, dn = side(cur), side(nxt)
        if dc >= 0:
            out.append(cur)
        if (dc >= 0) != (dn >= 0):
            t = dc / (dc - dn)
            out.append((cur[0] + (nxt[0] - cur[0]) * t, cur[1] + (nxt[1] - cur[1]) * t))
    return out


# ---------------------------------------------------------------------------
# Data
# ---------------------------------------------------------------------------

def load(lod=1):
    with open(os.path.join(DATA, f"geometry-lod{lod}.json"), encoding="utf-8") as f:
        geometry = json.load(f)
    with open(os.path.join(DATA, f"borders-lod{lod}.json"), encoding="utf-8") as f:
        borders = json.load(f)
    with open(os.path.join(DATA, "territories.json"), encoding="utf-8") as f:
        territories = {t["id"]: t for t in json.load(f)}
    with open(os.path.join(DATA, "cities.json"), encoding="utf-8") as f:
        cities = json.load(f)
    return geometry, borders, territories, cities


# Europe on 1 September 1939. Territory unit -> power.
OWNERS_1939 = {
    "DEU": "germany", "AUT": "germany", "CZE": "germany", "RUS-KGD": "germany",
    "SVK": "slovakia",
    "POL": "poland", "UKR-W": "poland", "BLR-W": "poland",
    "RUS": "ussr", "UKR-E": "ussr", "UKR-CRIMEA": "ussr", "BLR-E": "ussr",
    "KAZ": "ussr", "UZB": "ussr", "TKM": "ussr", "KGZ": "ussr", "TJK": "ussr",
    "GEO": "ussr", "ARM": "ussr", "AZE": "ussr",
    "FRA-OCC": "france", "FRA-VICHY": "france",
    "GBR": "uk", "IRL": "ireland",
    "ITA": "italy", "ALB": "italy",
    "ESP": "spain", "PRT": "portugal",
    "ROU": "romania", "ROU-TRANS-N": "romania", "MDA": "romania",
    "HUN": "hungary", "BGR": "bulgaria", "GRC": "greece", "TUR": "turkey",
    "SRB": "yugoslavia", "HRV": "yugoslavia", "BIH": "yugoslavia",
    "SVN": "yugoslavia", "MNE": "yugoslavia", "MKD": "yugoslavia", "KOS": "yugoslavia",
    "FIN": "finland", "FIN-KARELIA": "finland",
    "SWE": "sweden", "NOR": "norway", "DNK": "denmark",
    "EST": "estonia", "LVA": "latvia", "LTU": "lithuania",
    "NLD": "netherlands", "BEL": "belgium", "LUX": "luxembourg",
    "CHE": "switzerland", "ISL": "iceland",
}

POWERS = {
    "germany":     ("German Reich",  (94, 104, 96)),
    "slovakia":    ("Slovakia",      (132, 138, 112)),
    "poland":      ("Poland",        (176, 74, 68)),
    "ussr":        ("USSR",          (150, 44, 44)),
    "france":      ("France",        (86, 116, 158)),
    "uk":          ("United Kingdom",(122, 96, 148)),
    "italy":       ("Italy",         (128, 138, 84)),
    "romania":     ("Romania",       (168, 132, 72)),
    "hungary":     ("Hungary",       (140, 118, 88)),
    "yugoslavia":  ("Yugoslavia",    (108, 132, 116)),
    "bulgaria":    ("Bulgaria",      (120, 108, 76)),
    "greece":      ("Greece",        (92, 126, 152)),
    "turkey":      ("Turkey",        (150, 108, 80)),
    "finland":     ("Finland",       (140, 152, 160)),
    "sweden":      ("Sweden",        (96, 118, 140)),
    "norway":      ("Norway",        (110, 128, 148)),
    "denmark":     ("Denmark",       (158, 118, 110)),
    "estonia":     ("Estonia",       (128, 140, 148)),
    "latvia":      ("Latvia",        (136, 116, 112)),
    "lithuania":   ("Lithuania",     (144, 128, 100)),
    "netherlands": ("Netherlands",   (176, 130, 82)),
    "belgium":     ("Belgium",       (152, 140, 96)),
    "luxembourg":  ("Luxembourg",    (150, 150, 120)),
    "switzerland": ("Switzerland",   (128, 96, 96)),
    "spain":       ("Spain",         (162, 138, 84)),
    "portugal":    ("Portugal",      (110, 132, 100)),
    "ireland":     ("Ireland",       (100, 134, 108)),
    "iceland":     ("Iceland",       (120, 132, 142)),
}


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

def ocean_background(img, cam):
    d = ImageDraw.Draw(img)
    for y in range(img.height):
        t = y / max(1, img.height - 1)
        col = tuple(int(OCEAN[c] + (OCEAN_DEEP[c] - OCEAN[c]) * t) for c in range(3))
        d.line([(0, y), (img.width, y)], fill=col)


def draw_unit(d, cam, rings_list, fill, sweep=None):
    """Fill one territory. `sweep` optionally clips it to an advancing half-plane.

    No outline is stroked here — borders are drawn separately from the shared-edge
    table so that internal cuts between same-owner units stay invisible.
    """
    for rings in rings_list:
        for idx, ring in enumerate(rings):
            pts = [cam.project(lon, lat) for lon, lat in ring]
            if sweep is not None:
                pts = clip_half_plane(pts, sweep[0], sweep[1])
            if len(pts) < 3:
                continue
            # Interior rings (holes) are painted with the ocean colour rather than
            # punched out — adequate for a reference image.
            d.polygon(pts, fill=fill if idx == 0 else OCEAN)


def draw_borders(d, cam, borders, owners, view):
    """Stroke coastlines, and political borders only where ownership changes."""
    for seg in borders:
        a, b = seg["a"], seg["b"]
        if b is None:
            colour, width = COAST, 1
        else:
            if owners.get(a) == owners.get(b):
                continue  # same power on both sides: not a border at all
            colour, width = BORDER, 2
        pts = [cam.project(lon, lat) for lon, lat in seg["points"]]
        if len(pts) < 2:
            continue
        if all(p[0] < -50 or p[0] > cam.width + 50 or p[1] < -50 or p[1] > cam.height + 50
               for p in pts):
            continue
        d.line(pts, fill=colour, width=width, joint="curve")


def render_map(geometry, borders, territories, cities, cam, owners, size,
               title=None, subtitle=None, sweeps=None, show_cities=True):
    img = Image.new("RGB", size, OCEAN)
    ocean_background(img, cam)
    d = ImageDraw.Draw(img)
    sweeps = sweeps or {}

    # Cull to what the camera can actually see before touching any geometry.
    half_w = cam.span / 2
    half_h = (cam.height / cam.k) / cam.aspect / 2
    view = (cam.center_lon - half_w, cam.center_lat - half_h,
            cam.center_lon + half_w, cam.center_lat + half_h)

    def visible(unit_id):
        t = territories.get(unit_id)
        if not t:
            return False
        b = t["bbox"]
        return not (b[2] < view[0] or b[0] > view[2] or b[3] < view[1] or b[1] > view[3])

    drawn = 0
    for unit_id, rings_list in geometry.items():
        if not visible(unit_id):
            continue
        drawn += 1
        power = owners.get(unit_id)
        fill = POWERS[power][1] if power in POWERS else NEUTRAL
        draw_unit(d, cam, rings_list, fill)

    # Contested territories are repainted on top, clipped to the attacker's advance.
    for unit_id, (attacker, progress) in sweeps.items():
        rings_list = geometry.get(unit_id)
        if not rings_list or not visible(unit_id):
            continue
        t = territories[unit_id]
        b = t["bbox"]
        # Sweep west to east across the territory's own bounding box.
        x0 = cam.project(b[0], t["anchor"][1])
        x1 = cam.project(b[2], t["anchor"][1])
        ox = x0[0] + (x1[0] - x0[0]) * progress
        draw_unit(d, cam, rings_list, POWERS[attacker][1],
                  sweep=((ox, 0), (-1.0, 0.0)))

    draw_borders(d, cam, borders, owners, view)

    if show_cities:
        for c in cities:
            if c["importance"] > 2:
                continue
            if not (view[0] <= c["lon"] <= view[2] and view[1] <= c["lat"] <= view[3]):
                continue
            x, y = cam.project(c["lon"], c["lat"])
            r = 3 if c["capital"] else 2
            d.ellipse([x - r, y - r, x + r, y + r], fill=TEXT, outline=(20, 20, 20))
            d.text((x + 5, y - 6), c["name"], fill=TEXT)

    if title:
        d.rectangle([0, 0, size[0], 54], fill=(11, 13, 16))
        d.text((16, 12), title, fill=GOLD)
        if subtitle:
            d.text((16, 32), subtitle, fill=(168, 162, 150))

    print(f"    drew {drawn} territories")
    return img


def main():
    os.makedirs(OUT, exist_ok=True)
    geometry, borders, territories, cities = load(lod=1)

    print("  world …")
    cam = Camera.fitting([-180, -58, 180, 82], 1280, 720)
    render_map(geometry, borders, territories, cities, cam, {}, (1280, 720),
               title="MODERN WORLD", subtitle="184 territory units, Natural Earth 110m",
               show_cities=False).save(os.path.join(OUT, "01_world.png"))

    print("  europe 1939 …")
    cam = Camera.fitting([-12, 35, 42, 68], 1080, 1350)
    render_map(geometry, borders, territories, cities, cam, OWNERS_1939, (1080, 1350),
               title="EUROPE - 1 SEPTEMBER 1939",
               subtitle="Ownership overlay over Natural Earth geometry"
               ).save(os.path.join(OUT, "02_europe_1939.png"))

    print("  invasion sweep …")
    cam = Camera.fitting([10, 46, 30, 56], 900, 900)
    frames = []
    for i, p in enumerate([0.0, 0.35, 0.7, 1.0]):
        img = render_map(geometry, borders, territories, cities, cam, OWNERS_1939, (900, 900),
                         title="INVASION OF POLAND",
                         subtitle=f"advance {int(p * 100)}%",
                         sweeps={"POL": ("germany", p)})
        frames.append(img)
    strip = Image.new("RGB", (900 * 2, 900 * 2))
    for i, f in enumerate(frames):
        strip.paste(f, ((i % 2) * 900, (i // 2) * 900))
    strip.resize((900, 900), Image.LANCZOS).save(os.path.join(OUT, "03_invasion_sweep.png"))

    print(f"wrote frames to {OUT}")


if __name__ == "__main__":
    main()
