#!/usr/bin/env python3
"""Prop art for REGION "Yaros": the six objects the builder places but the old
valley never had, and one atlas that holds every prop.

Step 2's map is generated, so the props have to exist before the map can look
finished: a mountain gate at Pos Gunung, the watch tower, the village well, the
lake dock, the roadside signs and the torches along the old road. They are
ENVIRONMENT, not characters - no character in this game is ever drawn by code.

House style, same as gen_region_tiles.py: 55-60 pixels per metre, hard edges,
three or four shades per material, a warm dark outline, no gradient, no blur.
The palette is the valley's own (oak, moss, slate, ember) so a torch beside a
pine reads as one picture.

The second half of the script packs every prop - the six new ones plus the
trees, cottage, bush and rock the valley already used - into ONE atlas with a
companion JSON. Why: a chunk draws all its props with a single MultiMesh, and a
single MultiMesh can only use one texture. One atlas = one draw call for the
~80 props of a chunk instead of ten.

    python3 tools/gen_world_props.py
    python3 tools/gen_world_props.py --only torch

Output:
    game/game/world/textures/{dock,gate,sign,torch,tower,well}.png
    game/game/world/textures/prop_atlas.png
    game/game/world/prop_atlas.json
"""

from __future__ import annotations

import argparse
import json
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "game", "game", "world", "textures")
META_DIR = os.path.join(HERE, "..", "game", "game", "world")

SEED = 20251025

# ------------------------------------------------------------------ palette ---
OUTLINE = (44, 32, 24)
WOOD_DARK = (78, 56, 38)
WOOD = (112, 82, 54)
WOOD_LIGHT = (146, 112, 76)
WOOD_PALE = (176, 144, 102)
STONE_DARK = (74, 70, 64)
STONE = (104, 100, 92)
STONE_LIGHT = (132, 128, 118)
STONE_PALE = (156, 152, 142)
MOSS = (86, 104, 62)
MOSS_DARK = (60, 76, 46)
IRON = (62, 62, 68)
IRON_LIGHT = (96, 96, 104)
EMBER_DARK = (150, 58, 30)
EMBER = (206, 96, 38)
FLAME = (238, 152, 56)
FLAME_HOT = (252, 222, 140)
SHADOW = (30, 24, 20)

# world size in metres of every prop; the mesher reads this from the JSON
SIZE_M = {
    "bush": (1.5, 1.2),
    "cottage": (5.6, 4.2),
    "dock": (4.8, 2.2),
    "flowers": (0.9, 0.6),
    "gate": (3.4, 3.9),
    "oak": (5.4, 4.0),
    "pine": (3.2, 5.4),
    "reeds": (1.0, 1.6),
    "rock": (1.9, 1.3),
    "sign": (1.1, 1.5),
    "stump": (1.1, 0.7),
    "torch": (0.55, 2.2),
    "tower": (5.2, 7.3),
    "well": (2.2, 1.9),
}

# which PNG feeds which prop
SOURCE = {
    "bush": "bush.png",
    "cottage": "cottage.png",
    "flowers": "flowers.png",
    "oak": "tree_oak.png",
    "pine": "tree_pine.png",
    "reeds": "reeds.png",
    "rock": "rock.png",
    "stump": "stump.png",
}
# the six this script draws itself
NEW = ["dock", "gate", "sign", "torch", "tower", "well"]

# order inside the atlas: the mesher's kind index is this list's position, and
# the JSON carries the same order, so both sides agree without guessing.
ORDER = ["pine", "oak", "bush", "rock", "stump", "flowers", "reeds",
         "cottage", "dock", "gate", "sign", "torch", "tower", "well"]
ATLAS_COLS = 4


# ------------------------------------------------------------------ helpers ---
def canvas(w: int, h: int) -> np.ndarray:
    return np.zeros((h, w, 4), dtype=np.uint8)


