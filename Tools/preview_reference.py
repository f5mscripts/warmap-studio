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

# Mirrors of the Swift pixel style live near the bottom of this file:
# PIXEL_TERRAIN / PIXEL_FACTION mirror Sources/Rendering/PixelPalette.swift,
# SPRITES mirrors Sources/Rendering/PixelSprite.swift, and render_pixel_map mirrors
# the low-resolution pass in MapSceneRenderer.

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


# ---------------------------------------------------------------------------
# Pixel-art style — mirrors Sources/Rendering/{PixelPalette,PixelGrid,PixelSprite}.swift
# and the low-resolution pass in MapSceneRenderer
# ---------------------------------------------------------------------------

PIXEL_INK = "0B0F1A"
PIXEL_DEEP_SEA = "12294A"
PIXEL_SEA = "1D4E89"
PIXEL_SHALLOW_SEA = "3A7FC1"
PIXEL_NEUTRAL_LAND = "6E7686"
PIXEL_PAPER = "E8ECF5"
PIXEL_AMBER = "F0A02B"
PIXEL_DANGER = "C22E2E"

PIXEL_TERRAIN = [PIXEL_INK, PIXEL_DEEP_SEA, PIXEL_SEA, PIXEL_SHALLOW_SEA,
                 PIXEL_NEUTRAL_LAND, PIXEL_PAPER]

PIXEL_FACTION = [
    "C22E2E", "8C1F1F", "F2643C", "F0A02B", "F5D96B", "7A4A22",
    "C98C4B", "1FA850", "0E6B45", "8FD44A", "1EB9A0", "2E6FE0",
    "6FC8F0", "4B3AA8", "8B45C8", "E05FC0", "9AA3B5", "3C4356",
]

def rgb(hex_string):
    value = int(hex_string, 16)
    return ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)


def colour_distance(a, b):
    """Squared redmean distance — the same approximation the Swift palette uses."""
    r_mean = (a[0] + b[0]) / 2
    dr, dg, db = a[0] - b[0], a[1] - b[1], a[2] - b[2]
    return ((2 + r_mean / 256) * dr * dr + 4 * dg * dg
            + (2 + (255 - r_mean) / 256) * db * db)


def quantise(colour, candidates=None):
    candidates = candidates or (PIXEL_TERRAIN + PIXEL_FACTION)
    return rgb(min(candidates, key=lambda c: colour_distance(colour, rgb(c))))


def quantise_factions(colours_by_id):
    """Spread a whole cast across the faction palette, in id order.

    Same rule as PixelPalette.factionColors: each country takes its nearest unused
    entry, and only once all eighteen are gone do countries start sharing one.
    """
    taken, result = set(), {}
    for key in sorted(colours_by_id):
        target = colours_by_id[key]
        free = [c for c in PIXEL_FACTION if c not in taken] or PIXEL_FACTION
        chosen = min(free, key=lambda c: colour_distance(target, rgb(c)))
        taken.add(chosen)
        result[key] = rgb(chosen)
    return result


def pixel_buffer(width, height, short_edge=200):
    """Low-resolution buffer size and the whole-number factor it is blown up by."""
    scale = max(1, round(min(width, height) / short_edge))
    return (math.ceil(width / scale), math.ceil(height / scale)), scale


