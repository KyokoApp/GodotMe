#!/usr/bin/env python3
"""Build REGION "Yaros" from its declarative spec.

The region is DATA, not a scene: `tools/region/yaros_spec.json` says where the
valleys, terraces, roads, water, villages and markers are, and this script turns
that into `game/game/world/regions/yaros.json` - the file the game reads.

Three things are deliberate:

  * deterministic - the spec carries a seed, so building twice writes the same
    bytes (git stays quiet, and a bug is reproducible);
  * validating - reachability, trapped tiles, cliff steps, road length and
    decoration density are checked HERE, before a pack is built. A region that
    fails validation is not written;
  * small - the grids are packed as bytes and base64'd, decorations are integer
    quadruples. Yaros is 192x192 tiles and still weighs ~200 KB as JSON.

    python3 tools/build_region.py                 # build + validate
    python3 tools/build_region.py --report        # validate an existing build
    python3 tools/build_region.py --seed 7        # experiment, do not ship

Tiles are 1 m. `height` is the terrace level (0..5); the world lifts a level by
`level_h` metres (1.8 m, see DESIGN_NOTES 20.x). `structure` packs a code in the
low nibble and a direction in the high nibble (0 = +x, 1 = +y, 2 = -x, 3 = -y).
"""

from __future__ import annotations

import argparse
import base64
import json
import math
import os
import sys
from collections import deque

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = os.path.join(HERE, "region", "yaros_spec.json")
OUT = os.path.join(HERE, "..", "game", "game", "world", "regions", "yaros.json")

# --- terrain ids (must match RegionData.gd) --------------------------------
T_GRASS, T_TALL, T_DIRT, T_ROCK, T_SAND = 0, 1, 2, 3, 4
T_MUD, T_SNOW, T_SHALLOW, T_DEEP, T_WOOD, T_STONE = 5, 6, 7, 8, 9, 10

WATER = (T_SHALLOW, T_DEEP)
WALKABLE_TERRAIN = (T_GRASS, T_TALL, T_DIRT, T_ROCK, T_SAND, T_MUD, T_SNOW,
                    T_WOOD, T_STONE)

# --- structure ids ---------------------------------------------------------
S_NONE, S_STAIR, S_BRIDGE, S_FENCE, S_WALL, S_GATE, S_DOOR, S_RAMP = range(8)
BLOCKING_STRUCT = (S_FENCE, S_WALL, S_GATE, S_DOOR)


def enc_struct(code: int, direction: int = 0) -> int:
    return (code & 0x0F) | ((direction & 0x0F) << 4)


def struct_code(value: int) -> int:
    return value & 0x0F


def struct_dir(value: int) -> int:
    return (value >> 4) & 0x0F


# --------------------------------------------------------------- helpers -----
def hash01(x: int, y: int, seed: int) -> float:
    n = (x * 374761393 + y * 668265263 + seed * 2246822519) & 0xFFFFFFFF
    n = (n ^ (n >> 13)) * 1274126177 & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFFFFFF) / 0xFFFFFFFF


def smooth_noise(x: float, y: float, seed: int, scale: float = 1.0) -> float:
    """Value noise on the integer lattice, smoothstep interpolated."""
    x *= scale
    y *= scale
    x0, y0 = math.floor(x), math.floor(y)
    fx, fy = x - x0, y - y0
    fx = fx * fx * (3 - 2 * fx)
    fy = fy * fy * (3 - 2 * fy)
    a = hash01(int(x0), int(y0), seed)
    b = hash01(int(x0) + 1, int(y0), seed)
    c = hash01(int(x0), int(y0) + 1, seed)
    d = hash01(int(x0) + 1, int(y0) + 1, seed)
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def chaikin(points: list, rounds: int = 3) -> list:
    """Corner-cutting: hand-written waypoints become a road that curves."""
    pts = [(float(p[0]), float(p[1])) for p in points]
    for _ in range(rounds):
        out = [pts[0]]
        for i in range(len(pts) - 1):
            ax, ay = pts[i]
            bx, by = pts[i + 1]
            out.append((ax * 0.75 + bx * 0.25, ay * 0.75 + by * 0.25))
            out.append((ax * 0.25 + bx * 0.75, ay * 0.25 + by * 0.75))
        out.append(pts[-1])
        pts = out
    return pts


def polyline_length(points: list) -> float:
    total = 0.0
    for i in range(len(points) - 1):
        total += math.hypot(points[i + 1][0] - points[i][0],
                            points[i + 1][1] - points[i][1])
    return total


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


# ------------------------------------------------------------------ grid -----
class Grid:
    def __init__(self, w: int, h: int) -> None:
        self.w, self.h = w, h
        self.height = [[0] * w for _ in range(h)]
        self.terrain = [[T_GRASS] * w for _ in range(h)]
        self.struct = [[0] * w for _ in range(h)]

    def inside(self, x: int, y: int) -> bool:
        return 0 <= x < self.w and 0 <= y < self.h

    def rect_tiles(self, rect):
        """Yield (tx, ty) - x first, the same order as every marker in the spec."""
        x, y, w, h = rect
        for ty in range(max(0, y), min(self.h, y + h)):
            for tx in range(max(0, x), min(self.w, x + w)):
                yield tx, ty

    def block_tile(self, x: int, y: int, code: int = S_WALL, direction: int = 0):
        if self.inside(x, y):
            self.struct[y][x] = enc_struct(code, direction)

    def nearest_walkable(self, x: int, y: int, radius: int = 6):
        best = None
        best_d = 1e9
        for dy in range(-radius, radius + 1):
            for dx in range(-radius, radius + 1):
                tx, ty = x + dx, y + dy
                if not self.inside(tx, ty):
                    continue
                if self.terrain[ty][tx] in WATER:
                    continue
                d = dx * dx + dy * dy
                if d < best_d:
                    best_d = d
                    best = (tx, ty)
        return best


