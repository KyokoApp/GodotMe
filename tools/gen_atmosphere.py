#!/usr/bin/env python3
"""Re - Traveller : atmosphere sprites (dust, petal, firefly, fog puff).

The game may not *draw* a particle at runtime - the project rule is that every
visual is a real PNG. These four tiny textures are the exception that proves the
rule: they are generated here, once, by a script that is committed next to the
PNGs it produces, exactly like `tools/gen_ui_kit.py` does for the launcher.

Style rules they follow (docs/DESIGN_NOTES.md §1):
  * warm palette only - cream, amber, gold, moss. No blue/neon glow;
  * hard pixels, no anti-aliasing, no smooth gradients that read as blurry;
  * alpha is dithered by hand (Bayer 4x4) so a soft-looking sprite still snaps
    to the pixel grid instead of turning into a grey smudge at 0.05 m.

Run (Pillow needed):
    python3 tools/gen_atmosphere.py
"""
from __future__ import annotations

import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "game", "game", "world", "textures", "atmosphere")

BAYER = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
]


def _bayer(x: int, y: int) -> float:
    """0..1 ordered-dither threshold for a pixel."""
    return (BAYER[y % 4][x % 4] + 0.5) / 16.0


def _dither_alpha(base: float, x: int, y: int) -> int:
    """Turn a smooth 0..1 coverage into a hard pixel either fully on or off."""
    return 255 if base > _bayer(x, y) else 0


def mote_dust() -> Image.Image:
    """A speck of pollen caught in a sunbeam: 5x5, cream, no outline."""
    w = h = 5
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    core = (250, 238, 210)
    for y in range(h):
        for x in range(w):
            dx, dy = x - 2, y - 2
            d = (dx * dx + dy * dy) ** 0.5
            if d > 2.2:
                continue
            if d > 1.1 and _dither_alpha(0.55 - (d - 1.1) * 0.5, x, y) == 0:
                continue
            px[x, y] = core + (255 if d <= 1.1 else 170,)
    return img


def firefly() -> Image.Image:
    """Warm lamp-glow bug: 7x7, gold core fading to amber. Additive-safe."""
    w = h = 7
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    for y in range(h):
        for x in range(w):
            dx, dy = x - 3, y - 3
            d = (dx * dx + dy * dy) ** 0.5
            if d > 3.2:
                continue
            if d <= 1.2:
                px[x, y] = (255, 244, 190, 255)
            elif d <= 2.2:
                px[x, y] = (248, 206, 104, 235) if _dither_alpha(0.9, x, y) else (0, 0, 0, 0)
            else:
                px[x, y] = (214, 150, 58, 140) if _dither_alpha(0.55, x, y) else (0, 0, 0, 0)
    return img


def petal() -> Image.Image:
    """A leaf/petal on the wind: 6x4, gold-to-rust, hard edge, 1 px dark lip."""
    w, h = 6, 4
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    rows = [
        "..##..",
        ".####.",
        ".####.",
        "..##..",
    ]
    for y in range(h):
        for x in range(w):
            if rows[y][x] != "#":
                continue
            if y == 0 or y == 3 or x == 1 or x == 4:
                px[x, y] = (150, 88, 44, 235)
            elif x <= 2:
                px[x, y] = (226, 168, 88, 250)
            else:
                px[x, y] = (198, 132, 66, 250)
    return img


def fog_puff() -> Image.Image:
    """Ground mist: 40x24 soft ellipse, cream-grey, dithered so it stays pixel."""
    w, h = 40, 24
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    for y in range(h):
        for x in range(w):
            nx = (x - (w - 1) / 2.0) / (w / 2.0)
            ny = (y - (h - 1) / 2.0) / (h / 2.0)
            d = (nx * nx + ny * ny) ** 0.5
            if d >= 1.0:
                continue
            cover = (1.0 - d) ** 1.6
            if _dither_alpha(cover, x, y) == 0:
                continue
            warm = 232 - int(18 * ny)
            px[x, y] = (warm, warm - 6, warm - 16, 150)
    return img


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    for name, maker in (
        ("mote_dust.png", mote_dust),
        ("firefly.png", firefly),
        ("petal.png", petal),
        ("fog_puff.png", fog_puff),
    ):
        img = maker()
        path = os.path.join(OUT, name)
        img.save(path)
        print("wrote %-14s %dx%d" % (name, img.width, img.height))


if __name__ == "__main__":
    main()
