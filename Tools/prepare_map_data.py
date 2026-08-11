#!/usr/bin/env python3
"""Build WarMap Studio's bundled map data from Natural Earth.

Natural Earth is public domain (no attribution required), which is why it is the
only geometry we ship. See DATA_LICENSES.md.

What this produces in Resources/MapData/:

  territories.json      one record per territory unit: id, name, ISO, centroid,
                        bounding box, area and the ids of its land neighbours
  geometry-lod0.json    full-detail rings, keyed by unit id
  geometry-lod1.json    medium detail (zoomed-out editing)
  geometry-lod2.json    coarse detail (thumbnails, wide camera)
  cities.json           populated places with importance and historical names
  regions.json          the map presets offered by the New Project wizard

A "territory unit" is the atom of ownership. By default one country is one unit;
countries listed in SUBDIVISIONS are cut into several so that partitions,
occupation zones and ceded provinces can be animated.

Usage:  python3 Tools/prepare_map_data.py
"""

from __future__ import annotations

import json
import math
import os
import ssl
import sys
import urllib.request
from typing import Any, Iterable

from shapely.geometry import shape, box, LineString, Polygon, MultiPolygon
from shapely.geometry.base import BaseGeometry
from shapely.ops import unary_union
from shapely.strtree import STRtree

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CACHE = os.path.join(HERE, ".cache")
OUT = os.path.join(ROOT, "Resources", "MapData")

NE_BASE = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson"
SOURCES = {
    "countries": f"{NE_BASE}/ne_110m_admin_0_countries.geojson",
    "places": f"{NE_BASE}/ne_110m_populated_places.geojson",
}

# Simplification tolerance in degrees for each level of detail.
LOD_TOLERANCE = [0.0, 0.08, 0.35]

# Adjacency: two units are neighbours if their geometries come within this many
# degrees of each other. Natural Earth borders are coincident but not always
# bit-identical, so a small slack avoids missing genuine land borders.
ADJACENCY_SLACK = 0.06


# ---------------------------------------------------------------------------
# Territory subdivisions
#
# Each entry cuts a parent country into named pieces. `clip` is the region kept
# for that piece; whatever is left of the parent becomes the `remainder` unit.
# Boxes are (min_lon, min_lat, max_lon, max_lat); polygons are lon/lat rings.
#
# These lines are deliberately approximate — they exist so the app can animate a
# partition, not to assert a surveyed border. Documented in the README.
# ---------------------------------------------------------------------------
SUBDIVISIONS: list[dict[str, Any]] = [
    {
        # Interwar Poland reached well east of today's border; the 1939 partition
        # ran near the Bug. Cutting Ukraine and Belarus north-south reconstructs
        # both the 1939 Polish state and the line that split it.
        "parent": "UKR",
        "pieces": [
            {"id": "UKR-W", "name": "Western Ukraine", "clip": {"box": [21.0, 46.5, 26.7, 52.6]}},
            {"id": "UKR-CRIMEA", "name": "Crimea", "clip": {"box": [32.3, 44.2, 36.7, 46.2]}},
        ],
        "remainder": {"id": "UKR-E", "name": "Eastern Ukraine"},
    },
    {
        "parent": "BLR",
        "pieces": [
            {"id": "BLR-W", "name": "Western Belarus", "clip": {"box": [22.5, 51.0, 27.2, 56.5]}},
        ],
        "remainder": {"id": "BLR-E", "name": "Eastern Belarus"},
    },
    {
        # The Kaliningrad exclave — East Prussia until 1945 — is a detached part of
        # Russia in Natural Earth, so a box cleanly separates it.
        "parent": "RUS",
        "pieces": [
            {"id": "RUS-KGD", "name": "Kaliningrad", "clip": {"box": [19.2, 54.2, 23.0, 55.4]}},
        ],
        "remainder": {"id": "RUS", "name": "Russia"},
    },
    {
        # The 1940 demarcation: occupied north and Atlantic coast, Vichy south-east.
        "parent": "FRA",
        "pieces": [
            {
                "id": "FRA-VICHY",
                "name": "Southern France",
                "clip": {
                    "polygon": [
                        [-1.8, 43.3], [6.9, 43.3], [7.2, 46.4], [5.9, 46.6],
                        [4.2, 46.9], [2.2, 46.6], [0.1, 46.0], [-0.9, 45.0],
                        [-1.8, 43.3],
                    ]
                },
            },
        ],
        "remainder": {"id": "FRA-OCC", "name": "Northern France"},
    },
    {
        # Northern Transylvania, awarded to Hungary in 1940.
        "parent": "ROU",
        "pieces": [
            {"id": "ROU-TRANS-N", "name": "Northern Transylvania", "clip": {"box": [21.5, 46.2, 26.5, 48.4]}},
        ],
        "remainder": {"id": "ROU", "name": "Romania"},
    },
    {
        # Karelia, ceded to the USSR after the Winter War.
        "parent": "FIN",
        "pieces": [
            {"id": "FIN-KARELIA", "name": "Karelia", "clip": {"box": [28.4, 60.2, 32.5, 63.2]}},
        ],
        "remainder": {"id": "FIN", "name": "Finland"},
    },
]