# ------------------------------------------------------------- movement ------
def walkable(g: Grid, x: int, y: int) -> bool:
    if not g.inside(x, y):
        return False
    code = struct_code(g.struct[y][x])
    if code in BLOCKING_STRUCT:
        return False
    if code == S_BRIDGE:
        return True          # the deck carries the road over the water
    if g.height[y][x] >= 5:
        return False         # the snow summits are scenery, not a level
    if g.terrain[y][x] == T_SHALLOW:
        return code == S_RAMP   # only a marked ford / stepping stones
    return g.terrain[y][x] in WALKABLE_TERRAIN


def step_ok(g: Grid, ax: int, ay: int, bx: int, by: int) -> bool:
    """One level is a bank the knight walks up (the mesh draws it as a slope);
    two levels is a cliff, which no amount of thumb-stick climbs."""
    if not (walkable(g, ax, ay) and walkable(g, bx, by)):
        return False
    dh = abs(g.height[by][bx] - g.height[ay][ax])
    if dh <= 1:
        return True
    if dh == 2:
        # a stone flight is the one way up a real cliff: it has landings
        code_a = struct_code(g.struct[ay][ax])
        code_b = struct_code(g.struct[by][bx])
        return code_a == S_STAIR or code_b == S_STAIR
    return False


def flood(g: Grid, start) -> "set[tuple[int, int]]":
    seen = {start}
    q = deque([start])
    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if (nx, ny) in seen:
                continue
            if step_ok(g, x, y, nx, ny):
                seen.add((nx, ny))
                q.append((nx, ny))
    return seen


# ------------------------------------------------------------------ build ----
def profile_height(raw: list, hs: list, px: float, py: float) -> float:
    """Height of the road at (px, py): the nearest point on the raw waypoint
    polyline, interpolated between the two waypoints that own it. This is what
    turns "village at 0, forest at 1" into a staircase that steps once."""
    best_d = 1e18
    best_h = float(hs[0])
    for i in range(len(raw) - 1):
        ax, ay = raw[i]
        bx, by = raw[i + 1]
        vx, vy = bx - ax, by - ay
        l2 = vx * vx + vy * vy
        t = 0.0 if l2 == 0.0 else max(0.0, min(1.0, ((px - ax) * vx + (py - ay) * vy) / l2))
        cx, cy = ax + vx * t, ay + vy * t
        d = (px - cx) ** 2 + (py - cy) ** 2
        if d < best_d:
            best_d = d
            best_h = lerp(hs[i], hs[i + 1], t)
    return best_h