SPRITES = {
    "infantry": [
        "............",
        "....kkk..k..",
        "...klllk.k..",
        "...kbbbk.k..",
        "....kkk..k..",
        "..kbbbbbkk..",
        ".kbbbbbbbk..",
        ".kbbbbbk.k..",
        "..kbbbk..k..",
        "..kb.bk.....",
        "..kk.kk.....",
        "............",
    ],
    "armour": [
        "............",
        "............",
        "....kkkk....",
        "...kbbbbk...",
        "...kbbbbkkkk",
        ".kkkkkkkkk..",
        ".kbbbbbbbbk.",
        ".kbbbbbbbbk.",
        ".kkkkkkkkkk.",
        ".klklklklkk.",
        ".kkkkkkkkkk.",
        "............",
    ],
    "cavalry": [
        "............",
        ".......kkk..",
        "......kbbbk.",
        "..kkkkkbbk..",
        ".kbbbbbbbk..",
        ".kbbbbbbk...",
        ".kbbbbbbk...",
        ".kk.kk.kk...",
        ".k..k..k....",
        ".k..k..k....",
        ".kk.kk.kk...",
        "............",
    ],
    "airborne": [
        "...kkkkkk...",
        "..kllllllk..",
        ".kllllllllk.",
        "..kk.kk.kk..",
        "...k.kk.k...",
        "....k..k....",
        "....kbbk....",
        "...kbbbbk...",
        "....kbbk....",
        "....k..k....",
        "...kk..kk...",
        "............",
    ],
    "marine": [
        "............",
        "....kkk.....",
        "...klllk....",
        "...kbbbk....",
        "..kbbbbbk...",
        "..kbbbbbk...",
        "...kbbbk....",
        "...kb.bk....",
        "............",
        ".kllkllkllk.",
        "..kllkllkll.",
        "............",
    ],
    "artillery": [
        "..........k.",
        ".........kk.",
        "........kk..",
        ".......kk...",
        "......kk....",
        ".kkk.kk.....",
        "kbbbkk......",
        "kbkbbk.kkkk.",
        "kbbbkk......",
        ".kkk........",
        "............",
        "............",
    ],
    "fleet": [
        "............",
        "......k.....",
        "......k.....",
        "....kkkkk...",
        "....kbbbk...",
        "kkkkkbbbkkk.",
        "kbbbbbbbbbk.",
        ".kbbbbbbbk..",
        "..kkkkkkk...",
        "...llllll...",
        "............",
        "............",
    ],
    "airForce": [
        "............",
        ".....kk.....",
        "....kbbk....",
        "....kbbk....",
        "kkkkkbbkkkkk",
        "kbbbbbbbbbbk",
        "kkkkkbbkkkkk",
        "....kbbk....",
        "...kkbbkk...",
        "...kbbbbk...",
        "....kkkk....",
        "............",
    ],
    "partisan": [
        "......kkkkk.",
        "....kkkaaak.",
        "...klllkaak.",
        "...kbbbk.k..",
        "..kbbbbbkk..",
        "..kbbbbbk...",
        "...kbbbk....",
        "...kb.bk....",
        "...kb.bk....",
        "..kk...kk...",
        "............",
        "............",
    ],
    "battle": [
        ".k........k.",
        ".lk......kl.",
        "..lk....kl..",
        "...lk..kl...",
        "....lkkl....",
        ".....ll.....",
        "....lkkl....",
        "...kl..lk...",
        "..kl....lk..",
        ".kk......kk.",
        ".k........k.",
        "............",
    ],
    "majorBattle": [
        "....k..k....",
        ".k..kaak..k.",
        "..k.kaak.k..",
        "...kaaaak...",
        ".kkaaaaaakk.",
        "..aaallaaa..",
        ".kkaaaaaakk.",
        "...kaaaak...",
        "..k.kaak.k..",
        ".k..kaak..k.",
        "....k..k....",
        "............",
    ],
    "cityCapture": [
        "....kkkk....",
        "....kaaak...",
        "....kaak....",
        "....k.......",
        "....k.......",
        ".kkkkkkkk...",
        ".klllllk....",
        ".klkllklk...",
        ".kllllllk...",
        ".klkllklk...",
        ".kkkkkkkk...",
        "............",
    ],
    "offensive": [
        "............",
        "............",
        "......kk....",
        "......kak...",
        "kkkkkkkaak..",
        "kaaaaaaaaak.",
        "kaaaaaaaaak.",
        "kkkkkkkaak..",
        "......kak...",
        "......kk....",
        "............",
        "............",
    ],
    "defensive": [
        "............",
        "..kkkkkkkk..",
        "..kllllllk..",
        "..kllbbllk..",
        "..kllbbllk..",
        "..klbbbblk..",
        "...kllllk...",
        "...kllllk...",
        "....kllk....",
        ".....kk.....",
        "............",
        "............",
    ],
    "siege": [
        "............",
        "............",
        ".k.k.k.k.k..",
        ".kkkkkkkkk..",
        ".klllllllk..",
        ".klkkkkklk..",
        ".klkllklk...",
        ".klkllklk...",
        ".kkkkkkkkk..",
        "............",
        "............",
        "............",
    ],
    "naval": [
        ".....kk.....",
        "....klllk...",
        ".....kk.....",
        "...kkkkkk...",
        ".....ll.....",
        ".....ll.....",
        ".k...ll...k.",
        ".kl..ll..lk.",
        "..kl.ll.lk..",
        "...klllk....",
        "....kkk.....",
        "............",
    ],
    "airBattle": [
        "............",
        ".....kk..a..",
        "....kllk.aa.",
        "....kllk.a..",
        "kkkkkllkkkkk",
        "kllllllllllk",
        "kkkkkllkkkkk",
        "....kllk....",
        "...kkllkk.a.",
        "...kllllk.a.",
        "....kkkk....",
        "............",
    ],
}