# ---------------------------------------------------------------------------
# Historical city names, keyed by the Natural Earth place name.
# Each entry lists (name, start_year, end_year) with None meaning open-ended.
# ---------------------------------------------------------------------------
HISTORICAL_CITY_NAMES: dict[str, list[tuple[str, int | None, int | None]]] = {
    "Istanbul": [("Byzantium", None, 330), ("Constantinople", 330, 1930), ("Istanbul", 1930, None)],
    "Volgograd": [("Tsaritsyn", None, 1925), ("Stalingrad", 1925, 1961), ("Volgograd", 1961, None)],
    "St. Petersburg": [
        ("St. Petersburg", 1703, 1914), ("Petrograd", 1914, 1924),
        ("Leningrad", 1924, 1991), ("St. Petersburg", 1991, None),
    ],
    "Kaliningrad": [("Königsberg", None, 1946), ("Kaliningrad", 1946, None)],
    "Gdansk": [("Danzig", None, 1945), ("Gdańsk", 1945, None)],
    "Wroclaw": [("Breslau", None, 1945), ("Wrocław", 1945, None)],
    "Oslo": [("Christiania", 1624, 1925), ("Oslo", 1925, None)],
    "Ho Chi Minh City": [("Saigon", None, 1976), ("Ho Chi Minh City", 1976, None)],
    "Jakarta": [("Batavia", 1619, 1942), ("Jakarta", 1942, None)],
    "Mumbai": [("Bombay", None, 1995), ("Mumbai", 1995, None)],
    "Kolkata": [("Calcutta", None, 2001), ("Kolkata", 2001, None)],
    "Chennai": [("Madras", None, 1996), ("Chennai", 1996, None)],
    "Yangon": [("Rangoon", None, 1989), ("Yangon", 1989, None)],
    "Beijing": [("Peking", None, 1949), ("Beijing", 1949, None)],
    "Guangzhou": [("Canton", None, 1949), ("Guangzhou", 1949, None)],
    "Almaty": [("Alma-Ata", 1921, 1993), ("Almaty", 1993, None)],
    "Astana": [("Akmolinsk", None, 1961), ("Tselinograd", 1961, 1992), ("Astana", 1992, None)],
    "Bishkek": [("Frunze", 1926, 1991), ("Bishkek", 1991, None)],
    "Dushanbe": [("Stalinabad", 1929, 1961), ("Dushanbe", 1961, None)],
    "Chisinau": [("Kishinev", None, 1991), ("Chișinău", 1991, None)],
    "Lviv": [("Lemberg", None, 1918), ("Lwów", 1918, 1945), ("Lviv", 1945, None)],
    "Vilnius": [("Wilno", 1920, 1939), ("Vilnius", 1939, None)],
    "Tokyo": [("Edo", None, 1868), ("Tokyo", 1868, None)],
    "Harare": [("Salisbury", 1890, 1982), ("Harare", 1982, None)],
    "Kinshasa": [("Léopoldville", 1881, 1966), ("Kinshasa", 1966, None)],
    "Tbilisi": [("Tiflis", None, 1936), ("Tbilisi", 1936, None)],
}

