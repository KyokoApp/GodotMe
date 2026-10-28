#!/usr/bin/env python3
"""Generate the terrain/prop textures that REGION "Yaros" (step 2) needs.

The old valley used two hand-made tiles (grass, dirt). A tiered region needs a
few more surfaces - cliff rock, sand, snow, dressed stone, bridge wood, water -
and they must sit in the SAME visual language: 256x256, nearest-filtered pixel
art, warm palette, no gradients, no smooth noise.

Everything here is procedural but deterministic: the same seed writes
byte-identical PNGs, so a rebuild never dirties the repository by accident.

    python3 tools/gen_region_tiles.py
    python3 tools/gen_region_tiles.py --only cliff

Output: game/game/world/textures/*.png (world.pck).
"""

from __future__ import annotations

import argparse
import math
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "game", "game", "world", "textures")

SIZE = 256
SEED = 20251025


# ------------------------------------------------------------------ noise -----
def _rng(seed: int) -> np.random.Generator:
    return np.random.default_rng(seed)


def tile_noise(size: int, cells: int, seed: int) -> np.ndarray:
    """Smooth value noise that wraps at the edges (so the texture tiles)."""
    rng = _rng(seed)
    grid = rng.random((cells, cells))
    # bilinear over a circular grid: sample at 4 neighbours and wrap the index
    ys = np.linspace(0.0, cells, size, endpoint=False)
    xs = np.linspace(0.0, cells, size, endpoint=False)
    y0 = np.floor(ys).astype(int)
    x0 = np.floor(xs).astype(int)
    fy = (ys - y0)[:, None]
    fx = (xs - x0)[None, :]
    fy = fy * fy * (3.0 - 2.0 * fy)
    fx = fx * fx * (3.0 - 2.0 * fx)
    g00 = grid[np.ix_(y0 % cells, x0 % cells)]
    g10 = grid[np.ix_(y0 % cells, (x0 + 1) % cells)]
    g01 = grid[np.ix_((y0 + 1) % cells, x0 % cells)]
    g11 = grid[np.ix_((y0 + 1) % cells, (x0 + 1) % cells)]
    top = g00 * (1.0 - fx) + g10 * fx
    bot = g01 * (1.0 - fx) + g11 * fx
    return top * (1.0 - fy) + bot * fy


def speckles(size: int, count: int, seed: int, length: int = 2) -> np.ndarray:
    """Vertical 1 px strokes, the trick that makes the old grass read as pixel
    art rather than as a noise field."""
    m = np.zeros((size, size), dtype=bool)
    rng = _rng(seed)
    xs = rng.integers(0, size, count)
    ys = rng.integers(0, size, count)
    for x, y in zip(xs, ys):
        m[y : y + length, x] = True
    return m


def mix(a: tuple, b: tuple, t: float) -> tuple:
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def shade(base: tuple, k: float) -> tuple:
    return tuple(max(0, min(255, int(round(c * k)))) for c in base)


def put(img: np.ndarray, mask: np.ndarray, colour: tuple, alpha: float = 1.0) -> None:
    """Paint `colour` where `mask` is set, keeping the existing colour by
    `1 - alpha`. Works on an (h, w, 3) uint8 array."""
    mask = np.broadcast_to(mask, img.shape[:2])
    if alpha >= 1.0:
        img[mask] = colour
        return
    for c in range(3):
        img[..., c][mask] = (
            img[..., c][mask] * (1.0 - alpha) + colour[c] * alpha
        ).astype(np.uint8)


def quantise(img: np.ndarray, colours: int, name: str) -> Image.Image:
    out = Image.fromarray(img, "RGB").quantize(
        colors=colours, method=Image.MEDIANCUT, dither=Image.Dither.NONE
    ).convert("RGB")
    return out


def save(img: Image.Image, name: str) -> None:
    path = os.path.join(OUT, name + ".png")
    img.save(path, optimize=True)
    print("[tiles] %-22s %dx%d %6d B" % (name + ".png", img.width, img.height,
                                          os.path.getsize(path)))


