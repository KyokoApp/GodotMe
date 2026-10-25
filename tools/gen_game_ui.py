#!/usr/bin/env python3
"""Re - Traveller : game UI icons (24x24, warm palette, hard pixels).

Same idea as `tools/gen_ui_kit.py` for the launcher: the PNGs are generated once
by a committed script, so the whole set shares one grid, one outline colour and
one palette. Nothing is drawn at runtime (project rule).

Every icon is authored at 12x12 and doubled with NEAREST, which keeps the pixel
grid honest on a 24x24 button and makes the set feel like one family.

Palette (warm fantasy only - no blue glow, no neon):
    o outline      (58, 40, 28)
    B wood dark    (120, 84, 52)
    b wood light   (166, 124, 82)
    C cream        (246, 232, 204)
    W paper white  (252, 246, 232)
    G gold         (214, 168, 86)
    g gold dark    (168, 124, 58)
    R heart red    (178, 66, 50)
    r heart light  (224, 110, 80)
    Y lamp yellow  (250, 214, 120)
    S ink shadow   (96, 66, 44)

Run (Pillow needed):
    python3 tools/gen_game_ui.py
"""
from __future__ import annotations

import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "game", "game", "assets", "ui", "icons")

PALETTE = {
    "o": (58, 40, 28, 255),
    "B": (120, 84, 52, 255),
    "b": (166, 124, 82, 255),
    "C": (246, 232, 204, 255),
    "W": (252, 246, 232, 255),
    "G": (214, 168, 86, 255),
    "g": (168, 124, 58, 255),
    "R": (178, 66, 50, 255),
    "r": (224, 110, 80, 255),
    "Y": (250, 214, 120, 255),
    "S": (96, 66, 44, 255),
    "E": (120, 52, 44, 255),
    ".": (0, 0, 0, 0),
}

ICONS = {
    # a full heart: the player's three lives
    "heart_full": [
        ".oo....oo...",
        "oRro..orRo..",
        "oRRRooRRRo..",
        "oRRRRRRRRo..",
        "oRRRRRRRRo..",
        "oRRRRRRRRo..",
        ".oRRRRRRo...",
        "..oRRRRo....",
        "...oRRo.....",
        "....oo......",
        "............",
        "............",
    ],
    # the same silhouette, empty: a heart that has been spent
    "heart_empty": [
        ".oo....oo...",
        "oEo....oEo..",
        "oEEooooEEo..",
        "oEEEEEEEEo..",
        "oEEEEEEEEo..",
        "oEEEEEEEEo..",
        ".oEEEEEEo...",
        "..oEEEEo....",
        "...oEEo.....",
        "....oo......",
        "............",
        "............",
    ],
    # daytime sun and night moon are drawn as shapes below, because an 8-ray
    # sun typed as ASCII reads as a coin and a cog typed as ASCII reads as a star
    # back / close
    "arrow_left": [
        "............",
        "......oo....",
        ".....oGGo...",
        "....oGGGo...",
        "...oGGGGo...",
        "..oGGGGGo...",
        "...oGGGGo...",
        "....oGGGo...",
        ".....oGGo...",
        "......oo....",
        "............",
        "............",
    ],
    # ---- action icons (step 1: the contextual button) ----------------------
    # A speech ribbon: "Bicara".
    "talk": [
        "............",
        "..oooooooo..",
        ".oCCCCCCCCo.",
        ".oCoCoCoCCo.",
        ".oCCCCCCCCo.",
        ".oCoCoCoCCo.",
        ".oCCCCCCCCo.",
        "..ooooCCCo..",
        ".....oCo....",
        "....oo......",
        "............",
        "............",
    ],
    # An arched door with a brass handle: "Masuk".
    "door": [
        "............",
        "...oooooo...",
        "..oBBBBBBo..",
        ".oBbBBBBbBo.",
        ".oBbBBBBbBo.",
        ".oBbBBBBbBo.",
        ".oBbBBBGbBo.",
        ".oBbBBBBbBo.",
        ".oBbBBBBbBo.",
        ".oBbBBBBbBo.",
        ".oooooooooo.",
        "............",
    ],
    # An eye: "Periksa".
    "inspect": [
        "............",
        "............",
        "...oooooo...",
        "..oCCCCCCo..",
        ".oCCCooCCCo.",
        "oCCCoooCCCCo",
        ".oCCCooCCCo.",
        "..oCCCCCCo..",
        "...oooooo...",
        "............",
        "............",
        "............",
    ],
    # A tied pouch: "Ambil".
    "take": [
        "............",
        "....oooo....",
        "...oB..Bo...",
        "..oBBBBBBo..",
        "..oBbBBbBo..",
        ".oBbBBBBbBo.",
        ".oBbBBBBbBo.",
        ".oBbBBBBbBo.",
        "..oBbBBbBo..",
        "...oooooo...",
        "............",
        "............",
    ],
    # A folded map with creases and one gold trail: the peta tab.
    "map": [
        "............",
        "..oooooooo..",
        ".oCCSoCCSCo.",
        ".oCGSoCCSCo.",
        ".oCGSoGCSGo.",
        ".oCGSoGGCCo.",
        ".oCCSoGGSCo.",
        ".oCGSoCCSCo.",
        ".oCCSoCCSCo.",
        "..oooooooo..",
        "............",
        "............",
    ],
    # A brass cross: close the panel.
    "close": [
        "............",
        "............",
        "..G......G..",
        "...G....G...",
        "....G..G....",
        ".....GG.....",
        ".....GG.....",
        "....G..G....",
        "...G....G...",
        "..G......G..",
        "............",
        "............",
    ],
}


