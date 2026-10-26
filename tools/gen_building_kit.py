#!/usr/bin/env python3
"""Re - Traveller : pixel textures for the step-3B building kit.

The world's buildings stop being sprite billboards and become low-poly meshes.
A mesh needs textures that tile on a wall, and the houses need to keep the
hand-painted look of the rest of Yaros, so this script paints one 512x512 atlas
of sixteen 128x128 cells in the same palette as `gen_world_props.py`:

    wall_timber   cream plaster with an oak frame on its edges -> tiles into a
                  half-timbered wall every two metres
    wall_wood     vertical oak boards, for sheds and hoardings
    wall_stone    coursed masonry, for towers and gate piers
    roof_shingle  overlapping scalloped shingles
    roof_thatch   straw, for the smaller cottages
    floor_stone   paving slabs, for the tower floor and the well apron
    window        a small leaded window (GLOW cell: lights up at dusk)
    door          plank door with iron bands
    beam          dark oak, used for corner posts, lintels and rails
    gable         the triangular end of a roof: plaster and crossed timbers
    plank_light   pale deck boards, for the jetty
    iron          dark iron with rivets, for hinges and bands
    banner        crimson cloth, for the tower pennant
    stone_pale    paler masonry, for parapets and crenellations
    roof_dark     slate, for the tower's cone roof
    flame         4 animation frames of fire (GLOW cell, animated by the shader)

Every texture is procedural and deterministic (fixed seed): a rebuild writes
byte-identical PNGs, so the repository never dirties itself.

    python3 tools/gen_building_kit.py

Output
    game/game/world/textures/building_atlas.png
    game/game/world/building_kit.json
"""

from __future__ import annotations

import json
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "game", "game", "world", "textures")
META = os.path.join(HERE, "..", "game", "game", "world")

CELL = 128
SEED = 20251126

# ------------------------------------------------------------------ palette ---
OUTLINE = (40, 30, 24)
OAK_DARK = (76, 54, 36)
OAK = (108, 78, 50)
OAK_LIGHT = (140, 104, 68)
OAK_PALE = (172, 138, 96)
PLASTER_DARK = (196, 178, 148)
PLASTER = (222, 208, 178)
PLASTER_LIGHT = (238, 228, 202)
STONE_DARK = (78, 74, 68)
STONE = (106, 102, 94)
STONE_LIGHT = (132, 128, 118)
STONE_PALE = (158, 154, 144)
SLATE_DARK = (58, 58, 66)
SLATE = (78, 78, 88)
SLATE_LIGHT = (100, 100, 112)
SHINGLE_DARK = (104, 52, 40)
SHINGLE = (136, 70, 50)
SHINGLE_LIGHT = (168, 94, 64)
THATCH_DARK = (146, 118, 62)
THATCH = (180, 152, 88)
THATCH_LIGHT = (206, 182, 122)
IRON = (58, 58, 64)
IRON_LIGHT = (96, 96, 104)
GLASS_DARK = (60, 52, 44)
GLASS_WARM = (226, 168, 82)
GLASS_HOT = (250, 216, 148)
BANNER_DARK = (120, 42, 38)
BANNER = (156, 58, 48)
BANNER_LIGHT = (186, 82, 62)
EMBER = (206, 96, 38)
FLAME = (238, 152, 56)
FLAME_HOT = (252, 230, 160)


def rng(seed: int) -> np.random.Generator:
    return np.random.default_rng(seed)


def canvas(size: int = CELL) -> np.ndarray:
    return np.zeros((size, size, 4), dtype=np.uint8)


def rect(img: np.ndarray, x0: int, y0: int, x1: int, y1: int, colour: tuple) -> None:
    h, w = img.shape[:2]
    x0, x1 = max(0, int(x0)), min(w, int(x1))
    y0, y1 = max(0, int(y0)), min(h, int(y1))
    if x1 <= x0 or y1 <= y0:
        return
    if len(colour) == 4:
        img[y0:y1, x0:x1, :] = colour
        return
    img[y0:y1, x0:x1, :3] = colour
    img[y0:y1, x0:x1, 3] = 255