# Cities that matter to the historical scenarios but that Natural Earth's 110m
# populated-places layer omits.
#
# Note these carry their *modern* names even when the scenarios want the historical
# one: HISTORICAL_CITY_NAMES is applied to these entries too, so Volgograd renders as
# "Stalingrad" on a 1942 map. Adding "Stalingrad" as a separate city instead would
# put two dots on the Volga.
EXTRA_CITIES = [
    {"name": "Volgograd", "lon": 44.52, "lat": 48.72, "iso": "RUS", "rank": 2},
    {"name": "St. Petersburg", "lon": 30.31, "lat": 59.94, "iso": "RUS", "rank": 1},
    {"name": "Kaliningrad", "lon": 20.51, "lat": 54.71, "iso": "RUS", "rank": 3},
    {"name": "Gdansk", "lon": 18.65, "lat": 54.35, "iso": "POL", "rank": 3},
    {"name": "Wroclaw", "lon": 17.04, "lat": 51.11, "iso": "POL", "rank": 3},
    {"name": "Lviv", "lon": 24.03, "lat": 49.84, "iso": "UKR", "rank": 3},
    {"name": "Chisinau", "lon": 28.86, "lat": 47.01, "iso": "MDA", "rank": 3},
    {"name": "Almaty", "lon": 76.89, "lat": 43.24, "iso": "KAZ", "rank": 3},
    {"name": "Guangzhou", "lon": 113.26, "lat": 23.13, "iso": "CHN", "rank": 2},
    {"name": "Chennai", "lon": 80.27, "lat": 13.08, "iso": "IND", "rank": 2},
    {"name": "Ho Chi Minh City", "lon": 106.63, "lat": 10.82, "iso": "VNM", "rank": 2},
    {"name": "Sevastopol", "lon": 33.53, "lat": 44.62, "iso": "UKR", "rank": 3},
    {"name": "Verdun", "lon": 5.38, "lat": 49.16, "iso": "FRA", "rank": 4},
    {"name": "Dunkirk", "lon": 2.38, "lat": 51.04, "iso": "FRA", "rank": 4},
    {"name": "Normandy", "lon": -0.70, "lat": 49.35, "iso": "FRA", "rank": 4},
    {"name": "El Alamein", "lon": 28.95, "lat": 30.83, "iso": "EGY", "rank": 4},
    {"name": "Kursk", "lon": 36.19, "lat": 51.73, "iso": "RUS", "rank": 3},
    {"name": "Smolensk", "lon": 32.05, "lat": 54.78, "iso": "RUS", "rank": 3},
    {"name": "Brest", "lon": 23.70, "lat": 52.10, "iso": "BLR", "rank": 3},
    {"name": "Tobruk", "lon": 23.96, "lat": 32.08, "iso": "LBY", "rank": 4},
    {"name": "Cannae", "lon": 16.13, "lat": 41.30, "iso": "ITA", "rank": 5},
    {"name": "Carthage", "lon": 10.32, "lat": 36.85, "iso": "TUN", "rank": 3},
    {"name": "Alexandria", "lon": 29.92, "lat": 31.20, "iso": "EGY", "rank": 2},
    {"name": "Antioch", "lon": 36.16, "lat": 36.20, "iso": "TUR", "rank": 4},
    {"name": "Thermopylae", "lon": 22.54, "lat": 38.80, "iso": "GRC", "rank": 5},
    {"name": "Austerlitz", "lon": 16.76, "lat": 49.13, "iso": "CZE", "rank": 5},
    {"name": "Waterloo", "lon": 4.40, "lat": 50.68, "iso": "BEL", "rank": 5},
    {"name": "Borodino", "lon": 35.82, "lat": 55.52, "iso": "RUS", "rank": 5},
    {"name": "Trafalgar", "lon": -6.04, "lat": 36.18, "iso": "ESP", "rank": 5},
    {"name": "Gallipoli", "lon": 26.41, "lat": 40.41, "iso": "TUR", "rank": 4},
    {"name": "Ypres", "lon": 2.89, "lat": 50.85, "iso": "BEL", "rank": 5},
    {"name": "Somme", "lon": 2.70, "lat": 50.00, "iso": "FRA", "rank": 5},
]


# ---------------------------------------------------------------------------
# Region presets offered by the New Project wizard.
# ---------------------------------------------------------------------------
REGIONS = [
    {"id": "world", "name": "Modern World", "box": [-180, -60, 180, 84]},
    {"id": "europe", "name": "Europe", "box": [-25, 34, 45, 71]},
    {"id": "asia", "name": "Asia", "box": [26, -11, 150, 78]},
    {"id": "middle_east", "name": "Middle East", "box": [24, 12, 64, 42]},
    {"id": "africa", "name": "Africa", "box": [-19, -36, 52, 38]},
    {"id": "north_america", "name": "North America", "box": [-170, 7, -52, 72]},
    {"id": "south_america", "name": "South America", "box": [-82, -56, -34, 13]},
    {"id": "mediterranean", "name": "Ancient Mediterranean", "box": [-11, 27, 45, 49]},
]