def _disc(size: int, cx: float, cy: float, r: float) -> set[tuple[int, int]]:
    out: set[tuple[int, int]] = set()
    for y in range(size):
        for x in range(size):
            if (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r * r:
                out.add((x, y))
    return out


def _outline(shape: set[tuple[int, int]], size: int) -> set[tuple[int, int]]:
    """Pixels outside `shape` that touch it (4-neighbour), clipped to the canvas."""
    edge: set[tuple[int, int]] = set()
    for (x, y) in shape:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            p = (x + dx, y + dy)
            if 0 <= p[0] < size and 0 <= p[1] < size and p not in shape:
                edge.add(p)
    return edge


def _blank(size: int = 24) -> Image.Image:
    return Image.new("RGBA", (size, size), (0, 0, 0, 0))


def draw_sun() -> Image.Image:
    """A warm disc with eight short rays; reads as a sun, not a ring."""
    size = 24
    img = _blank(size)
    px = img.load()
    core = _disc(size, 12.0, 12.0, 5.0)
    rays: set[tuple[int, int]] = set()
    for k in range(8):
        ang = k * 3.14159265 / 4.0
        for step in range(7, 10):
            x = int(round(12.0 + step * __import__("math").cos(ang) - 0.5))
            y = int(round(12.0 + step * __import__("math").sin(ang) - 0.5))
            if 0 <= x < size and 0 <= y < size:
                rays.add((x, y))
    shape = core | rays
    for (x, y) in _outline(shape, size):
        px[x, y] = PALETTE["o"]
    for (x, y) in rays:
        px[x, y] = PALETTE["G"]
    for (x, y) in core:
        inner = (x + 0.5 - 12.0) ** 2 + (y + 0.5 - 12.0) ** 2 <= 2.6 ** 2
        px[x, y] = PALETTE["Y"] if inner else PALETTE["G"]
    return img


def draw_moon() -> Image.Image:
    """Crescent: a disc with a second disc bitten out of its upper right."""
    size = 24
    img = _blank(size)
    px = img.load()
    full = _disc(size, 11.0, 12.5, 6.2)
    bite = _disc(size, 15.6, 9.4, 5.0)
    shape = full - bite
    for (x, y) in _outline(shape, size):
        px[x, y] = PALETTE["o"]
    for (x, y) in shape:
        px[x, y] = PALETTE["C"]
    # one gold star beside it, so the icon reads "night" at 24 px
    for p in [(19, 17), (18, 17), (20, 17), (19, 16), (19, 18)]:
        px[p[0], p[1]] = PALETTE["G"]
    return img


def draw_gear() -> Image.Image:
    """Eight square teeth around a rim with a hole - clockwork, not machinery."""
    size = 24
    img = _blank(size)
    px = img.load()
    rim = _disc(size, 12.0, 12.0, 6.4)
    teeth: set[tuple[int, int]] = set()
    for k in range(8):
        ang = k * 3.14159265 / 4.0
        cx = 12.0 + 8.2 * __import__("math").cos(ang)
        cy = 12.0 + 8.2 * __import__("math").sin(ang)
        for y in range(int(cy) - 2, int(cy) + 2):
            for x in range(int(cx) - 2, int(cx) + 2):
                if 0 <= x < size and 0 <= y < size:
                    teeth.add((x, y))
    shape = rim | teeth
    hole = _disc(size, 12.0, 12.0, 2.4)
    shape = shape - hole
    for (x, y) in _outline(shape | hole, size):
        px[x, y] = PALETTE["o"]
    for (x, y) in shape:
        px[x, y] = PALETTE["G"]
    return img


SHAPES = {"sun": draw_sun, "moon": draw_moon, "gear": draw_gear}


def render(rows: list[str]) -> Image.Image:
    small = Image.new("RGBA", (12, 12), (0, 0, 0, 0))
    px = small.load()
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            px[x, y] = PALETTE.get(ch, PALETTE["."])
    return small.resize((24, 24), Image.NEAREST)


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    for name, fn in SHAPES.items():
        img = fn()
        img.save(os.path.join(OUT, name + ".png"))
        print("drew  %-14s %dx%d" % (name + ".png", img.width, img.height))
    for name, rows in ICONS.items():
        assert len(rows) == 12, name
        for row in rows:
            assert len(row) == 12, (name, row)
        img = render(rows)
        path = os.path.join(OUT, name + ".png")
        img.save(path)
        print("wrote %-14s %dx%d" % (name + ".png", img.width, img.height))


if __name__ == "__main__":
    main()