# ------------------------------------------------------------------ tiles -----
def cliff() -> Image.Image:
    """Layered rock face. Strata run horizontally because the walls in the world
    are vertical: a horizontal band reads as sediment, and it hides the seam
    where one 1.8 m level meets the next."""
    base = np.zeros((SIZE, SIZE, 3), dtype=np.uint8)
    bands = [(96, 86, 72), (76, 68, 58), (116, 104, 86), (64, 57, 50)]
    n_grain = tile_noise(SIZE, 64, SEED + 2)
    xs = np.arange(SIZE)
    ys = np.arange(SIZE)
    warp = 4.0 * np.sin(xs * 2.0 * np.pi / 128.0) + 2.0 * np.sin(xs * 2.0 * np.pi / 37.0)
    for y in range(SIZE):
        for x in range(SIZE):
            v = (y + warp[x]) / 38.0
            band = int(np.floor(v)) % len(bands)
            f = v - np.floor(v)
            c = bands[band]
            if f < 0.11:
                c = shade(c, 1.16)
            elif f > 0.90:
                c = shade(c, 0.78)
            jitter = (float(n_grain[y, x]) - 0.5) * 18.0
            base[y, x] = (max(0, min(255, int(c[0] + jitter))),
                          max(0, min(255, int(c[1] + jitter))),
                          max(0, min(255, int(c[2] + jitter))))
    # vertical cracks: a dark core with a lit edge on one side
    rng = _rng(SEED + 3)
    for _ in range(7):
        x = float(rng.integers(8, SIZE - 8))
        y = int(rng.integers(0, SIZE))
        length = int(rng.integers(40, 130))
        drift = float(rng.uniform(-0.8, 0.8))
        for i in range(length):
            xx = int(round(x + drift * i + 2.0 * np.sin(i / 9.0))) % SIZE
            yy = (y + i) % SIZE
            base[yy, xx] = shade(bands[3], 0.55)
            if xx + 1 < SIZE:
                base[yy, xx + 1] = shade(bands[2], 1.10)
    # moss: the top lip and a few damp pockets, never a camouflage field
    moss_n = tile_noise(SIZE, 10, SEED + 4)
    top = np.arange(SIZE)[:, None] < 7
    put(base, top, (78, 92, 48), 0.9)
    put(base, (moss_n > 0.78) & (np.arange(SIZE)[:, None] < 60), (74, 90, 46), 0.55)
    put(base, tile_noise(SIZE, 28, SEED + 5) > 0.93, (104, 120, 64), 0.25)
    return quantise(base, 18, "cliff_tile")


def sand() -> Image.Image:
    n1 = tile_noise(SIZE, 5, SEED + 10)
    n2 = tile_noise(SIZE, 21, SEED + 11)
    base = np.zeros((SIZE, SIZE, 3), dtype=np.uint8)
    pale = (214, 196, 156)
    warm = (188, 162, 118)
    dark = (150, 126, 88)
    for y in range(SIZE):
        for x in range(0, SIZE, 64):
            t = float(np.clip(0.65 * n1[y, x] + 0.35 * n2[y, x], 0, 1))
            base[y, x : x + 64, :] = mix(pale, warm, t)
    # wide, soft ripples: the beach cue at a glance, at low contrast
    for band in range(6):
        y0 = band * SIZE // 6
        put(base, (np.arange(SIZE)[:, None] >= y0) & (np.arange(SIZE)[:, None] < y0 + 3),
            shade(warm, 1.06), 0.30)
        put(base, (np.arange(SIZE)[:, None] >= y0 + 3) & (np.arange(SIZE)[:, None] < y0 + 5),
            dark, 0.18)
    put(base, speckles(SIZE, 240, SEED + 12), (228, 212, 176), 0.28)
    put(base, speckles(SIZE, 300, SEED + 13, 1), (166, 142, 104), 0.35)
    put(base, tile_noise(SIZE, 60, SEED + 14) > 0.90, (222, 204, 166), 0.25)
    return quantise(base, 18, "sand_tile")