# ---------------------------------------------------------------------------
# Fetching
# ---------------------------------------------------------------------------

def fetch(name: str, url: str) -> dict:
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, f"{name}.geojson")
    if not os.path.exists(path):
        print(f"  downloading {name} …")
        ctx = ssl.create_default_context(cafile="/root/.ccr/ca-bundle.crt") \
            if os.path.exists("/root/.ccr/ca-bundle.crt") else None
        with urllib.request.urlopen(url, context=ctx, timeout=120) as r:
            data = r.read()
        with open(path, "wb") as f:
            f.write(data)
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


# ---------------------------------------------------------------------------
# Geometry helpers
# ---------------------------------------------------------------------------

def clean(geom: BaseGeometry) -> BaseGeometry:
    """Repair self-intersections that would otherwise poison later operations."""
    if not geom.is_valid:
        geom = geom.buffer(0)
    return geom


def clip_region(spec: dict) -> BaseGeometry:
    if "box" in spec:
        return box(*spec["box"])
    return Polygon(spec["polygon"])


def to_rings(geom: BaseGeometry) -> list[list[list[list[float]]]]:
    """Flatten a (Multi)Polygon into [polygon][ring][point][lon, lat], rounded.

    Six decimal places is ~0.1 m at the equator — far beyond what a 110m dataset
    justifies, but it keeps files compact without visible loss.
    """
    if geom.is_empty:
        return []
    polys = list(geom.geoms) if isinstance(geom, MultiPolygon) else [geom]
    out = []
    for p in polys:
        if p.is_empty or not isinstance(p, Polygon):
            continue
        rings = [[[round(x, 6), round(y, 6)] for x, y in p.exterior.coords]]
        for interior in p.interiors:
            rings.append([[round(x, 6), round(y, 6)] for x, y in interior.coords])
        out.append(rings)
    return out


def representative_point(geom: BaseGeometry) -> tuple[float, float]:
    """A label anchor guaranteed to fall inside the territory.

    For multi-part territories the anchor goes in the largest part, so labels
    land on mainland France rather than in the Atlantic between its islands.
    """
    target = geom
    if isinstance(geom, MultiPolygon) and len(geom.geoms) > 1:
        target = max(geom.geoms, key=lambda g: g.area)
    p = target.representative_point()
    return (round(p.x, 6), round(p.y, 6))


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

def build_units(countries: dict) -> list[dict]:
    """Turn country features into territory units, applying subdivisions."""
    subs_by_parent = {s["parent"]: s for s in SUBDIVISIONS}
    units: list[dict] = []

    for feature in countries["features"]:
        props = feature["properties"]
        iso = props.get("ISO_A3") or props.get("ADM0_A3") or ""
        # Natural Earth uses "-99" for entities without an assigned ISO code.
        if iso in ("-99", ""):
            iso = props.get("ADM0_A3", "") or props.get("NAME", "").upper()[:3]
        name = props.get("NAME_LONG") or props.get("NAME") or iso
        geom = clean(shape(feature["geometry"]))
        if geom.is_empty:
            continue

        spec = subs_by_parent.get(iso)
        if spec is None:
            units.append({"id": iso, "name": name, "iso": iso, "geom": geom})
            continue

        leftover = geom
        for piece in spec["pieces"]:
            region = clip_region(piece["clip"])
            cut = clean(geom.intersection(region))
            if cut.is_empty or cut.area <= 0:
                print(f"  ! subdivision {piece['id']} produced nothing; check its clip")
                continue
            units.append({"id": piece["id"], "name": piece["name"], "iso": iso, "geom": cut})
            leftover = clean(leftover.difference(region))

        rem = spec["remainder"]
        if not leftover.is_empty and leftover.area > 0:
            units.append({"id": rem["id"], "name": rem["name"], "iso": iso, "geom": leftover})

    return units