def rect(img: np.ndarray, x0: int, y0: int, x1: int, y1: int, colour: tuple) -> None:
    """Filled rectangle, clipped. Coordinates are inclusive-exclusive."""
    h, w = img.shape[:2]
    x0, x1 = max(0, min(w, x0)), max(0, min(w, x1))
    y0, y1 = max(0, min(h, y0)), max(0, min(h, y1))
    if x1 <= x0 or y1 <= y0:
        return
    img[y0:y1, x0:x1, 0:3] = colour
    img[y0:y1, x0:x1, 3] = 255


def outline(img: np.ndarray, colour: tuple = OUTLINE) -> None:
    """One-pixel outline around every opaque region.

    Done as a dilation difference: cheap, exact, and it never eats the interior
    the way a per-shape border does when two shapes touch.
    """
    alpha = img[..., 3] > 0
    grown = alpha.copy()
    grown[1:, :] |= alpha[:-1, :]
    grown[:-1, :] |= alpha[1:, :]
    grown[:, 1:] |= alpha[:, :-1]
    grown[:, :-1] |= alpha[:, 1:]
    edge = grown & ~alpha
    img[edge, 0:3] = colour
    img[edge, 3] = 255


def speck(img: np.ndarray, x0: int, y0: int, x1: int, y1: int, colour: tuple,
          step: int, phase: int = 0) -> None:
    """Deterministic 1 px stipple, the cheap way to kill flat colour."""
    h, w = img.shape[:2]
    for y in range(max(0, y0), min(h, y1)):
        for x in range(max(0, x0), min(w, x1)):
            if img[y, x, 3] == 0:
                continue
            if (x * 7 + y * 13 + phase) % step == 0:
                img[y, x, 0:3] = colour


def plank(img: np.ndarray, x0: int, y0: int, x1: int, y1: int, step: int = 9,
          base: tuple = WOOD, seam: tuple = WOOD_DARK,
          light: tuple = WOOD_LIGHT) -> None:
    rect(img, x0, y0, x1, y1, base)
    for y in range(y0, y1, step):
        rect(img, x0, y, x1, y + 1, seam)
        rect(img, x0, y + 1, x1, y + 2, light)


def stone_rows(img: np.ndarray, x0: int, y0: int, x1: int, y1: int, row: int = 13,
               offset: int = 0) -> None:
    """Coursed masonry: alternating rows of slightly different stone, mortar
    lines, and a darker block here and there so the wall is not a grid."""
    rect(img, x0, y0, x1, y1, STONE)
    width = x1 - x0
    for i, y in enumerate(range(y0, y1, row)):
        shade = [STONE, STONE_LIGHT, STONE, STONE_DARK][i % 4]
        rect(img, x0, y, x1, min(y1, y + row - 1), shade)
        rect(img, x0, min(y1, y + row - 1), x1, min(y1, y + row), STONE_DARK)
        shift = (offset + i * 17) % 23
        for x in range(x0 + shift, x1, 23):
            rect(img, x, y, x + 1, min(y1, y + row - 1), STONE_DARK)
        if i % 3 == 1:
            rect(img, x0 + (i * 13) % max(1, width - 8), y + 2,
                 x0 + (i * 13) % max(1, width - 8) + 6, y + row - 3, STONE_PALE)