def build(spec: dict):
    w, h = int(spec["width"]), int(spec["height"])
    seed = int(spec["seed"])
    g = Grid(w, h)

    # 1. base grass with a little long grass
    for y in range(h):
        for x in range(w):
            g.terrain[y][x] = T_GRASS if hash01(x, y, seed) > 0.18 else T_TALL

    # 2. terraces: rectangles with an organic edge
    for ter in spec["terraces"]:
        x, y, tw, th = ter["rect"]
        level = int(ter["height"])
        wobble = int(ter.get("wobble", 3))
        edge = float(ter.get("edge", 0.55))
        for tx, ty in g.rect_tiles(ter["rect"]):
            # distance into the rectangle, in tiles
            d = min(tx - x, ty - y, x + tw - 1 - tx, y + th - 1 - ty)
            if wobble > 0 and d < wobble:
                noise = smooth_noise(tx, ty, seed + 11, 0.7)
                if noise > edge + 0.12 * d / max(1, wobble):
                    continue
            g.height[ty][tx] = level

    # 3. mountain rim: the world never shows an empty edge
    ring = int(spec.get("edge_ring", 7))
    for y in range(h):
        for x in range(w):
            d = min(x, y, w - 1 - x, h - 1 - y)
            if d < ring:
                n = smooth_noise(x, y, seed + 21, 0.55)
                g.height[y][x] = 5 if d < ring - 3 else (5 if n > 0.30 else 4)
                g.terrain[y][x] = T_SNOW if g.height[y][x] >= 5 else T_ROCK
                g.struct[y][x] = enc_struct(S_WALL)

    # 4. water: lake, then the river carved north to south
    lake = spec["water"]["lake"]
    cx, cy, rx, ry = lake["centre"][0], lake["centre"][1], lake["rx"], lake["ry"]
    for y in range(h):
        for x in range(w):
            n = smooth_noise(x, y, seed + 31, 0.9) - 0.5
            d = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 + n * 0.18
            if d < 0.80:
                g.height[y][x] = int(lake["level"])
                g.terrain[y][x] = T_DEEP if d < 0.52 else T_SHALLOW
            elif d < 1.18:
                g.height[y][x] = int(lake["level"])
                g.terrain[y][x] = T_SAND if d < 1.02 else T_GRASS

    for isl in spec.get("islands", []):
        icx, icy = isl["at"]
        irx, iry = isl["rx"], isl["ry"]
        for y in range(h):
            for x in range(w):
                n = smooth_noise(x, y, seed + 33, 1.1) - 0.5
                d = ((x - icx) / irx) ** 2 + ((y - icy) / iry) ** 2 + n * 0.25
                if d < 1.0:
                    g.height[y][x] = int(isl.get("height", 1))
                    g.terrain[y][x] = int(isl.get("terrain", T_GRASS))
                elif d < 1.35 and g.terrain[y][x] in WATER:
                    g.terrain[y][x] = T_SAND

    river = spec["water"]["river"]
    pts = chaikin([(p[0], p[1]) for p in river["points"]], 3)
    width = float(river.get("width", 5.0))
    level = int(river.get("level", 0))
    # walk the curve and stamp a channel
    steps = int(polyline_length(pts) / 0.4) + 1
    for i in range(steps + 1):
        t = i / steps
        # position along the polyline by arc length
        want = t * polyline_length(pts)
        acc = 0.0
        px, py = pts[0]
        for k in range(len(pts) - 1):
            seg = math.hypot(pts[k + 1][0] - pts[k][0], pts[k + 1][1] - pts[k][1])
            if acc + seg >= want or k == len(pts) - 2:
                f = 0.0 if seg == 0 else (want - acc) / seg
                px = lerp(pts[k][0], pts[k + 1][0], f)
                py = lerp(pts[k][1], pts[k + 1][1], f)
                break
            acc += seg
        for oy in range(-int(width) - 2, int(width) + 3):
            for ox in range(-int(width) - 2, int(width) + 3):
                tx, ty = int(round(px + ox)), int(round(py + oy))
                if not g.inside(tx, ty):
                    continue
                d = math.hypot(tx - px, ty - py)
                wob = 1.4 * (smooth_noise(tx, ty, seed + 41, 0.8) - 0.5)
                d += wob
                if d < width * 0.5 - 0.6:
                    g.height[ty][tx] = level
                    g.terrain[ty][tx] = T_DEEP
                elif d < width * 0.5 + 0.9:
                    g.height[ty][tx] = level
                    g.terrain[ty][tx] = T_SHALLOW
                elif d < width * 0.5 + 2.4 and g.terrain[ty][tx] not in WATER:
                    g.terrain[ty][tx] = T_MUD

    # 4b. stepping stones / shallows: water the player may wade through
    for path in spec.get("shallow_paths", []):
        pts_s = chaikin([(p[0], p[1]) for p in path["points"]], 2)
        half = float(path.get("width", 2.0)) * 0.5
        steps = int(polyline_length(pts_s) / 0.4) + 1
        for i in range(steps + 1):
            t = i / max(1, steps)
            want = t * polyline_length(pts_s)
            acc = 0.0
            px, py = pts_s[0]
            for k in range(len(pts_s) - 1):
                seg = math.hypot(pts_s[k + 1][0] - pts_s[k][0], pts_s[k + 1][1] - pts_s[k][1])
                if acc + seg >= want or k == len(pts_s) - 2:
                    f = 0.0 if seg == 0 else (want - acc) / seg
                    px = lerp(pts_s[k][0], pts_s[k + 1][0], f)
                    py = lerp(pts_s[k][1], pts_s[k + 1][1], f)
                    break
                acc += seg
            for oy in range(-2, 3):
                for ox in range(-2, 3):
                    tx, ty = int(round(px + ox)), int(round(py + oy))
                    if not g.inside(tx, ty):
                        continue
                    if math.hypot(tx - px, ty - py) > half + 0.2:
                        continue
                    if g.terrain[ty][tx] in WATER:
                        g.terrain[ty][tx] = T_SHALLOW
                        g.struct[ty][tx] = enc_struct(S_RAMP)

    # 4c. biome surfaces: the plateau is ROCK, the lake shore is SAND, the peaks
    # are SNOW. Heights alone read as "a green field with steps"; the surface
    # under the boots is what makes a stone terrace feel like a stone terrace.
    biome_terrain = {
        "village": (T_GRASS, T_TALL),
        "fields": (T_TALL, T_DIRT),
        "forest": (T_GRASS, T_TALL),
        "river": (T_GRASS, T_MUD),
        "stone": (T_ROCK, T_STONE),
        "landmark": (T_STONE, T_ROCK),
        "cave": (T_ROCK, T_ROCK),
        "lake": (T_GRASS, T_TALL),
        "peak": (T_ROCK, T_SNOW),
    }
    for zone in spec["zones"]:
        if zone.get("kind") == "road":
            continue
        pair = biome_terrain.get(zone.get("kind", ""), (T_GRASS, T_TALL))
        for tx, ty in g.rect_tiles(zone["rect"]):
            if g.terrain[ty][tx] in WATER or struct_code(g.struct[ty][tx]) == S_WALL:
                continue
            n = smooth_noise(tx, ty, seed + 51, 0.42)
            h = g.height[ty][tx]
            if zone.get("kind") == "peak" and h >= 4:
                g.terrain[ty][tx] = T_SNOW if n > 0.35 else T_ROCK
            elif zone.get("kind") == "fields":
                # ploughed rows: dirt lines through the tall grass
                g.terrain[ty][tx] = T_DIRT if (tx % 7 < 2) else T_TALL
            elif zone.get("kind") == "village":
                near = math.hypot(tx - spec["villages"][0]["at"][0],
                                  ty - spec["villages"][0]["at"][1]) < 7.0
                g.terrain[ty][tx] = T_DIRT if near and n > 0.45 else (
                    T_TALL if n > 0.62 else T_GRASS)
            elif h >= 4:
                g.terrain[ty][tx] = pair[1] if n > 0.55 else pair[0]
            else:
                g.terrain[ty][tx] = pair[1] if n > 0.80 else pair[0]

    # 5. roads: a smoothed corridor whose height follows the waypoint profile.
    # Two legs of the same road can pass close to each other (switchbacks), so
    # every tile remembers the CLOSEST station that touched it - "last writer
    # wins" left a mountain road that changed height twice at the same spot.
    road_best: dict = {}
    built_routes = []
    for route in spec["routes"]:
        raw = [(float(p[0]), float(p[1])) for p in route["points"]]
        hs = [int(p[2]) for p in route["points"]]
        curve = chaikin(raw, int(route.get("smooth", 3)))
        radius = float(route.get("width", 3.0)) * 0.5
        seg_len = [math.hypot(raw[i + 1][0] - raw[i][0], raw[i + 1][1] - raw[i][1])
                   for i in range(len(raw) - 1)]
        total = sum(seg_len) or 1.0
        stations = []
        acc = 0.0
        for i in range(len(curve) - 1):
            ax, ay = curve[i]
            bx, by = curve[i + 1]
            seg = math.hypot(bx - ax, by - ay)
            n = max(1, int(seg / 0.35))
            for k in range(n):
                f = k / n
                stations.append((lerp(ax, bx, f), lerp(ay, by, f), acc + seg * f))
            acc += seg
        stations.append((curve[-1][0], curve[-1][1], acc))
        smooth_len = acc or 1.0
        for sx, sy, s_along in stations:
            frac = max(0.0, min(1.0, s_along / smooth_len))
            run = 0.0
            target = hs[-1]
            for i in range(len(raw) - 1):
                share = seg_len[i] / total
                if frac <= run + share + 1e-9:
                    f = 0.0 if share <= 0.0 else max(0.0, min(1.0, (frac - run) / share))
                    target = int(round(lerp(hs[i], hs[i + 1], f)))
                    break
                run += share
            span = int(math.ceil(radius)) + 1
            for oy in range(-span, span + 1):
                for ox in range(-span, span + 1):
                    tx, ty = int(round(sx + ox)), int(round(sy + oy))
                    if not g.inside(tx, ty):
                        continue
                    d = math.hypot(tx - sx, ty - sy)
                    if d > radius:
                        continue
                    key = (tx, ty)
                    prev = road_best.get(key)
                    if prev is None or d < prev[0] - 0.001:
                        road_best[key] = (d, target)
        built_routes.append({"id": route["id"], "length": round(acc, 1),
                             "points": [(round(p[0], 2), round(p[1], 2)) for p in raw]})

    for (tx, ty), (_d, target) in road_best.items():
        here = g.terrain[ty][tx]
        if here in WATER:
            g.struct[ty][tx] = enc_struct(S_BRIDGE)
            # the deck sits at the road's own height, so the approach tile and
            # the bridge are the same step - otherwise the bridge is an island
            g.height[ty][tx] = max(target, level + 1)
            continue
        g.height[ty][tx] = target
        g.terrain[ty][tx] = T_DIRT
        if struct_code(g.struct[ty][tx]) == S_BRIDGE:
            continue
        g.struct[ty][tx] = 0

    # 5b. blend the shoulders: within three tiles the ground may stand at most
    # one level above the road. Without this the road is a two-level slot in the
    # plateau, and the meadow beside it has no way in.
    for (tx, ty), (dist, target) in road_best.items():
        for oy in range(-3, 4):
            for ox in range(-3, 4):
                qx, qy = tx + ox, ty + oy
                if not g.inside(qx, qy):
                    continue
                if math.hypot(ox, oy) > 3.2:
                    continue
                if g.terrain[qy][qx] in WATER:
                    continue
                if g.height[qy][qx] > target + 1:
                    g.height[qy][qx] = target + 1

    # 6. home plot: a flat meadow the player owns (house + garden in step 5)
    plot = spec["home_plot"]
    hx, hy, hw, hh = plot["rect"]
    for tx, ty in g.rect_tiles(plot["rect"]):
        g.height[ty][tx] = int(plot.get("height", 0))
        g.terrain[ty][tx] = T_GRASS
        g.struct[ty][tx] = 0

    # 7. cleaning: no single-tile spikes, no step taller than 2 levels
    for _ in range(3):
        for y in range(1, h - 1):
            for x in range(1, w - 1):
                hn = [g.height[y + dy][x + dx] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))]
                here = g.height[y][x]
                if all(v != here for v in hn):
                    counts = {}
                    for v in hn:
                        counts[v] = counts.get(v, 0) + 1
                    g.height[y][x] = max(counts, key=lambda k: counts[k])
    for y in range(h):
        for x in range(w):
            for dx, dy in ((1, 0), (0, 1)):
                nx, ny = x + dx, y + dy
                if not g.inside(nx, ny):
                    continue
                diff = g.height[y][x] - g.height[ny][nx]
                if abs(diff) > 2:
                    g.height[y][x] = (g.height[y][x] + g.height[ny][nx]) // 2
                    g.height[ny][nx] = g.height[y][x]

    # 7b. terrace the tall jumps: the mountain rim must come down in steps.
    # Only the rim is touched - the plateau's road cuts are deliberate, and a
    # global pass here ground the whole east half down to the valley floor.
    for _ in range(12):
        changed = False
        for y in range(h):
            for x in range(w):
                if min(x, y, w - 1 - x, h - 1 - y) > ring + 8:
                    continue
                here = g.height[y][x]
                for dx, dy in ((1, 0), (0, 1), (-1, 0), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if not g.inside(nx, ny):
                        continue
                    other = g.height[ny][nx]
                    if here - other > 2:
                        g.height[y][x] = other + 2
                        here = other + 2
                        changed = True
        if not changed:
            break

    # 7c. the rim is a wall of rock: the strip just inside it is scenery too,
    # otherwise it becomes a walkable ledge nobody can ever reach
    for y in range(h):
        for x in range(w):
            d = min(x, y, w - 1 - x, h - 1 - y)
            if d < ring + 2 and g.height[y][x] >= 1:
                g.struct[y][x] = enc_struct(S_WALL)

    # 8. stairs: only the ones named in the spec. Natural one-level banks are
    # slopes now (see step_ok), so a stair is a deliberate landmark - a stone
    # flight where the road climbs the plateau - not a patch over a bad bank.
    for acc in spec.get("stairs", []):
        x, y = int(acc["at"][0]), int(acc["at"][1])
        d = int(acc.get("dir", 1))
        dx, dy = ((1, 0), (0, 1), (-1, 0), (0, -1))[d]
        for k in range(int(acc.get("run", 3))):
            tx, ty = x + dx * k, y + dy * k
            if not g.inside(tx, ty):
                continue
            g.struct[ty][tx] = enc_struct(S_STAIR, d)
            g.terrain[ty][tx] = T_STONE if acc.get("stone", False) else T_DIRT

    # 9. structures: fences around the fields, the mountain gate, house walls
    for fence in spec.get("fences", []):
        x, y, fw, fh = fence["rect"]
        gap = max(2, fw // 4)
        gate_from = x + fw // 2 - gap // 2
        for tx in range(x, x + fw):
            if gate_from <= tx < gate_from + gap:
                continue      # the garden gate: a fenced field must not trap
            for ty in (y, y + fh - 1):
                if g.inside(tx, ty) and g.terrain[ty][tx] != T_DIRT:
                    g.block_tile(tx, ty, S_FENCE)
        for ty in range(y, y + fh):
            for tx in (x, x + fw - 1):
                if g.inside(tx, ty) and g.terrain[ty][tx] != T_DIRT:
                    g.block_tile(tx, ty, S_FENCE)
    gate = spec.get("gate")
    if gate:
        gx, gy = int(gate["at"][0]), int(gate["at"][1])
        for tx in range(gx - 1, gx + 2):
            g.block_tile(tx, gy, S_GATE)

    # a broken bridge: deck over the river with the middle missing
    broken = spec.get("broken_bridge")
    if broken:
        bx, by = int(broken["at"][0]), int(broken["at"][1])
        half = int(broken.get("span", 9)) // 2
        for k in range(-half, half + 1):
            tx = bx + k
            if not g.inside(tx, by):
                continue
            g.height[by][tx] = max(g.height[by][tx], 1)
            g.terrain[by][tx] = T_WOOD if abs(k) < 2 else T_DIRT
            g.struct[by][tx] = enc_struct(S_BRIDGE)
        g.block_tile(bx, by, S_WALL)   # the missing planks: closed for step 2

    # 10. connectivity: every terrace gets a stair to the rest of the world
    start = (int(spec["player_start"][0]), int(spec["player_start"][1]))
    spec["_connectors"] = connect_pockets(g, start)
    return g, built_routes


# -------------------------------------------------------------- connectors ---
def connect_pockets(g: Grid, start, rounds: int = 400) -> list:
    """Join every walkable pocket to the main network, honestly.

    The region is designed by hand, but a hand-designed 192x192 map WILL leave
    the odd terrace cut off - a two-level bank between two meadows looks fine
    and traps the player. Instead of loosening the validation, the builder makes
    the shortest honest connection, in this order:

      1. a stair on the low side where the bank is one or two levels;
      2. otherwise carve the pocket's own edge tile down to two levels above the
         neighbour it meets and put the stair there - the terrace becomes a
         lookout with steps, not a hole in the world;
      3. if the pocket touches nothing but water or a wall, it was never a place
         to stand: it becomes rock, which the movement rules already refuse.

    Two limits used to hide pockets for good: the loop returned on the first
    pocket it could not join, and it stopped after 48 connections. Both are gone;
    every round works on the largest remaining pocket, so the count can only go
    down. Returns the (x, y) of every stair it placed.
    """
    made = []
    for _ in range(rounds):
        reach = flood(g, start)
        pockets = []
        seen = set()
        for y in range(g.h):
            for x in range(g.w):
                if (x, y) in seen or (x, y) in reach or not walkable(g, x, y):
                    continue
                comp = flood(g, (x, y))
                seen |= comp
                pockets.append(comp)
        if not pockets:
            return made
        pockets.sort(key=len, reverse=True)
        pocket = pockets[0]
        easy = []
        hard = []
        for (px, py) in pocket:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                qx, qy = px + dx, py + dy
                if not g.inside(qx, qy) or (qx, qy) not in reach:
                    continue
                if g.terrain[qy][qx] in WATER:
                    continue
                dh = abs(g.height[py][px] - g.height[qy][qx])
                if dh <= 2:
                    low_x, low_y = (qx, qy) if g.height[py][px] > g.height[qy][qx] else (px, py)
                    if struct_code(g.struct[low_y][low_x]) not in BLOCKING_STRUCT:
                        easy.append((dh, px, py, qx, qy, dx, dy))
                hard.append((dh, px, py, qx, qy, dx, dy))
        if easy:
            easy.sort()
            _cost, px, py, qx, qy, dx, dy = easy[0]
            if g.height[py][px] > g.height[qy][qx]:
                low_x, low_y = qx, qy
                high_dx, high_dy = -dx, -dy
            else:
                low_x, low_y = px, py
                high_dx, high_dy = dx, dy
            direction = ((1, 0), (0, 1), (-1, 0), (0, -1)).index((high_dx, high_dy))
            g.struct[low_y][low_x] = enc_struct(S_STAIR, direction)
            if g.terrain[low_y][low_x] == T_DIRT:
                g.terrain[low_y][low_x] = T_STONE
            made.append((low_x, low_y))
            continue
        if hard:
            hard.sort()
            _dh, px, py, qx, qy, _dx, _dy = hard[0]
            # the pocket's own edge tile becomes the high landing, exactly two
            # levels above the neighbour it steps down to
            g.height[py][px] = min(4, g.height[qy][qx] + 2)
            to_low = (qx - px, qy - py)
            direction = ((1, 0), (0, 1), (-1, 0), (0, -1)).index(to_low)
            g.struct[py][px] = enc_struct(S_STAIR, direction)
            if g.terrain[py][px] in WATER:
                g.terrain[py][px] = T_STONE
            made.append((px, py))
            continue
        # Nothing but water and walls around it: never a place to stand. Rock
        # would not do - rock is walkable ground in this world - so the pocket
        # becomes deep water, and its structure goes with it: a lone plank of the
        # broken bridge must not keep the movement rule calling it a deck.
        for (px, py) in pocket:
            g.terrain[py][px] = T_DEEP
            if struct_code(g.struct[py][px]) == S_BRIDGE:
                g.struct[py][px] = enc_struct(S_NONE)
    return made


# ------------------------------------------------------------- decoration ----
PROP_KINDS = ["pine", "oak", "bush", "rock", "cottage", "flowers", "reeds",
              "stump", "sign", "torch", "tower", "gate", "well", "dock"]

# radius used by the character controller; the builder keeps props off the road
PROP_RADIUS = {"pine": 0.55, "oak": 0.85, "bush": 0.55, "rock": 0.7,
               "cottage": 2.2, "flowers": 0.0, "reeds": 0.0, "stump": 0.45,
               "sign": 0.25, "torch": 0.25, "tower": 3.2, "gate": 3.0,
               "well": 1.0, "dock": 1.5}


def shore_distance(g: Grid, x: int, y: int, radius: int = 4) -> int:
    if g.terrain[y][x] in WATER:
        return 0
    for r in range(1, radius + 1):
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                tx, ty = x + dx, y + dy
                if g.inside(tx, ty) and g.terrain[ty][tx] in WATER:
                    return r
    return radius + 1


def scatter(g: Grid, spec: dict) -> list:
    seed = int(spec["seed"])
    decor = []
    used = set()

    def near_used(x, y, gap):
        for ux, uy in used:
            if abs(ux - x) <= gap and abs(uy - y) <= gap:
                return True
        return False

    landmarks = [(int(m["at"][0]), int(m["at"][1])) for m in spec["markers"]]
    home = spec["home_plot"]["rect"]
    home_tiles = set(g.rect_tiles(home))
    zone_of = zone_lookup(g, spec)

    for y in range(2, g.h - 2):
        for x in range(2, g.w - 2):
            if g.terrain[y][x] in WATER:
                continue
            code = struct_code(g.struct[y][x])
            if code != S_NONE:
                continue
            if g.terrain[y][x] == T_DIRT:
                # keep the road walkable: nothing stands on it
                continue
            if any(g.inside(x + dx, y + dy) and g.terrain[y + dy][x + dx] == T_DIRT
                   for dx in (-2, -1, 0, 1, 2) for dy in (-2, -1, 0, 1, 2)):
                continue
            if (x, y) in home_tiles:
                continue
            zone = zone_of(x, y)
            r = hash01(x, y, seed + 101)
            n = smooth_noise(x, y, seed + 102, 0.45)
            kind = None
            edge = shore_distance(g, x, y)
            if zone in ("Danau Cermin",) and edge <= 2 and r < 0.30:
                kind = "reeds"
            elif zone == "Hutan Pinus":
                if n > 0.42 and r < 0.55:
                    kind = "pine" if r < 0.42 else "bush"
                elif r > 0.93:
                    kind = "stump"
                elif r > 0.86:
                    kind = "flowers"
            elif zone in ("Dataran Batu", "Menara Penjaga"):
                if g.terrain[y][x] in (T_ROCK, T_STONE):
                    kind = "rock" if r < 0.20 else ("pine" if n > 0.55 and r < 0.28 else None)
                elif r < 0.16:
                    kind = "bush"
            elif zone == "Pos Gunung":
                if n > 0.45 and r < 0.30:
                    kind = "pine"
                elif r < 0.10:
                    kind = "rock"
            elif zone == "Lembah Senja":
                if n > 0.62 and r < 0.15:
                    kind = "oak"
                elif r < 0.11:
                    kind = "flowers"
                elif r < 0.16:
                    kind = "bush"
            else:
                if n > 0.60 and r < 0.22:
                    kind = "oak" if r < 0.08 else "pine"
                elif r < 0.12:
                    kind = "bush"
                elif r < 0.20:
                    kind = "flowers"
                elif r > 0.955:
                    kind = "rock"
                elif r > 0.93:
                    kind = "stump"
            if kind is None:
                continue
            gap = 2 if kind in ("pine", "oak") else 1
            if near_used(x, y, gap):
                continue
            for lx, ly in landmarks:
                if abs(lx - x) < 3 and abs(ly - y) < 3:
                    kind = None
                    break
            if kind is None:
                continue
            used.add((x, y))
            jx = (hash01(x, y, seed + 201) - 0.5) * 0.7
            jy = (hash01(x, y, seed + 202) - 0.5) * 0.7
            scale = 0.85 + hash01(x, y, seed + 203) * 0.35
            flip = 1 if hash01(x, y, seed + 204) > 0.5 else 0
            decor.append([kind, round((x + 0.5 + jx) * 10), round((y + 0.5 + jy) * 10),
                          round(scale * 100), flip])
    return decor


def place_landmarks(g: Grid, spec: dict) -> list:
    """Hand-placed, high-value objects: houses, tower, gate, well, dock, signs."""
    out = []
    seed = int(spec["seed"])

    def put(kind: str, x: float, y: float, scale: float = 1.0, flip: int = 0):
        out.append([kind, round(x * 10), round(y * 10), round(scale * 100), flip])

    for village in spec.get("villages", []):
        cx, cy = village["at"]
        houses = int(village.get("houses", 4))
        for i in range(houses):
            ang = -0.9 + i * (1.8 / max(1, houses - 1))
            hx = cx + math.cos(ang) * float(village.get("spread", 9.0))
            hy = cy + math.sin(ang) * float(village.get("spread", 9.0)) * 0.8 - 3.0
            tx, ty = g.nearest_walkable(int(round(hx)), int(round(hy)), 4) or (int(hx), int(hy))
            put("cottage", tx + 0.5, ty + 0.5, 0.9 + hash01(tx, ty, seed) * 0.2,
                1 if i % 2 else 0)
        if village.get("well"):
            wx, wy = village["well"]
            put("well", wx + 0.5, wy + 0.5)
        if village.get("dock"):
            dx, dy = village["dock"]
            put("dock", dx + 0.5, dy + 0.5)

    for lamp in spec.get("torches", []):
        put("torch", lamp[0] + 0.5, lamp[1] + 0.5)
    for sign in spec.get("signs", []):
        put("sign", sign[0] + 0.5, sign[1] + 0.5)
    for lm in spec.get("landmark_props", []):
        kind = str(lm["kind"])
        put(kind, lm["at"][0] + 0.5, lm["at"][1] + 0.5,
            float(lm.get("scale", 1.0)), int(lm.get("flip", 0)))
    return out


# ----------------------------------------------------------------- zones -----
ZONE_ORDER_HINT = []


def zone_lookup(g: Grid, spec: dict):
    zones = [(z["name"], z["rect"]) for z in spec["zones"]]

    def at(x: int, y: int) -> str:
        for name, (zx, zy, zw, zh) in zones:
            if zx <= x < zx + zw and zy <= y < zy + zh:
                return name
        return "Jalan Tua"

    return at


# ------------------------------------------------------------ validation -----
def validate(g: Grid, spec: dict, decor: list, routes: list) -> dict:
    report = {"errors": [], "warnings": []}
    start = spec["player_start"]
    sx, sy = int(start[0]), int(start[1])
    if not walkable(g, sx, sy):
        report["errors"].append("player_start tidak walkable: %s" % (start,))
        sx, sy = g.nearest_walkable(sx, sy, 8) or (sx, sy)
    reach = flood(g, (sx, sy))
    report["reachable_tiles"] = len(reach)
    walkable_total = sum(1 for y in range(g.h) for x in range(g.w) if walkable(g, x, y))
    report["walkable_tiles"] = walkable_total

    blocked_kinds = {"region_gate", "cave_entrance", "bridge_broken"}
    checks = []
    for m in spec["markers"]:
        kind = m["kind"]
        tx, ty = int(m["at"][0]), int(m["at"][1])
        ok = (tx, ty) in reach
        if not ok and kind not in blocked_kinds:
            # a marker may sit exactly on a blocking structure (a door, a gate);
            # the approach tile is what has to be reachable
            ok = any((tx + dx, ty + dy) in reach
                     for dx in (-1, 0, 1) for dy in (-1, 0, 1))
        checks.append({"kind": kind, "name": m.get("name", ""), "ok": ok})
        if not ok and kind not in blocked_kinds:
            report["errors"].append("marker %s %s tidak terjangkau dari start"
                                    % (kind, m.get("name", "")))
    report["markers"] = checks

    # deliberately closed places must NOT be reachable
    for m in spec["markers"]:
        if m["kind"] == "region_gate":
            tx, ty = int(m["at"][0]), int(m["at"][1])
            if (tx, ty) in reach:
                report["errors"].append("gerbang region_gate terbuka (harus terkunci)")

    # isolated walkable pockets
    seen = set()
    pockets = []
    for y in range(g.h):
        for x in range(g.w):
            if (x, y) in seen or not walkable(g, x, y):
                continue
            comp = flood(g, (x, y))
            seen |= comp
            if comp != reach and len(comp) > 25:
                pockets.append(len(comp))
    report["unreachable_pockets"] = pockets
    if pockets:
        report["errors"].append("ada %d kantong walkable terisolasi (%s)"
                               % (len(pockets), pockets[:5]))

    # cliff sanity: a level jump of more than two has no mesh rule
    worst = 0
    for y in range(g.h):
        for x in range(g.w - 1):
            if walkable(g, x, y) and walkable(g, x + 1, y):
                worst = max(worst, abs(g.height[y][x] - g.height[y][x + 1]))
        for x in range(g.w):
            if y + 1 < g.h and walkable(g, x, y) and walkable(g, x, y + 1):
                worst = max(worst, abs(g.height[y][x] - g.height[y + 1][x]))
    report["max_height_step"] = worst
    # a tall bank between walkable tiles is a cliff, and the mesh always draws a
    # wall for it; it is reported, not failed. What must never happen is a
    # cliff the player can neither climb nor walk around - that is the pocket
    # check above.

    # road length: the brief's 450 tiles at 3.5 m/s, i.e. 2-3 minutes
    main = next((r for r in routes if r["id"] == "utama"), routes[0] if routes else None)
    report["main_road_tiles"] = main["length"] if main else 0
    if main and main["length"] < 450:
        report["errors"].append("jalur utama hanya %.0f ubin (< 450)" % main["length"])

    # decoration density per zone: an empty zone is a failed zone
    zone_of = zone_lookup(g, spec)
    counts = {}
    for entry in decor:
        x = int(entry[1]) // 10
        y = int(entry[2]) // 10
        counts[zone_of(x, y)] = counts.get(zone_of(x, y), 0) + 1
    report["decor_per_zone"] = counts
    for z in spec["zones"]:
        if z.get("kind") == "road":
            continue
        have = counts.get(z["name"], 0)
        tiles = z["rect"][2] * z["rect"][3]
        if have < max(12, tiles // 120):
            report["errors"].append("zona %s terlalu kosong (%d dekorasi)"
                                    % (z["name"], have))

    report["connectors"] = spec.get("_connectors", [])
    report["decor_total"] = len(decor)
    report["ok"] = not report["errors"]
    return report


# ------------------------------------------------------------------ export ---
def encode_grid(rows: list, w: int, h: int) -> str:
    flat = bytearray(w * h)
    for y in range(h):
        row = rows[y]
        for x in range(w):
            flat[y * w + x] = int(row[x]) & 0xFF
    return base64.b64encode(bytes(flat)).decode("ascii")


def export(g: Grid, spec: dict, decor: list, routes: list, report: dict) -> dict:
    w, h = g.w, g.h
    markers = []
    for m in spec["markers"]:
        markers.append({
            "kind": m["kind"],
            "name": m.get("name", ""),
            "x": round(float(m["at"][0]) + 0.5, 2),
            "y": round(float(m["at"][1]) + 0.5, 2),
            "radius": float(m.get("radius", 2.5)),
        })
    zones = []
    for z in spec["zones"]:
        zones.append({"name": z["name"], "kind": z.get("kind", "wild"),
                      "rect": z["rect"], "biome": z.get("biome", ""),
                      "subtitle": z.get("subtitle", ""),
                      "weather": z.get("weather", ""),
                      "music": z.get("music", "")})
    decor_by_kind = {}
    for kind, x, y, s, f in decor:
        decor_by_kind.setdefault(kind, []).append([x, y, s, f])
    for kind in decor_by_kind:
        decor_by_kind[kind] = sorted(decor_by_kind[kind])
    return {
        "schema": 1,
        "name": spec["name"],
        "seed": spec["seed"],
        "width": w,
        "height": h,
        "cell": 1.0,
        "level_h": float(spec.get("level_h", 1.8)),
        "chunk": int(spec.get("chunk", 32)),
        "origin": [w * 0.5, h * 0.5],
        "label": spec["name"],
        "grid_height": encode_grid(g.height, w, h),
        "grid_terrain": encode_grid(g.terrain, w, h),
        "grid_structure": encode_grid(g.struct, w, h),
        "decor": decor_by_kind,
        "markers": markers,
        "zones": zones,
        "routes": routes,
        "stats": {
            "walkable": report["walkable_tiles"],
            "road_tiles": report["main_road_tiles"],
            "decor": report["decor_total"],
            "max_step": report["max_height_step"],
        },
    }


def print_report(report: dict, routes: list) -> None:
    print("--- Yaros ---")
    print("walkable      : %d ubin" % report["walkable_tiles"])
    for r in routes:
        print("jalur %-10s: %.0f ubin" % (r["id"], r["length"]))
    print("dekorasi      : %d (%s)" % (report["decor_total"], report["decor_per_zone"]))
    print("langkah tinggi: maks %d level" % report["max_height_step"])
    bad = [c for c in report["markers"] if not c["ok"]]
    print("marker        : %d/%d terjangkau" %
          (len(report["markers"]) - len(bad), len(report["markers"])))
    for c in bad:
        print("   tidak terjangkau: %s %s" % (c["kind"], c["name"]))
    if report["unreachable_pockets"]:
        print("kantong       : %s" % report["unreachable_pockets"])
    print("tangga sambung: %d titik" % len(report.get("connectors", [])))
    for err in report["errors"]:
        print("GALAT: %s" % err)
    print("HASIL: %s" % ("LULUS" if report["ok"] else "GAGAL"))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--spec", default=SPEC)
    ap.add_argument("--out", default=OUT)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--allow-fail", action="store_true",
                    help="write the data even when validation fails (debug only)")
    args = ap.parse_args()

    with open(args.spec, encoding="utf-8") as fh:
        spec = json.load(fh)
    if args.seed:
        spec["seed"] = args.seed

    g, routes = build(spec)
    decor = place_landmarks(g, spec) + scatter(g, spec)
    decor.sort(key=lambda e: (e[0], e[2], e[1]))
    report = validate(g, spec, decor, routes)
    print_report(report, routes)
    if not report["ok"] and not args.allow_fail:
        print("data TIDAK ditulis: perbaiki spesifikasi dulu.")
        return 1

    data = export(g, spec, decor, routes, report)
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(data, fh, separators=(",", ":"), sort_keys=False)
    size = os.path.getsize(args.out)
    print("tulis %s (%.1f KB, seed %d)" % (args.out, size / 1024.0, spec["seed"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