def noise(img: np.ndarray, r: np.random.Generator, amount: float = 7.0) -> None:
    """Break up flat colour with grain, like the hand-made tiles.

    The grain is generated at half resolution and doubled up. Per-pixel noise
    triples the PNG's size for a difference nobody can see: these textures are
    drawn at a few pixels per metre on a phone, and the world already carries
    its own dither. Two-pixel grain still reads as hand-painted stone.
    """
    h, w = img.shape[:2]
    coarse = r.normal(0.0, amount, ((h + 1) // 2, (w + 1) // 2))
    grain = np.repeat(np.repeat(coarse, 2, axis=0), 2, axis=1)[:h, :w]
    rgb = img[:, :, :3].astype(np.float32) + grain[:, :, None]
    img[:, :, :3] = np.clip(rgb, 0, 255).astype(np.uint8)


def speck(img: np.ndarray, r: np.random.Generator, count: int, colour: tuple,
          x0: int = 0, y0: int = 0, x1: int = CELL, y1: int = CELL) -> None:
    for _ in range(count):
        x = int(r.integers(x0, max(x0 + 1, x1)))
        y = int(r.integers(y0, max(y0 + 1, y1)))
        rect(img, x, y, x + 1, y + 1, colour)


def wrap_rect(img: np.ndarray, x0: int, y0: int, x1: int, y1: int, colour: tuple) -> None:
    """Rect that wraps around the tile edges, so the texture tiles cleanly."""
    h, w = img.shape[:2]
    for ox in (0, -w):
        for oy in (0, -h):
            rect(img, x0 + ox, y0 + oy, x1 + ox, y1 + oy, colour)


# ------------------------------------------------------------------- walls ----
def wall_timber() -> np.ndarray:
    """Cream plaster panel with an oak frame on the tile edges: repeated on a
    wall, one cell becomes one half-timbered bay every two metres."""
    img = canvas()
    r = rng(SEED + 1)
    rect(img, 0, 0, CELL, CELL, PLASTER)
    noise(img, r, 5.0)
    speck(img, r, 90, PLASTER_DARK)
    speck(img, r, 40, PLASTER_LIGHT)
    # the frame: a beam down each edge and across the top and bottom
    for x0 in (0, CELL - 7):
        wrap_rect(img, x0, 0, x0 + 7, CELL, OAK)
        wrap_rect(img, x0 + 1, 0, x0 + 2, CELL, OAK_LIGHT)
        wrap_rect(img, x0 + 6, 0, x0 + 7, CELL, OAK_DARK)
    for y0 in (0, CELL - 7):
        wrap_rect(img, 0, y0, CELL, y0 + 7, OAK)
        wrap_rect(img, 0, y0 + 1, CELL, y0 + 2, OAK_LIGHT)
        wrap_rect(img, 0, y0 + 6, CELL, y0 + 7, OAK_DARK)
    # a diagonal brace in the lower left, and a stud in the middle: the pattern
    # every timber-framed cottage in the region has
    for i in range(46):
        rect(img, 7 + i, CELL - 46 + i, 12 + i, CELL - 41 + i, OAK if i % 5 else OAK_DARK)
    rect(img, CELL // 2 - 3, 7, CELL // 2 + 3, CELL - 7, OAK)
    rect(img, CELL // 2 - 2, 7, CELL // 2 - 1, CELL - 7, OAK_LIGHT)
    # grain on the beams
    speck(img, r, 120, OAK_DARK, 0, 0, CELL, 8)
    speck(img, r, 120, OAK_DARK, 0, CELL - 8, CELL, CELL)
    return img


def wall_wood() -> np.ndarray:
    img = canvas()
    r = rng(SEED + 2)
    rect(img, 0, 0, CELL, CELL, OAK)
    for x in range(0, CELL, 13):
        rect(img, x, 0, x + 1, CELL, OAK_DARK)
        rect(img, x + 2, 0, x + 3, CELL, OAK_LIGHT)
        # a knot per board, at a different height: no visible repeat
        ky = int(18 + (x * 37) % 90)
        rect(img, x + 5, ky, x + 9, ky + 3, OAK_DARK)
    noise(img, r, 6.0)
    speck(img, r, 70, OAK_DARK)
    speck(img, r, 40, OAK_PALE)
    # top and bottom plate
    rect(img, 0, 0, CELL, 4, OAK_DARK)
    rect(img, 0, CELL - 4, CELL, CELL, OAK_DARK)
    return img


def masonry(img: np.ndarray, r: np.random.Generator, base: tuple, light: tuple,
            dark: tuple, course: int = 16) -> None:
    """Coursed rubble: rows of blocks with mortar lines and a lit top edge."""
    rect(img, 0, 0, CELL, CELL, dark)
    for row, y in enumerate(range(0, CELL, course)):
        offset = (row % 2) * 11
        x = -offset
        while x < CELL:
            bw = 18 + int(r.integers(0, 10))
            shade = [base, base, light, base][int(r.integers(0, 4))]
            rect(img, x + 1, y + 1, x + bw - 1, y + course - 1, shade)
            rect(img, x + 1, y + 1, x + bw - 1, y + 2, light)
            rect(img, x + 1, y + course - 2, x + bw - 1, y + course - 1, dark)
            x += bw
    noise(img, r, 5.0)


def wall_stone() -> np.ndarray:
    img = canvas()
    r = rng(SEED + 3)
    masonry(img, r, STONE, STONE_LIGHT, STONE_DARK, course=16)
    speck(img, r, 70, STONE_DARK)
    # moss at the foot: the region's buildings all sit in damp grass
    speck(img, r, 60, (86, 104, 62), 0, CELL - 34, CELL, CELL)
    return img


def stone_pale() -> np.ndarray:
    img = canvas()
    r = rng(SEED + 4)
    masonry(img, r, STONE_LIGHT, STONE_PALE, STONE, course=14)
    speck(img, r, 50, STONE)
    return img


# ------------------------------------------------------------------- roofs ----
def roof_shingle() -> np.ndarray:
    """Scalloped shingles, lit on the upper edge: reads as clay tile from the
    game's 30-degree camera without a single smooth gradient."""
    img = canvas()
    r = rng(SEED + 5)
    rect(img, 0, 0, CELL, CELL, SHINGLE_DARK)
    row_h = 20
    for row, y in enumerate(range(0, CELL, row_h)):
        offset = (row % 2) * 11
        for x in range(-offset - 16, CELL + 16, 22):
            w = 20
            rect(img, x, y + 2, x + w, y + row_h - 3, SHINGLE)
            rect(img, x + 1, y + 2, x + w - 1, y + 5, SHINGLE_LIGHT)
            # rounded lower edge: two notches, not a straight line
            rect(img, x, y + row_h - 4, x + 3, y + row_h - 2, SHINGLE_DARK)
            rect(img, x + w - 3, y + row_h - 4, x + w, y + row_h - 2, SHINGLE_DARK)
            rect(img, x + w - 1, y + 2, x + w, y + row_h - 3, SHINGLE_DARK)
    noise(img, r, 7.0)
    speck(img, r, 90, SHINGLE_DARK)
    speck(img, r, 40, (150, 84, 58))
    return img


def roof_thatch() -> np.ndarray:
    img = canvas()
    r = rng(SEED + 6)
    rect(img, 0, 0, CELL, CELL, THATCH_DARK)
    for y in range(0, CELL, 9):
        rect(img, 0, y, CELL, y + 1, THATCH)
    for _ in range(900):
        x = int(r.integers(0, CELL))
        y = int(r.integers(0, CELL))
        length = int(r.integers(4, 12))
        colour = [THATCH, THATCH_LIGHT, THATCH_DARK][int(r.integers(0, 3))]
        rect(img, x, y, x + 1, min(CELL, y + length), colour)
    noise(img, r, 6.0)
    return img


def roof_dark() -> np.ndarray:
    """Slate: square courses, for the tower's cone roof."""
    img = canvas()
    r = rng(SEED + 7)
    rect(img, 0, 0, CELL, CELL, SLATE_DARK)
    for row, y in enumerate(range(0, CELL, 16)):
        offset = (row % 2) * 8
        for x in range(-offset, CELL, 16):
            rect(img, x + 1, y + 1, x + 15, y + 13, SLATE)
            rect(img, x + 1, y + 1, x + 15, y + 3, SLATE_LIGHT)
            rect(img, x + 1, y + 12, x + 15, y + 14, SLATE_DARK)
    noise(img, r, 5.0)
    spear = img
    speck(spear, r, 40, (120, 120, 132))
    return img


# ------------------------------------------------------------ floors/planks ---
def floor_stone() -> np.ndarray:
    img = canvas()
    r = rng(SEED + 8)
    rect(img, 0, 0, CELL, CELL, STONE_DARK)
    for y in range(0, CELL, 32):
        for x in range(0, CELL, 32):
            rect(img, x + 1, y + 1, x + 31, y + 31, STONE)
            rect(img, x + 2, y + 2, x + 30, y + 4, STONE_LIGHT)
            rect(img, x + 2, y + 29, x + 30, y + 30, STONE_DARK)
    noise(img, r, 6.0)
    speck(img, r, 60, STONE_DARK)
    return img


def plank_light() -> np.ndarray:
    img = canvas()
    r = rng(SEED + 9)
    rect(img, 0, 0, CELL, CELL, OAK_PALE)
    for y in range(0, CELL, 16):
        rect(img, 0, y, CELL, y + 1, OAK)
        rect(img, 0, y + 1, CELL, y + 2, OAK_LIGHT)
        for _ in range(18):
            x = int(r.integers(0, CELL))
            rect(img, x, y + 3, x + int(r.integers(6, 20)), y + 4, OAK_LIGHT)
    noise(img, r, 6.0)
    speck(img, r, 60, OAK)
    return img


def beam() -> np.ndarray:
    img = canvas()
    r = rng(SEED + 10)
    rect(img, 0, 0, CELL, CELL, OAK)
    for y in range(0, CELL, 26):
        rect(img, 0, y, CELL, y + 2, OAK_DARK)
        rect(img, 0, y + 2, CELL, y + 4, OAK_LIGHT)
    for _ in range(120):
        x = int(r.integers(0, CELL))
        y = int(r.integers(0, CELL))
        rect(img, x, y, x + int(r.integers(8, 30)), y + 1, OAK_LIGHT)
    noise(img, r, 7.0)
    rect(img, 0, 0, 3, CELL, OAK_DARK)
    rect(img, CELL - 3, 0, CELL, CELL, OAK_DARK)
    return img


def iron() -> np.ndarray:
    img = canvas()
    r = rng(SEED + 11)
    rect(img, 0, 0, CELL, CELL, IRON)
    noise(img, r, 4.0)
    for y in (30, 62, 94):
        for x in (24, 64, 104):
            rect(img, x, y, x + 5, y + 5, IRON_LIGHT)
            rect(img, x + 1, y + 1, x + 4, y + 4, (128, 128, 136))
    return img


# ------------------------------------------------------- doors and windows ----
def window_cell() -> np.ndarray:
    """A leaded window: warm panes, oak frame, iron mullions. The glow shader
    lights the panes at dusk, so the panes are the brightest pixels in the cell
    and the frame stays dark."""
    img = canvas()
    r = rng(SEED + 12)
    rect(img, 0, 0, CELL, CELL, (0, 0, 0, 0))
    # frame
    rect(img, 8, 8, CELL - 8, CELL - 8, OAK)
    rect(img, 8, 8, CELL - 8, 14, OAK_LIGHT)
    rect(img, 8, CELL - 14, CELL - 8, CELL - 8, OAK_DARK)
    rect(img, 8, 8, 14, CELL - 8, OAK_LIGHT)
    rect(img, CELL - 14, 8, CELL - 8, CELL - 8, OAK_DARK)
    # glass: panes of different warm tones, a diamond of hot light in the middle
    rect(img, 14, 14, CELL - 14, CELL - 14, GLASS_WARM)
    for y in range(14, CELL - 14, 22):
        rect(img, 14, y, CELL - 14, y + 2, GLASS_DARK)
    for x in range(14, CELL - 14, 22):
        rect(img, x, 14, x + 2, CELL - 14, GLASS_DARK)
    rect(img, 24, 24, CELL - 24, CELL - 24, GLASS_HOT)
    rect(img, 32, 32, CELL - 32, CELL - 32, GLASS_WARM)
    noise(img, r, 3.0)
    rect(img, 2, 2, CELL - 2, CELL - 2, (0, 0, 0, 0))
    rect(img, 8, 8, CELL - 8, CELL - 8, OAK)
    rect(img, 12, 12, CELL - 12, CELL - 12, GLASS_WARM)
    rect(img, 14, 14, CELL - 14, CELL - 14, GLASS_HOT)
    for y in range(14, CELL - 14, 22):
        rect(img, 14, y, CELL - 14, y + 2, OAK)
    for x in range(14, CELL - 14, 22):
        rect(img, x, 14, x + 2, CELL - 14, OAK)
    rect(img, 8, 8, CELL - 8, 10, OAK_LIGHT)
    rect(img, 8, CELL - 10, CELL - 8, CELL - 8, OAK_DARK)
    # sill
    rect(img, 4, CELL - 12, CELL - 4, CELL - 6, STONE_LIGHT)
    rect(img, 4, CELL - 7, CELL - 4, CELL - 5, STONE)
    # Glass carries a slightly lower alpha than its frame. The scissor in
    # building.gdshader only asks "is this pixel there" (>= 0.42), so the exact
    # value is free - and it is what lets the shader tell a pane from its oak
    # frame: at noon the PANE goes dark and cool like real glass while the frame
    # keeps the wood colour. Without the split, fading a window for daylight also
    # faded its frame and every wall got black rectangles.
    glass = ((img[:, :, 0] == GLASS_WARM[0]) & (img[:, :, 1] == GLASS_WARM[1])
             & (img[:, :, 2] == GLASS_WARM[2]))
    hot = ((img[:, :, 0] == GLASS_HOT[0]) & (img[:, :, 1] == GLASS_HOT[1])
           & (img[:, :, 2] == GLASS_HOT[2]))
    img[glass | hot, 3] = 204
    return img


def door_cell() -> np.ndarray:
    img = canvas()
    r = rng(SEED + 13)
    rect(img, 0, 0, CELL, CELL, (0, 0, 0, 0))
    # stone lintel and jambs
    rect(img, 4, 0, CELL - 4, 12, STONE)
    rect(img, 4, 0, CELL - 4, 4, STONE_LIGHT)
    rect(img, 0, 0, 10, CELL, STONE_DARK)
    rect(img, CELL - 10, 0, CELL, CELL, STONE_DARK)
    # planks, vertical
    rect(img, 10, 12, CELL - 10, CELL, OAK)
    for x in range(10, CELL - 10, 12):
        rect(img, x, 12, x + 1, CELL, OAK_DARK)
        rect(img, x + 2, 12, x + 3, CELL, OAK_LIGHT)
    noise(img, r, 6.0)
    # iron bands and studs
    for y in (30, 74, 106):
        rect(img, 10, y, CELL - 10, y + 6, IRON)
        rect(img, 10, y, CELL - 10, y + 2, IRON_LIGHT)
        for x in range(16, CELL - 14, 22):
            rect(img, x, y + 1, x + 3, y + 5, IRON_LIGHT)
    # ring handle
    rect(img, CELL // 2 + 26, 60, CELL // 2 + 32, 62, IRON_LIGHT)
    rect(img, CELL // 2 + 26, 62, CELL // 2 + 28, 74, IRON_LIGHT)
    rect(img, CELL // 2 + 30, 62, CELL // 2 + 32, 74, IRON_LIGHT)
    rect(img, CELL // 2 + 26, 72, CELL // 2 + 32, 74, IRON_LIGHT)
    return img


def gable_cell() -> np.ndarray:
    """The triangular end under a roof: plaster with a crossed timber brace."""
    img = canvas()
    r = rng(SEED + 14)
    rect(img, 0, 0, CELL, CELL, PLASTER)
    noise(img, r, 5.0)
    speck(img, r, 70, PLASTER_DARK)
    for i in range(CELL):
        rect(img, i, i, i + 1, i + 1, OAK)
        rect(img, CELL - 1 - i, i, CELL - i, i + 1, OAK)
        rect(img, i, i + 1, i + 1, i + 2, OAK_LIGHT)
    rect(img, 0, 0, CELL, 6, OAK)
    rect(img, 0, 0, CELL, 2, OAK_LIGHT)
    rect(img, 0, CELL - 5, CELL, CELL, OAK)
    rect(img, 0, 0, CELL, 2, OAK)
    rect(img, 0, 0, 4, CELL, OAK)
    rect(img, CELL - 4, 0, CELL, CELL, OAK)
    return img


def banner_cell() -> np.ndarray:
    img = canvas()
    r = rng(SEED + 15)
    rect(img, 0, 0, CELL, CELL, (0, 0, 0, 0))
    rect(img, 12, 4, CELL - 12, CELL - 8, BANNER)
    for y in range(8, CELL - 10, 18):
        rect(img, 14, y, CELL - 14, y + 2, BANNER_DARK)
    # a stylised traveller's star, in the same language as the crest
    cx, cy = CELL // 2, CELL // 2
    for i in range(-14, 15):
        rect(img, cx + i, cy - 2, cx + i + 1, cy + 2, BANNER_LIGHT)
        rect(img, cx - 2, cy + i, cx + 2, cy + i + 1, BANNER_LIGHT)
    for i in range(-9, 10):
        rect(img, cx + i, cy + i, cx + i + 1, cy + i + 1, BANNER_LIGHT)
        rect(img, cx + i, cy - i, cx + i + 1, cy - i + 1, BANNER_LIGHT)
    rect(img, cx - 4, cy - 4, cx + 4, cy + 4, BANNER_LIGHT)
    # the fly edge is ragged
    for y in range(4, CELL - 8, 10):
        rect(img, CELL - 12, y, CELL - 5, y + 4, (0, 0, 0, 0))
    rect(img, 8, 0, CELL - 6, 6, OAK)
    noise(img, r, 4.0)
    return img


def flame_cell() -> np.ndarray:
    """Four frames of fire side by side (4 x 32 px wide). The glow shader picks a
    frame from TIME, so a torch on a post flickers without an animation player.

    The first version scattered ninety random pixels per frame and the capture
    of the village read as confetti rather than fire: at 2-6 screen pixels per
    texture pixel, a flame has to be a SOLID shape. So: one teardrop body, a hot
    core inside it, a thin tongue above, and six embers. Each frame is a little
    taller, thinner and further left than the last, which is the flicker.
    """
    img = canvas()
    r = rng(SEED + 16)
    for frame in range(4):
        x0 = frame * 32
        mid = x0 + 16 + [0, -1, 1, 0][frame]
        lift = [0, 4, -3, 2][frame]
        # body: a teardrop, widest just above the wick
        for y in range(34 + lift, 112):
            grow = min(7.0, (y - (34 + lift)) / 9.0)
            half = max(1, int(1 + grow))
            colour = FLAME if y > 52 + lift else EMBER
            rect(img, mid - half, y, mid + half, y + 1, colour)
        # hot core: narrow, low in the body, so the flame reads orange with a
        # white middle rather than as a white candle
        for y in range(74 + lift, 104):
            half = max(1, int((104 - y) / 13.0) + 1)
            rect(img, mid - half, y, mid + half, y + 1, FLAME_HOT)
        # the tongue above the body
        for y in range(20 + lift, 34 + lift):
            half = 1 if y > 26 + lift else 0
            rect(img, mid - half, y, mid + half + 1, y + 1, EMBER)
        # embers, deterministic, and only ever two pixels each
        for _ in range(6):
            ex = mid + int(r.integers(-9, 10))
            ey = int(r.integers(14 + lift, 40 + lift))
            rect(img, ex, ey, ex + 2, ey + 2, EMBER if r.random() < 0.6 else FLAME)
    return img


CELLS = [
    ("wall_timber", wall_timber, 2.0, False),
    ("wall_wood", wall_wood, 1.6, False),
    ("wall_stone", wall_stone, 2.0, False),
    ("roof_shingle", roof_shingle, 1.2, False),
    ("roof_thatch", roof_thatch, 1.2, False),
    ("floor_stone", floor_stone, 1.6, False),
    ("window", window_cell, 0.0, True),
    ("door", door_cell, 0.0, False),
    ("beam", beam, 1.0, False),
    ("gable", gable_cell, 0.0, False),
    ("plank_light", plank_light, 1.2, False),
    ("iron", iron, 0.8, False),
    ("banner", banner_cell, 0.0, False),
    ("stone_pale", stone_pale, 2.0, False),
    ("roof_dark", roof_dark, 1.2, False),
    ("flame", flame_cell, 0.0, True),
]

# What the world may place as a 3D building, and how big it really is. The
# mesher reads `footprint` for the foundation and the occlusion box, and
# RegionData-style collision reads `block_radius`.
KINDS = {
    # w/d/h are the mesh's real bounds in metres (the roof overhang included),
    # used for the occlusion box and by the mesh generator's sanity checks.
    # block_radius mirrors RegionData.blocker_radius, the collision contract
    # that step 2 signed off - a house takes the same room in 3D as it did as a
    # sprite, so walking through the village feels unchanged.
    # 7,8 m: the widest variant carries a lean-to on its left flank, and the
    # footprint is what samples the ground under the whole house - including the
    # shed, which must not float over a slope either
    "cottage": {"w": 7.8, "d": 5.04, "h": 5.9, "variants": 3, "block_radius": 2.0,
                "front": True},
    "tower": {"w": 4.7, "d": 4.7, "h": 13.3, "variants": 2, "block_radius": 2.4,
              "front": True},
    "gate": {"w": 4.9, "d": 1.6, "h": 5.0, "variants": 1, "block_radius": 2.2,
             "front": True},
    "well": {"w": 2.4, "d": 2.4, "h": 3.3, "variants": 1, "block_radius": 0.9,
             "front": False},
    "dock": {"w": 4.8, "d": 2.4, "h": 1.0, "variants": 1, "block_radius": 0.0,
             "front": False},
    "sign": {"w": 1.1, "d": 0.3, "h": 2.2, "variants": 2, "block_radius": 0.45,
             "front": True},
    "torch": {"w": 0.7, "d": 0.7, "h": 3.0, "variants": 1, "block_radius": 0.3,
              "front": False},
}


def main() -> None:
    cols = 4
    rows = (len(CELLS) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * CELL, rows * CELL), (0, 0, 0, 0))
    meta_cells = []
    for index, (name, fn, tile_m, glow) in enumerate(CELLS):
        cell = fn()
        if cell.shape[0] != CELL or cell.shape[1] != CELL:
            raise SystemExit(f"cell {name} bukan {CELL}x{CELL}")
        cx = (index % cols) * CELL
        cy = (index // cols) * CELL
        sheet.paste(Image.fromarray(cell, "RGBA"), (cx, cy))
        meta_cells.append({
            "name": name,
            "index": index,
            "rect": [cx, cy, CELL, CELL],
            "uv": [round(cx / sheet.width, 6), round(cy / sheet.height, 6),
                   round(CELL / sheet.width, 6), round(CELL / sheet.height, 6)],
            "tile_m": tile_m,
            "glow": glow,
        })
    os.makedirs(OUT, exist_ok=True)
    atlas_path = os.path.join(OUT, "building_atlas.png")
    sheet.save(atlas_path)
    meta = {
        "schema": 1,
        "atlas": [sheet.width, sheet.height],
        "cells": meta_cells,
        "kinds": KINDS,
    }
    with open(os.path.join(META, "building_kit.json"), "w", encoding="utf-8") as fh:
        json.dump(meta, fh, indent=1)
        fh.write("\n")
    print(f"[KIT] {atlas_path} {sheet.width}x{sheet.height}, {len(meta_cells)} sel, "
          f"{len(KINDS)} jenis bangunan")


if __name__ == "__main__":
    main()