def moss(img: np.ndarray, x0: int, y0: int, x1: int, y1: int) -> None:
    """Moss creeping up from a base line: only onto pixels that exist."""
    h, w = img.shape[:2]
    for x in range(max(0, x0), min(w, x1)):
        depth = 3 + ((x * 5 + x // 3) % 6)
        for y in range(max(0, y1 - depth), min(h, y1)):
            if img[y, x, 3] == 0:
                continue
            img[y, x, 0:3] = MOSS if (x + y) % 4 else MOSS_DARK


# --------------------------------------------------------------------- torch ---
def torch() -> Image.Image:
    """A stake torch: iron collar, guttering flame, two embers in the air."""
    w, h = 40, 140
    img = canvas(w, h)
    # stake, thick enough to read at phone distance
    rect(img, 16, 50, 24, 140, WOOD)
    rect(img, 17, 50, 20, 140, WOOD_LIGHT)
    rect(img, 23, 50, 24, 140, WOOD_DARK)
    for y in range(58, 136, 13):
        rect(img, 16, y, 24, y + 1, WOOD_DARK)
    # iron collar and the charred rag under the head
    rect(img, 13, 46, 27, 56, IRON)
    rect(img, 14, 47, 26, 49, IRON_LIGHT)
    rect(img, 14, 38, 26, 48, (92, 70, 50))
    rect(img, 15, 39, 25, 43, (56, 42, 30))
    # flame: a teardrop with a hot core and a sooty base
    for y in range(2, 48):
        t = (y - 2) / 46.0
        half = 1.5 + 10.0 * (t ** 0.55)
        wob = 1.8 * np.sin(y * 0.42)
        cx = 20.0 + wob
        x0, x1 = int(round(cx - half)), int(round(cx + half))
        rect(img, x0, y, x1, y + 1, (204, 92, 38) if t > 0.14 else (150, 58, 30))
        rect(img, int(round(cx - half * 0.62)), y,
             int(round(cx + half * 0.62)), y + 1,
             FLAME if t > 0.10 else (216, 120, 44))
        if t > 0.40:
            rect(img, int(round(cx - half * 0.30)), y,
                 int(round(cx + half * 0.30)), y + 1, FLAME_HOT)
    # embers dancing above the flame
    for ex, ey in ((9, 20), (30, 12), (27, 30), (12, 34)):
        rect(img, ex, ey, ex + 2, ey + 2, FLAME if ex % 2 else (216, 120, 44))
    outline(img)
    return Image.fromarray(img, "RGBA")


# ---------------------------------------------------------------------- sign ---
def sign() -> Image.Image:
    """A hand-cut roadside board on one post."""
    w, h = 76, 108
    img = canvas(w, h)
    # post
    rect(img, 34, 40, 42, 108, WOOD)
    rect(img, 35, 40, 38, 108, WOOD_LIGHT)
    rect(img, 41, 40, 42, 108, WOOD_DARK)
    # board
    plank(img, 4, 12, 72, 56, step=11, base=WOOD_LIGHT, seam=WOOD_DARK,
          light=WOOD_PALE)
    # cut the four corners off: no pips, the pixels simply are not there
    for k in range(5):
        for i in range(5 - k):
            img[12 + k, 4 + i, 3] = 0
            img[12 + k, 71 - i, 3] = 0
            img[55 - k, 4 + i, 3] = 0
            img[55 - k, 71 - i, 3] = 0
    # carved lettering: two lines of notches (no readable text; see the note in
    # docs/DESIGN_NOTES.md - the game does not fake a script it cannot write)
    for x in range(13, 62, 8):
        rect(img, x, 23, x + 5, 26, WOOD_DARK)
        rect(img, x, 24, x + 5, 25, (92, 68, 46))
    for x in range(13, 54, 8):
        rect(img, x, 34, x + 5, 37, WOOD_DARK)
        rect(img, x, 35, x + 5, 36, (92, 68, 46))
    # binding strap and nails
    rect(img, 34, 40, 42, 45, IRON)
    rect(img, 35, 41, 41, 42, IRON_LIGHT)
    for nx in (11, 63):
        rect(img, nx, 15, nx + 2, 18, IRON_LIGHT)
        rect(img, nx, 49, nx + 2, 52, IRON_LIGHT)
    outline(img)
    return Image.fromarray(img, "RGBA")


# ---------------------------------------------------------------------- well ---
def well() -> Image.Image:
    """Stone well with a shingled gable roof, a winch and a bucket on a rope."""
    w, h = 128, 112
    img = canvas(w, h)
    # stone ring: three courses around an ellipse, the inner shaft dark
    cx, cy, rx, ry = 64, 94, 42, 16
    for y in range(h):
        for x in range(w):
            dx = (x - cx) / rx
            dy = (y - cy) / ry
            d = dx * dx + dy * dy
            if 1.0 >= d >= 0.30:
                row = (y - (cy - ry)) // 6
                shade = [STONE, STONE_LIGHT, STONE_DARK][row % 3]
                if (x + row * 11) % 17 == 0:
                    shade = STONE_DARK
                img[y, x, 0:3] = shade
                img[y, x, 3] = 255
            elif d < 0.30:
                img[y, x, 0:3] = (40, 42, 44) if (x + y) % 6 else (58, 62, 64)
                img[y, x, 3] = 255
    # two posts, thick enough to be seen behind the roof
    for px in (22, 96):
        rect(img, px, 40, px + 10, 96, WOOD)
        rect(img, px + 1, 40, px + 5, 96, WOOD_LIGHT)
        rect(img, px + 8, 40, px + 10, 96, WOOD_DARK)
    # gable roof: a steep triangle of slates with a ridge cap
    for y in range(14, 44):
        half = 6 + (y - 14) * 2.6
        rect(img, int(cx - half), y, int(cx + half), y + 1,
             (96, 92, 86) if (y - 14) % 5 else (118, 112, 104))
    for y in range(17, 44, 5):
        half = 6 + (y - 14) * 2.6
        rect(img, int(cx - half) + 2, y, int(cx + half) - 2, y + 1, (72, 68, 64))
    rect(img, 2, 42, 126, 48, WOOD_DARK)
    rect(img, 6, 48, 122, 51, (58, 44, 32))
    # winch, rope, bucket
    rect(img, 30, 56, 98, 61, WOOD)
    rect(img, 30, 56, 98, 58, WOOD_PALE)
    rect(img, 62, 61, 65, 70, (128, 112, 88))
    rect(img, 55, 70, 72, 84, WOOD)
    rect(img, 56, 71, 71, 74, WOOD_DARK)
    rect(img, 58, 84, 69, 86, (52, 40, 30))
    moss(img, 20, 78, 108, 104)
    outline(img)
    return Image.fromarray(img, "RGBA")


# ---------------------------------------------------------------------- dock ---
def dock() -> Image.Image:
    """A jetty in perspective: the deck runs away from the camera, posts stand
    in the water, a rope rail runs down one side.

    A side-on pier reads as a fence; a deck you can see the top of reads as
    something you can walk on, which is what this one is for.
    """
    w, h = 256, 128
    img = canvas(w, h)
    front_y, back_y = 84, 18
    fx0, fx1 = 14, 242          # front edge
    bx0, bx1 = 82, 174          # far edge
    # deck: a quad whose far edge is narrower (that is the whole illusion)
    for y in range(back_y, front_y):
        t = (y - back_y) / float(front_y - back_y)
        x0 = int(bx0 + (fx0 - bx0) * t)
        x1 = int(bx1 + (fx1 - bx1) * t)
        rect(img, x0, y, x1, y + 1, WOOD_LIGHT if (y // 3) % 2 else WOOD)
        for px in range(x0 + 8, x1 - 6, 18):
            rect(img, px, y, px + 1, y + 1, WOOD_DARK)
        # the two side faces, seen because the deck is above the water
        rect(img, x0, y, x0 + 3, y + 1, WOOD_DARK)
        rect(img, x1 - 3, y, x1, y + 1, (58, 42, 30))
    # front edge: plank ends and the shadow under the deck
    rect(img, fx0, front_y, fx1, front_y + 14, WOOD)
    for px in range(fx0 + 2, fx1, 15):
        rect(img, px, front_y, px + 1, front_y + 14, WOOD_DARK)
        rect(img, px + 3, front_y + 2, px + 11, front_y + 5, WOOD_LIGHT)
    rect(img, fx0, front_y + 13, fx1, front_y + 16, (50, 36, 26))
    # posts down into the water
    for px in (26, 88, 150, 214):
        rect(img, px, front_y + 15, px + 9, 116, WOOD_DARK)
        rect(img, px + 1, front_y + 15, px + 4, 116, WOOD)
    for px in (26, 150):
        for k in range(24):
            rect(img, px + 4 + k // 2, front_y + 22 + k, px + 9 + k // 2,
                 front_y + 23 + k, WOOD_DARK)
    # rope rail along the right side
    for y in range(back_y + 4, front_y):
        t = (y - back_y) / float(front_y - back_y)
        x = int(bx1 + (fx1 - bx1) * t) - 3
        rect(img, x, y, x + 2, y + 1, (156, 136, 98) if y % 4 else (126, 108, 80))
    for t in (0.2, 0.6, 0.98):
        y = int(back_y + (front_y - back_y) * t)
        x = int(bx1 + (fx1 - bx1) * t) - 8
        rect(img, x, y - 8, x + 6, y + 1, WOOD)
    # a coil of rope and a mooring bollard on the deck
    for i, (x, y) in enumerate(((104, 56), (112, 60), (120, 55), (128, 59))):
        rect(img, x, y, x + 9, y + 4, (156, 136, 98) if i % 2 else (128, 110, 80))
    rect(img, 172, 40, 184, 56, WOOD)
    rect(img, 174, 40, 182, 42, WOOD_PALE)
    # wet band where the posts meet the water
    for px in (26, 88, 150, 214):
        rect(img, px - 4, 110, px + 13, 118, (44, 52, 52))
    outline(img)
    return Image.fromarray(img, "RGBA")


# ---------------------------------------------------------------------- gate ---
def gate() -> Image.Image:
    """The mountain gate: two stone piers, an iron-bound lintel, a shut gate.

    Pos Gunung is locked for step 2 by design, so the gate is drawn CLOSED - a
    closed gate is the honest picture of `S_GATE` in the data.
    """
    w, h = 200, 232
    img = canvas(w, h)
    # piers
    for x0 in (0, 168):
        stone_rows(img, x0, 66, x0 + 32, 232, row=15, offset=x0)
        rect(img, x0 - 2 if x0 else 0, 60, x0 + 34 if x0 else 32, 70, STONE_LIGHT)
        # crenellation
        for k in range(2):
            cx = x0 + 2 + k * 16
            rect(img, cx, 52, cx + 11, 62, STONE)
            rect(img, cx, 52, cx + 11, 54, STONE_PALE)
    # lintel: oak beam with two iron straps and a hanging lamp hook
    plank(img, 26, 30, 174, 58, step=11, base=WOOD, seam=WOOD_DARK, light=WOOD_LIGHT)
    rect(img, 26, 28, 174, 32, WOOD_DARK)
    for sx in (46, 100, 154):
        rect(img, sx, 30, sx + 6, 58, IRON)
        rect(img, sx + 1, 31, sx + 2, 57, IRON_LIGHT)
    # the gate itself: two leaves of vertical planks with iron bands
    for leaf_x0, leaf_x1 in ((34, 98), (102, 166)):
        plank(img, leaf_x0, 58, leaf_x1, 214, step=99, base=WOOD,
              seam=WOOD_DARK, light=WOOD_LIGHT)
        for x in range(leaf_x0 + 3, leaf_x1 - 2, 11):
            rect(img, x, 58, x + 1, 214, WOOD_DARK)
        for by in (80, 128, 176):
            rect(img, leaf_x0, by, leaf_x1, by + 7, IRON)
            rect(img, leaf_x0, by, leaf_x1, by + 2, IRON_LIGHT)
            for rx in range(leaf_x0 + 6, leaf_x1 - 4, 16):
                rect(img, rx, by + 2, rx + 3, by + 5, IRON_LIGHT)
    # centre seam and handles
    rect(img, 98, 58, 102, 214, (54, 40, 30))
    for hx in (88, 108):
        rect(img, hx, 130, hx + 4, 150, IRON_LIGHT)
    # a step of packed earth at the foot
    rect(img, 24, 214, 176, 224, (118, 96, 70))
    rect(img, 16, 224, 184, 232, (96, 78, 58))
    moss(img, 0, 196, 32, 232)
    moss(img, 168, 196, 200, 232)
    outline(img)
    return Image.fromarray(img, "RGBA")


# --------------------------------------------------------------------- tower ---
def tower() -> Image.Image:
    """The watch tower: tapered stone shaft, timber hoarding on corbels,
    crenellated parapet and a pennant, so it reads as a landmark from across
    the plateau."""
    w, h = 288, 420
    img = canvas(w, h)
    cx = 144
    top_y, base_y = 172, 420
    # shaft: masonry rows following a gentle taper (not a pyramid)
    for y in range(top_y, base_y):
        t = (y - top_y) / float(base_y - top_y)
        half = 58 + 14 * t
        row = (y - top_y) // 14
        shade = [STONE, STONE_LIGHT, STONE, STONE_DARK][row % 4]
        rect(img, int(cx - half), y, int(cx + half), y + 1, shade)
        for bx in range(int(cx - half) + (row * 19) % 27, int(cx + half), 27):
            rect(img, bx, y, bx + 1, y + 1, STONE_DARK)
        if (y - top_y) % 14 == 13:
            rect(img, int(cx - half), y, int(cx + half), y + 1, STONE_DARK)
    # lit left flank, shaded right flank
    for y in range(top_y, base_y):
        t = (y - top_y) / float(base_y - top_y)
        half = 58 + 14 * t
        rect(img, int(cx - half), y, int(cx - half) + 8, y + 1, STONE_LIGHT)
        rect(img, int(cx + half) - 12, y, int(cx + half), y + 1, STONE_DARK)
    # windows: one arched opening per window, sill under it
    for wx, wy in ((cx - 34, 226), (cx + 2, 282), (cx - 30, 336)):
        for i in range(8):                      # round head, same width as body
            half = int(round(6.5 * np.sqrt(max(0.0, 1.0 - ((8 - i) / 8.0) ** 2))))
            rect(img, wx - half, wy + i, wx + half + 1, wy + i + 1, (36, 34, 32))
        rect(img, wx - 6, wy + 7, wx + 7, wy + 26, (36, 34, 32))
        rect(img, wx - 7, wy + 26, wx + 8, wy + 29, STONE_PALE)
        rect(img, wx - 5, wy + 8, wx - 4, wy + 24, (58, 54, 50))
    # door
    for i in range(14):
        half = int(11 * np.sqrt(max(0.0, 1.0 - ((14 - i) / 14.0) ** 2)))
        rect(img, cx - half, 350 + i, cx + half, 351 + i, (48, 36, 26))
    rect(img, cx - 12, 364, cx + 12, 420, (48, 36, 26))
    rect(img, cx - 12, 364, cx - 10, 420, (70, 54, 38))
    rect(img, cx + 10, 364, cx + 12, 420, (32, 24, 18))
    for sy in (382, 402):
        rect(img, cx - 10, sy, cx + 10, sy + 3, IRON)
    # corbels bridging shaft and hoarding, then the hoarding they carry
    for bx in range(cx - 66, cx + 68, 22):
        for k in range(20):
            rect(img, bx + 1 + k // 3, 152 + k, bx + 12 - k // 3, 153 + k, WOOD_DARK)
    plank(img, cx - 76, 114, cx + 76, 154, step=10, base=WOOD, seam=WOOD_DARK,
          light=WOOD_LIGHT)
    for bx in range(cx - 74, cx + 74, 25):
        rect(img, bx, 114, bx + 6, 154, WOOD_DARK)
    rect(img, cx - 76, 110, cx + 76, 117, WOOD_PALE)
    # parapet with merlons above the hoarding
    rect(img, cx - 62, 92, cx + 62, 114, STONE)
    rect(img, cx - 62, 92, cx + 62, 96, STONE_LIGHT)
    for k in range(5):
        bx = cx - 62 + k * 26
        rect(img, bx, 74, bx + 16, 94, STONE_LIGHT)
        rect(img, bx, 74, bx + 16, 77, STONE_PALE)
        rect(img, bx + 14, 74, bx + 16, 94, STONE_DARK)
    # pennant on a pole
    rect(img, cx - 2, 12, cx + 2, 92, WOOD_DARK)
    for i in range(28):
        span = 30 - i
        rect(img, cx + 2, 16 + i, cx + 2 + max(5, span), 17 + i,
             (150, 56, 48) if i % 6 else (120, 42, 38))
    rect(img, cx + 2, 16, cx + 6, 70, (120, 42, 38))
    moss(img, 40, 380, 250, 420)
    speck(img, 70, 180, 220, 410, STONE_DARK, 29, 7)
    outline(img)
    return Image.fromarray(img, "RGBA")


BUILDERS = {
    "dock": dock,
    "gate": gate,
    "sign": sign,
    "torch": torch,
    "tower": tower,
    "well": well,
}


# --------------------------------------------------------------------- atlas ---
def shelf_pack(images: dict, width: int = 768, pad: int = 2) -> tuple:
    """Shelf-pack sprites, tallest first, into rows of `width`."""
    order = sorted(images, key=lambda k: (-images[k].height, k))
    rows = []
    x = pad
    y = pad
    row_h = 0
    placed = {}
    for name in order:
        im = images[name]
        if x + im.width + pad > width:
            x = pad
            y += row_h + pad
            row_h = 0
        placed[name] = (x, y)
        x += im.width + pad
        row_h = max(row_h, im.height)
    height = y + row_h + pad
    return placed, width, height


def build_atlas() -> None:
    images = {}
    for kind, filename in SOURCE.items():
        path = os.path.join(OUT, filename)
        images[kind] = Image.open(path).convert("RGBA")
    for kind in NEW:
        path = os.path.join(OUT, kind + ".png")
        images[kind] = Image.open(path).convert("RGBA")

    placed, aw, ah = shelf_pack(images)
    sheet = Image.new("RGBA", (aw, ah), (0, 0, 0, 0))
    cells = []
    for kind in ORDER:
        im = images[kind]
        x, y = placed[kind]
        sheet.paste(im, (x, y))
        size = SIZE_M[kind]
        cells.append({
            "kind": kind,
            "index": ORDER.index(kind),
            "rect": [x, y, im.width, im.height],
            "size_m": [size[0], size[1]],
            # uv rect, top-left origin in atlas space; the shader flips v
            "uv": [round(x / aw, 6), round(y / ah, 6),
                   round(im.width / aw, 6), round(im.height / ah, 6)],
        })

    path = os.path.join(OUT, "prop_atlas.png")
    sheet.save(path, optimize=True)
    print("[props] %-22s %dx%d %7d B" % ("prop_atlas.png", aw, ah,
                                         os.path.getsize(path)))

    meta = {
        "schema": 1,
        "cols": ATLAS_COLS,
        "atlas": [aw, ah],
        "count": len(ORDER),
        "cells": cells,
    }
    mpath = os.path.join(META_DIR, "prop_atlas.json")
    with open(mpath, "w", encoding="utf-8") as fh:
        json.dump(meta, fh, indent=1, sort_keys=False)
        fh.write("\n")
    print("[props] %-22s %7d B, %d sel" % ("prop_atlas.json",
                                           os.path.getsize(mpath), len(cells)))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="", help="one key from: " + ", ".join(BUILDERS))
    args = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    for key, build in BUILDERS.items():
        if args.only and args.only != key:
            continue
        img = build()
        path = os.path.join(OUT, key + ".png")
        img.save(path, optimize=True)
        print("[props] %-22s %dx%d %7d B" % (key + ".png", img.width, img.height,
                                             os.path.getsize(path)))
    if not args.only:
        build_atlas()


if __name__ == "__main__":
    main()