def snow() -> Image.Image:
    """Snow reads as snow because of its SHADOWS, not its white: soft blue-grey
    drift shadows with a lit crust above them, plus a little sparkle."""
    base = np.zeros((SIZE, SIZE, 3), dtype=np.uint8)
    white = (238, 240, 236)
    lit = (250, 250, 246)
    shade_blue = (182, 198, 212)
    drift = tile_noise(SIZE, 9, SEED + 20)
    grain = tile_noise(SIZE, 44, SEED + 21)
    xs = np.arange(SIZE)[None, :]
    ys = np.arange(SIZE)[:, None]
    bank = np.clip((0.42 - drift) / 0.16, 0.0, 1.0) * 0.55
    bank *= np.clip(0.55 + 0.45 * np.sin(ys * 0.09 + xs * 0.004), 0.0, 1.0)
    for y in range(SIZE):
        for x in range(SIZE):
            c = mix(white, shade_blue, float(bank[y, x]))
            if grain[y, x] > 0.82:
                c = mix(c, lit, 0.6)
            base[y, x] = c
    put(base, (np.clip((0.42 - drift) / 0.16, 0.0, 1.0) < 0.12)
        & (drift < 0.42), lit, 0.55)
    put(base, tile_noise(SIZE, 70, SEED + 23) > 0.97, (255, 255, 255), 0.9)
    return quantise(base, 10, "snow_tile")