def draw_sprite(d, rows, x, y, body, cell=1):
    """Paint a sprite, one rectangle per run of equal tone."""
    tones = {"k": rgb(PIXEL_INK), "b": body, "l": rgb(PIXEL_PAPER), "a": rgb(PIXEL_DANGER)}
    for row_index, row in enumerate(rows):
        for col_index, char in enumerate(row):
            if char == ".":
                continue
            px = x + col_index * cell
            py = y + row_index * cell
            d.rectangle([px, py, px + cell - 1, py + cell - 1], fill=tones[char])


def render_pixel_map(geometry, borders, territories, cities, cam, owners, size,
                     short_edge=200, sweeps=None, title=None, subtitle=None,
                     markers=None):
    """The pixel style: render small onto a snapped grid, then blow it up.

    The camera is rebuilt for the low-resolution viewport so it frames the same land,
    every projected point is rounded onto the pixel grid before anything is filled,
    and the upscale is NEAREST — which is the whole effect.
    """
    (low_w, low_h), scale = pixel_buffer(size[0], size[1], short_edge)
    low = Camera(cam.center_lon, cam.center_lat, cam.span, low_w, low_h)
    img = Image.new("RGB", (low_w, low_h), rgb(PIXEL_SEA))
    d = ImageDraw.Draw(img)
    sweeps = sweeps or {}

    faction_colours = quantise_factions({k: v[1] for k, v in POWERS.items()})

    half_w = low.span / 2
    half_h = (low.height / low.k) / low.aspect / 2
    view = (low.center_lon - half_w, low.center_lat - half_h,
            low.center_lon + half_w, low.center_lat + half_h)

    def visible(unit_id):
        t = territories.get(unit_id)
        if not t:
            return False
        b = t["bbox"]
        return not (b[2] < view[0] or b[0] > view[2] or b[3] < view[1] or b[1] > view[3])

    def snap(points):
        return [(round(x), round(y)) for x, y in points]

    for unit_id, rings_list in geometry.items():
        if not visible(unit_id):
            continue
        power = owners.get(unit_id)
        fill = faction_colours.get(power, rgb(PIXEL_NEUTRAL_LAND))
        for rings in rings_list:
            for idx, ring in enumerate(rings):
                pts = snap([low.project(lon, lat) for lon, lat in ring])
                if len(pts) < 3:
                    continue
                d.polygon(pts, fill=fill if idx == 0 else rgb(PIXEL_SEA))

    for unit_id, (attacker, progress) in sweeps.items():
        rings_list = geometry.get(unit_id)
        if not rings_list or not visible(unit_id):
            continue
        t = territories[unit_id]
        b = t["bbox"]
        x0 = low.project(b[0], t["anchor"][1])
        x1 = low.project(b[2], t["anchor"][1])
        ox = x0[0] + (x1[0] - x0[0]) * progress
        for rings in rings_list:
            for idx, ring in enumerate(rings):
                pts = [low.project(lon, lat) for lon, lat in ring]
                pts = snap(clip_half_plane(pts, (ox, 0), (-1.0, 0.0)))
                if len(pts) < 3:
                    continue
                d.polygon(pts, fill=faction_colours[attacker] if idx == 0 else rgb(PIXEL_SEA))
        # The bright leading edge, two pixels of opaque paper. The Swift renderer
        # clips it to the territory being taken; here it is bounded by that
        # territory's own projected extent, which comes to the same thing.
        top = low.project(b[0], b[3])[1]
        bottom = low.project(b[0], b[1])[1]
        d.line([(round(ox), round(top)), (round(ox), round(bottom))],
               fill=rgb(PIXEL_PAPER), width=2)

    for seg in borders:
        a, b = seg["a"], seg["b"]
        if b is None:
            colour, width = rgb(PIXEL_INK), 1
        else:
            if owners.get(a) == owners.get(b):
                continue
            colour, width = rgb(PIXEL_INK), 2
        pts = snap([low.project(lon, lat) for lon, lat in seg["points"]])
        if len(pts) < 2:
            continue
        if all(p[0] < -20 or p[0] > low_w + 20 or p[1] < -20 or p[1] > low_h + 20
               for p in pts):
            continue
        d.line(pts, fill=colour, width=width)

    for c in cities:
        if c["importance"] > 1:
            continue
        if not (view[0] <= c["lon"] <= view[2] and view[1] <= c["lat"] <= view[3]):
            continue
        x, y = (round(v) for v in low.project(c["lon"], c["lat"]))
        r = 2 if c["capital"] else 1
        d.rectangle([x - r - 1, y - r - 1, x + r, y + r], fill=rgb(PIXEL_INK))
        d.rectangle([x - r, y - r, x + r - 1, y + r - 1],
                    fill=rgb(PIXEL_AMBER) if c["capital"] else rgb(PIXEL_PAPER))

    for marker in markers or []:
        lon, lat, kind, power = marker
        x, y = (round(v) for v in low.project(lon, lat))
        body = faction_colours.get(power, rgb(PIXEL_DANGER))
        draw_sprite(d, SPRITES[kind], x - 6, y - 6, body)

    if title:
        d.rectangle([0, 0, low_w, 13], fill=rgb(PIXEL_INK))
        d.text((3, 2), title, fill=rgb(PIXEL_AMBER))
        if subtitle:
            d.text((3, 15), subtitle, fill=rgb(PIXEL_PAPER))

    print(f"    {low_w}x{low_h} buffer, {scale}x upscale")
    return img.resize((low_w * scale, low_h * scale), Image.NEAREST)