def node_units(units: list[dict]) -> None:
    """Insert missing shared vertices so neighbouring outlines agree exactly.

    Cutting a country introduces a vertex where the cut meets an international
    border — but only on the country being cut. Its neighbour keeps the original
    straight segment, so the two outlines no longer share identical edges and
    `build_borders` cannot pair them: the border silently degrades into two
    overlapping "coastlines". Ukraine cut at 26.7°E next to Belarus cut at 27.2°E
    is exactly this case.

    Fix it globally by walking every ring segment and splicing in any vertex from
    any other territory that lies on it. This repairs T-junctions inherited from
    Natural Earth too, not just the ones our own cuts create.

    Mutates each unit's "geom" in place.
    """
    from shapely.geometry import Point

    vertices: set[tuple[float, float]] = set()
    for u in units:
        for poly in to_rings(u["geom"]):
            for ring in poly:
                for x, y in ring:
                    vertices.add((x, y))

    points = [Point(v) for v in sorted(vertices)]
    tree = STRtree(points)
    # to_rings rounds to 6 decimals, so a vertex can sit up to ~5e-7 off the
    # neighbouring segment. 1e-6 degrees is about 10 cm — comfortably above that
    # rounding error and far below any real feature at 110m scale.
    eps = 1e-6
    inserted = 0

    def node_ring(ring: list[list[float]]) -> list[list[float]]:
        nonlocal inserted
        out: list[list[float]] = []
        for i in range(len(ring) - 1):
            a = (ring[i][0], ring[i][1])
            b = (ring[i + 1][0], ring[i + 1][1])
            out.append(list(a))
            seg = LineString([a, b])
            if seg.length == 0:
                continue
            extra = []
            for j in tree.query(seg.buffer(eps)):
                p = points[int(j)]
                c = (p.x, p.y)
                if c == a or c == b:
                    continue
                if seg.distance(p) > eps:
                    continue
                t = seg.project(p)
                if eps < t < seg.length - eps:
                    extra.append((t, c))
            extra.sort()
            for _, c in extra:
                out.append([c[0], c[1]])
                inserted += 1
        out.append(list(ring[-1]))
        return out

    for u in units:
        polys = []
        for poly in to_rings(u["geom"]):
            noded = [node_ring(r) for r in poly]
            shell = noded[0]
            holes = [h for h in noded[1:] if len(h) >= 4]
            if len(shell) < 4:
                continue
            polys.append(Polygon(shell, holes))
        if polys:
            u["geom"] = clean(unary_union(polys) if len(polys) > 1 else polys[0])

    print(f"  spliced {inserted} shared vertices")


def compute_adjacency(units: list[dict]) -> dict[str, list[str]]:
    """Land neighbours per unit, via an R-tree over slightly buffered geometry."""
    buffered = [u["geom"].buffer(ADJACENCY_SLACK / 2) for u in units]
    tree = STRtree(buffered)
    neighbours: dict[str, list[str]] = {}
    for i, u in enumerate(units):
        hits = tree.query(buffered[i])
        found = set()
        for j in hits:
            j = int(j)
            if j == i:
                continue
            if buffered[i].intersects(buffered[j]):
                found.add(units[j]["id"])
        neighbours[u["id"]] = sorted(found)
    return neighbours