def stone_floor() -> Image.Image:
    """Dressed slabs: 2x2 blocks per tile, mortar dark, chipped corners."""
    n1 = tile_noise(SIZE, 7, SEED + 30)
    n2 = tile_noise(SIZE, 24, SEED + 31)
    base = np.zeros((SIZE, SIZE, 3), dtype=np.uint8)
    cool = (124, 118, 108)
    warm = (146, 138, 124)
    mortar = (78, 74, 66)
    for y in range(SIZE):
        for x in range(SIZE):
            t = float(np.clip(0.55 * n1[y, x] + 0.45 * n2[y, x], 0, 1))
            base[y, x] = mix(cool, warm, t)
    for k in range(1, 4):
        seam = (k * SIZE // 4) + 2
        base[:, seam - 1 : seam + 1] = mortar
        base[seam - 1 : seam + 1, :] = mortar
    # slab bevels: lighter top edge, darker bottom edge inside each block
    for by in range(4):
        for bx in range(4):
            y0, x0 = by * 64, bx * 64
            base[y0 + 2 : y0 + 4, x0 + 2 : x0 + 62] = shade(warm, 1.12)
            base[y0 + 60 : y0 + 62, x0 + 2 : x0 + 62] = shade(cool, 0.82)
    put(base, (n2 > 0.80), shade(warm, 1.10), 0.45)
    put(base, tile_noise(SIZE, 30, SEED + 32) > 0.88, (86, 96, 62), 0.35)  # moss in joints
    return quantise(base, 16, "stone_floor_tile")


def wood() -> Image.Image:
    """Bridge/dock planks: horizontal boards, dark seams every 32 px."""
    n1 = tile_noise(SIZE, 4, SEED + 40)
    n2 = tile_noise(SIZE, 40, SEED + 41)
    base = np.zeros((SIZE, SIZE, 3), dtype=np.uint8)
    light = (150, 112, 74)
    mid = (124, 90, 58)
    dark = (88, 62, 40)
    for y in range(SIZE):
        plank = y // 32
        t = float(np.clip(0.5 * n1[y, 0] + 0.5 * n2[y, 0] + 0.08 * (plank % 2), 0, 1))
        base[y, :, :] = mix(mid, light, t)
    for seam in range(0, SIZE + 1, 32):
        base[max(0, seam - 2) : seam, :] = dark
    # grain: long horizontal strokes, darker
    put(base, ((n2 > 0.66) & (n2 < 0.74)) | (n2 < 0.05), shade(dark, 1.1), 0.35)
    # nails at the plank ends
    rng = _rng(SEED + 42)
    for y in range(16, SIZE, 32):
        for _ in range(2):
            x = int(rng.integers(6, SIZE - 6))
            base[y - 1 : y + 2, x - 1 : x + 2] = (70, 72, 74)
    return quantise(base, 16, "wood_tile")


def water() -> Image.Image:
    """A tile the water shader scrolls twice at different speeds: broad swell
    plus fine chop. Low contrast on purpose - the tint comes from depth."""
    base = np.zeros((SIZE, SIZE, 3), dtype=np.uint8)
    deep = (38, 60, 68)
    lift = (66, 94, 96)
    crest = (126, 146, 136)
    xs = np.arange(SIZE)[None, :]
    ys = np.arange(SIZE)[:, None]
    swell = np.sin(ys * 2.0 * np.pi / 34.0 + 1.6 * np.sin(xs * 2.0 * np.pi / 96.0))
    chop = np.sin((ys * 1.9 + xs * 0.35) * 2.0 * np.pi / 17.0
                  + 0.8 * np.sin(xs * 2.0 * np.pi / 48.0))
    t = np.clip(0.55 * (0.5 + 0.5 * swell) + 0.45 * (0.5 + 0.5 * chop), 0.0, 1.0)
    for y in range(SIZE):
        for x in range(SIZE):
            base[y, x] = mix(deep, lift, float(t[y, x]) * 0.85)
    put(base, (swell > 0.93) & (chop > -0.2), crest, 0.35)
    put(base, (swell < -0.94), shade(deep, 0.85), 0.4)
    put(base, tile_noise(SIZE, 40, SEED + 53) > 0.95, (168, 186, 172), 0.30)
    return quantise(base, 12, "water_tile")


# ------------------------------------------------------------------ props -----
def _alpha_canvas(w: int, h: int) -> np.ndarray:
    return np.zeros((h, w, 4), dtype=np.uint8)


def flowers() -> Image.Image:
    """A clump of small warm flowers. Billboards, never a character."""
    w, h = 96, 64
    img = _alpha_canvas(w, h)
    rng = _rng(SEED + 60)
    stem = (72, 96, 52)
    leaf = (94, 122, 62)
    petals = [(226, 210, 168), (214, 150, 96), (188, 104, 104), (232, 190, 96)]
    for i in range(26):
        x = int(rng.integers(4, w - 4))
        base = h - 1 - int(rng.integers(0, 6))
        height = int(rng.integers(8, 22))
        for k in range(height):
            y = base - k
            if 0 <= y < h:
                img[y, x] = (*stem, 255)
        if rng.random() < 0.6:
            ly = base - height // 2
            lx = x + (1 if rng.random() < 0.5 else -1)
            if 0 <= ly < h and 0 <= lx < w:
                img[ly, lx] = (*leaf, 255)
        top = base - height
        col = petals[int(rng.integers(0, len(petals)))]
        for dx, dy in ((0, 0), (1, 0), (0, -1), (1, -1), (-1, 0)):
            xx, yy = x + dx, top + dy
            if 0 <= xx < w and 0 <= yy < h:
                img[yy, xx] = (*col, 255)
        if 0 <= top + 1 < h:
            img[top + 1, x] = (150, 120, 60, 255)
    return Image.fromarray(img, "RGBA")


def reeds() -> Image.Image:
    w, h = 80, 128
    img = _alpha_canvas(w, h)
    rng = _rng(SEED + 61)
    green = (86, 108, 58)
    dry = (150, 132, 82)
    tip = (176, 150, 96)
    for i in range(18):
        x = int(rng.integers(4, w - 4))
        top = int(rng.integers(16, 54))
        bend = rng.uniform(-0.10, 0.10)
        height = h - top
        for k in range(height):
            y = h - 1 - k
            xx = int(round(x + bend * k))
            if 0 <= xx < w and 0 <= y < h:
                img[y, xx] = (*(green if k < height * 0.75 else dry), 255)
        if 0 <= top < h:
            img[top, max(0, min(w - 1, int(round(x + bend * height))))] = (*tip, 255)
            if top + 1 < h:
                img[top + 1, max(0, min(w - 1, int(round(x + bend * height))))] = (*tip, 220)
    return Image.fromarray(img, "RGBA")


def stump() -> Image.Image:
    w, h = 96, 64
    img = _alpha_canvas(w, h)
    bark = (92, 70, 48)
    bark_light = (128, 100, 68)
    cut = (168, 140, 96)
    ring = (138, 112, 76)
    cx, cy, rx, ry = w // 2, h // 2 + 6, 34, 20
    for y in range(h):
        for x in range(w):
            dx = (x - cx) / rx
            dy = (y - cy) / ry
            if dx * dx + dy * dy <= 1.0:
                img[y, x] = (*bark, 255)
    for y in range(cy - 8, cy - 2):
        for x in range(cx - 24, cx + 24):
            dx = (x - cx) / 30.0
            dy = (y - (cy - 5)) / 4.0
            if dx * dx + dy * dy <= 1.0:
                img[y, x] = (*cut, 255)
    for r in (8, 16, 24):
        for a in range(0, 360, 6):
            x = int(cx + math.cos(math.radians(a)) * r)
            y = int(cy - 5 + math.sin(math.radians(a)) * r * 0.22)
            if 0 <= x < w and 0 <= y < h and img[y, x, 3] > 0:
                img[y, x] = (*ring, 255)
    for y in range(cy, cy + 12):
        for x in range(cx - 30, cx + 30):
            if img[y, x, 3] > 0 and (x + y) % 7 == 0:
                img[y, x] = (*bark_light, 255)
    return Image.fromarray(img, "RGBA")


BUILDERS = {
    "cliff": cliff,
    "sand": sand,
    "snow": snow,
    "stone_floor": stone_floor,
    "wood": wood,
    "water": water,
    "flowers": flowers,
    "reeds": reeds,
    "stump": stump,
}

NAMES = {
    "cliff": "cliff_tile",
    "sand": "sand_tile",
    "snow": "snow_tile",
    "stone_floor": "stone_floor_tile",
    "wood": "wood_tile",
    "water": "water_tile",
    "flowers": "flowers",
    "reeds": "reeds",
    "stump": "stump",
}


def atlas() -> Image.Image:
    """One 1024x512 sheet holding every ground surface, 4x2 cells.

    Why an atlas: each chunk becomes ONE mesh with ONE material, so a phone
    draws the whole valley in a handful of calls instead of one per surface
    type. Cell order (must match RegionMesh.ATLAS_CELL in GDScript):
        0 grass   1 dirt   2 sand   3 cliff-rock
        4 snow    5 stone  6 wood   7 spare
    """
    cells = ["grass_tile", "path_tile", "sand_tile", "cliff_tile",
             "snow_tile", "stone_floor_tile", "wood_tile", "stone_floor_tile"]
    sheet = Image.new("RGB", (SIZE * 4, SIZE * 2))
    for i, name in enumerate(cells):
        cell = Image.open(os.path.join(OUT, name + ".png")).convert("RGB")
        sheet.paste(cell, ((i % 4) * SIZE, (i // 4) * SIZE))
    # one shared palette keeps the sheet a few hundred KB instead of a megabyte,
    # and pixel art has no colours to spare anyway
    return sheet.quantize(colors=160, method=Image.MEDIANCUT, dither=Image.Dither.NONE)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="", help="one key from: " + ", ".join(BUILDERS))
    args = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    for key, build in BUILDERS.items():
        if args.only and args.only != key:
            continue
        save(build(), NAMES[key])
    if not args.only:
        save(atlas(), "terrain_atlas")


if __name__ == "__main__":
    main()