def render_sprite_sheet(scale=6):
    """Every sprite on one sheet, so the art can be judged rather than imagined."""
    names = list(SPRITES)
    columns = 6
    rows = math.ceil(len(names) / columns)
    cell = 16
    img = Image.new("RGB", (columns * cell, rows * cell + 6), rgb(PIXEL_SEA))
    d = ImageDraw.Draw(img)
    for index, name in enumerate(names):
        x = (index % columns) * cell + 2
        y = (index // columns) * cell + 2
        draw_sprite(d, SPRITES[name], x, y, rgb("C98C4B"))
    sheet = img.resize((img.width * scale, img.height * scale), Image.NEAREST)
    d = ImageDraw.Draw(sheet)
    for index, name in enumerate(names):
        x = (index % columns) * cell * scale + 4
        y = ((index // columns) * cell + cell - 3) * scale
        d.text((x, y), name, fill=rgb(PIXEL_PAPER))
    return sheet


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

    print("  pixel sprites …")
    render_sprite_sheet().save(os.path.join(OUT, "04_pixel_sprites.png"))

    print("  pixel europe 1939 …")
    cam = Camera.fitting([-12, 35, 42, 68], 1080, 1350)
    render_pixel_map(geometry, borders, territories, cities, cam, OWNERS_1939,
                     (1080, 1350),
                     title="EUROPE - 1939",
                     subtitle="pixel style",
                     markers=[(13.4, 52.5, "armour", "germany"),
                              (21.0, 52.2, "infantry", "poland"),
                              (2.3, 48.9, "airForce", "france"),
                              (-0.1, 51.5, "fleet", "uk"),
                              (19.0, 50.0, "majorBattle", None)]
                     ).save(os.path.join(OUT, "05_pixel_europe_1939.png"))

    print("  pixel invasion …")
    cam = Camera.fitting([10, 46, 30, 56], 1080, 1350)
    render_pixel_map(geometry, borders, territories, cities, cam, OWNERS_1939,
                     (1080, 1350),
                     sweeps={"POL": ("germany", 0.55)},
                     title="INVASION OF POLAND",
                     subtitle="advance 55%",
                     markers=[(17.0, 52.0, "armour", "germany"),
                              (21.0, 52.2, "infantry", "poland"),
                              (19.0, 51.0, "offensive", None)]
                     ).save(os.path.join(OUT, "06_pixel_invasion.png"))

    print(f"wrote frames to {OUT}")


if __name__ == "__main__":
    main()