def build_cities(places: dict, units: list[dict]) -> list[dict]:
    """Populated places tagged with the territory unit that contains them."""
    tree = STRtree([u["geom"] for u in units])
    ids = [u["id"] for u in units]

    def locate(lon: float, lat: float) -> str:
        from shapely.geometry import Point
        pt = Point(lon, lat)
        for j in tree.query(pt):
            j = int(j)
            if units[j]["geom"].contains(pt):
                return ids[j]
        # Coastal places can sit just outside a simplified outline; fall back to
        # whichever territory is closest rather than dropping the city.
        best, best_d = "", float("inf")
        for j, u in enumerate(units):
            d = u["geom"].distance(pt)
            if d < best_d:
                best, best_d = ids[j], d
        return best if best_d < 2.0 else ""

    cities: list[dict] = []
    seen: set[str] = set()

    for feature in places["features"]:
        props = feature["properties"]
        name = props.get("NAME") or props.get("NAMEASCII")
        if not name or name in seen:
            continue
        seen.add(name)
        lon, lat = feature["geometry"]["coordinates"][:2]
        # Natural Earth's SCALERANK runs 0 (most prominent) to 10.
        scalerank = int(props.get("SCALERANK", 8) or 8)
        is_capital = str(props.get("FEATURECLA", "")).startswith("Admin-0 capital")
        entry = {
            "id": f"city.{name.lower().replace(' ', '_').replace('.', '')}",
            "name": name,
            "lon": round(float(lon), 5),
            "lat": round(float(lat), 5),
            "unit": locate(float(lon), float(lat)),
            "importance": max(1, min(5, scalerank // 2 + 1)),
            "capital": is_capital,
        }
        if name in HISTORICAL_CITY_NAMES:
            entry["historicalNames"] = [
                {"name": n, "startYear": s, "endYear": e}
                for (n, s, e) in HISTORICAL_CITY_NAMES[name]
            ]
        cities.append(entry)

    for extra in EXTRA_CITIES:
        if extra["name"] in seen:
            continue
        seen.add(extra["name"])
        entry = {
            "id": f"city.{extra['name'].lower().replace(' ', '_').replace('.', '')}",
            "name": extra["name"],
            "lon": extra["lon"],
            "lat": extra["lat"],
            "unit": locate(extra["lon"], extra["lat"]),
            "importance": extra["rank"],
            "capital": False,
        }
        # Extras get the same historical-name treatment as Natural Earth's own
        # places, so Volgograd can render as Stalingrad without a second dot.
        if extra["name"] in HISTORICAL_CITY_NAMES:
            entry["historicalNames"] = [
                {"name": n, "startYear": s, "endYear": e}
                for (n, s, e) in HISTORICAL_CITY_NAMES[extra["name"]]
            ]
        cities.append(entry)

    cities.sort(key=lambda c: (c["importance"], c["name"]))
    return cities


def build_borders(units: list[dict]) -> list[dict]:
    """Derive shared boundaries so the renderer can stroke political borders only.

    Territory units are the atoms of ownership, but their edges are not all real
    borders: the cut that separates Northern Transylvania from the rest of Romania
    must vanish while both halves belong to Romania. So instead of stroking each
    unit's outline, we extract every boundary edge once, note which two units share
    it, and let the renderer decide at draw time — stroke it only when the owners
    differ. Edges belonging to a single unit are coastline.

    Natural Earth's neighbouring polygons share vertices exactly, and shapely's
    intersection/difference preserves that for our own cuts, so plain edge equality
    is enough to pair them up.
    """
    edge_owners: dict[tuple, list[str]] = {}
    for u in units:
        for poly in to_rings(u["geom"]):
            for ring in poly:
                for i in range(len(ring) - 1):
                    a = (ring[i][0], ring[i][1])
                    b = (ring[i + 1][0], ring[i + 1][1])
                    if a == b:
                        continue
                    key = (a, b) if a < b else (b, a)
                    edge_owners.setdefault(key, []).append(u["id"])

    # Group edges by the unordered pair of units that share them.
    groups: dict[tuple[str, str | None], list[tuple]] = {}
    for edge, owners in edge_owners.items():
        uniq = sorted(set(owners))
        if len(uniq) == 1:
            key = (uniq[0], None)
        else:
            key = (uniq[0], uniq[1])
        groups.setdefault(key, []).append(edge)

    borders: list[dict] = []
    for (a, b), edges in groups.items():
        for line in chain_edges(edges):
            borders.append({"a": a, "b": b, "points": [[round(x, 6), round(y, 6)] for x, y in line]})
    return borders


def chain_edges(edges: list[tuple]) -> list[list[tuple[float, float]]]:
    """Stitch unordered segments into the longest possible polylines.

    Fewer, longer polylines mean fewer stroke calls and continuous joins on screen.
    """
    adjacency: dict[tuple, list[tuple]] = {}
    for p, q in edges:
        adjacency.setdefault(p, []).append(q)
        adjacency.setdefault(q, []).append(p)

    unused = {(p, q) if p < q else (q, p) for p, q in edges}
    lines: list[list[tuple]] = []

    def walk(start: tuple) -> list[tuple]:
        line = [start]
        cur = start
        while True:
            nxt = None
            for cand in adjacency.get(cur, ()):
                key = (cur, cand) if cur < cand else (cand, cur)
                if key in unused:
                    nxt = cand
                    unused.discard(key)
                    break
            if nxt is None:
                return line
            line.append(nxt)
            cur = nxt

    # Start from open ends first so chains are not cut in the middle, then mop up
    # any remaining closed loops (islands, enclaves).
    endpoints = [p for p, nbrs in adjacency.items() if len(nbrs) == 1]
    for p in endpoints:
        if any(((p, q) if p < q else (q, p)) in unused for q in adjacency[p]):
            line = walk(p)
            if len(line) > 1:
                lines.append(line)
    while unused:
        p = next(iter(unused))[0]
        line = walk(p)
        if len(line) > 1:
            lines.append(line)
        else:
            unused.discard(next(iter(unused)))
    return lines


def simplify_line(points: list[list[float]], tol: float) -> list[list[float]]:
    """Douglas–Peucker on an open polyline."""
    if tol <= 0 or len(points) < 3:
        return points

    def rdp(pts: list[list[float]]) -> list[list[float]]:
        if len(pts) < 3:
            return pts
        x0, y0 = pts[0]
        x1, y1 = pts[-1]
        dx, dy = x1 - x0, y1 - y0
        norm = math.hypot(dx, dy)
        worst_i, worst_d = 0, -1.0
        for i in range(1, len(pts) - 1):
            px, py = pts[i]
            if norm == 0:
                d = math.hypot(px - x0, py - y0)
            else:
                d = abs(dy * px - dx * py + x1 * y0 - y1 * x0) / norm
            if d > worst_d:
                worst_i, worst_d = i, d
        if worst_d <= tol:
            return [pts[0], pts[-1]]
        return rdp(pts[:worst_i + 1])[:-1] + rdp(pts[worst_i:])

    return rdp(points)


def write_json(path: str, payload: Any) -> None:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(payload, f, separators=(",", ":"), ensure_ascii=False)
    size = os.path.getsize(path)
    print(f"  {os.path.basename(path):<24} {size/1024:8.1f} KB")


def main() -> int:
    os.makedirs(OUT, exist_ok=True)

    print("Fetching Natural Earth 110m …")
    countries = fetch("countries", SOURCES["countries"])
    places = fetch("places", SOURCES["places"])

    print("Building territory units …")
    units = build_units(countries)
    print(f"  {len(units)} units")

    print("Noding shared vertices …")
    node_units(units)

    dupes = {u["id"] for u in units if [x["id"] for x in units].count(u["id"]) > 1}
    if dupes:
        print(f"  ! duplicate unit ids: {sorted(dupes)}", file=sys.stderr)
        return 1

    print("Computing adjacency …")
    neighbours = compute_adjacency(units)

    print("Writing geometry …")
    for lod, tol in enumerate(LOD_TOLERANCE):
        geom_out: dict[str, Any] = {}
        for u in units:
            g = u["geom"] if tol == 0 else clean(u["geom"].simplify(tol, preserve_topology=True))
            rings = to_rings(g)
            # A tiny island can vanish entirely at a coarse tolerance; fall back to
            # the previous level rather than dropping the territory off the map.
            if not rings:
                rings = to_rings(u["geom"].simplify(tol / 4, preserve_topology=True))
            if not rings:
                rings = to_rings(u["geom"])
            geom_out[u["id"]] = rings
        write_json(os.path.join(OUT, f"geometry-lod{lod}.json"), geom_out)

    print("Extracting borders …")
    borders = build_borders(units)
    coast = sum(1 for b in borders if b["b"] is None)
    print(f"  {len(borders)} polylines ({coast} coastline, {len(borders) - coast} shared)")
    for lod, tol in enumerate(LOD_TOLERANCE):
        simplified = []
        for b in borders:
            pts = b["points"] if tol == 0 else simplify_line(b["points"], tol)
            if len(pts) < 2:
                continue
            simplified.append({"a": b["a"], "b": b["b"], "points": pts})
        write_json(os.path.join(OUT, f"borders-lod{lod}.json"), simplified)

    print("Writing territories …")
    territories = []
    for u in units:
        minx, miny, maxx, maxy = u["geom"].bounds
        cx, cy = representative_point(u["geom"])
        territories.append({
            "id": u["id"],
            "name": u["name"],
            "iso": u["iso"],
            "anchor": [cx, cy],
            "bbox": [round(minx, 5), round(miny, 5), round(maxx, 5), round(maxy, 5)],
            "area": round(u["geom"].area, 5),
            "neighbours": neighbours[u["id"]],
        })
    territories.sort(key=lambda t: t["id"])
    write_json(os.path.join(OUT, "territories.json"), territories)

    print("Writing cities …")
    cities = build_cities(places, units)
    write_json(os.path.join(OUT, "cities.json"), cities)
    print(f"  {len(cities)} cities")

    print("Writing regions …")
    write_json(os.path.join(OUT, "regions.json"), REGIONS)

    print("Done.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
