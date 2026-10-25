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
    """A speck of pollen caught in a sunbeam: 4x4, cream, one soft rim pixel.

    Smooth alpha, not dithered. A dithered 5x5 magnified to 0.10 m reads as a
    checkerboard of little squares floating in the air - the first capture of
    phase 6 was full of them (see DESIGN_NOTES.md §15).
    """
    w = h = 4
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    for y in range(h):
        for x in range(w):
            dx, dy = x - 1.5, y - 1.5
            d = (dx * dx + dy * dy) ** 0.5
            if d <= 1.0:
                px[x, y] = (252, 243, 216, 255)
            elif d <= 1.8:
                px[x, y] = (250, 238, 210, 120)
            else:
                px[x, y] = (250, 238, 210, 40)
    return img


def firefly() -> Image.Image:
    """Warm lamp-glow bug: 11x11, gold core fading to amber, additive.

    Light is continuous, so this sprite's alpha is smooth on purpose; a dithered
    halo around forty of them turned the night into a field of grey squares.
    Four soft rings keep the dot round instead of square when it is magnified.
    """
    w = h = 11
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    for y in range(h):
        for x in range(w):
            dx, dy = x - 5, y - 5
            d = (dx * dx + dy * dy) ** 0.5
            if d > 5.1:
                continue
            if d <= 1.2:
                px[x, y] = (255, 248, 206, 255)
            elif d <= 2.4:
                px[x, y] = (252, 224, 140, 215)
            elif d <= 3.6:
                px[x, y] = (238, 184, 88, 140)
            else:
                px[x, y] = (206, 142, 58, 70)
    return img


def petal() -> Image.Image:
    """A leaf on the wind: 12x7, gold-to-rust, pointed tip, 1 px dark lip.

    Was 6x4, which magnified into an orange square. A leaf has to read as a leaf
    even when it is twenty screen pixels wide - that is the whole point of it.
    """
    w, h = 12, 7
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    body = [
        ".....##.....",
        "...####.....",
        "..######....",
        ".########...",
        "..######....",
        "...####.....",
        ".....##.....",
    ]
    dark = (126, 74, 38, 240)
    mid = (196, 126, 60, 250)
    light = (232, 174, 92, 250)
    for y in range(h):
        row = body[y]
        for x in range(w):
            if row[x] != "#":
                continue
            edge = (
                x == 0 or x == w - 1 or row[x - 1] != "#" or row[x + 1] != "#"
                or y == 0 or y == h - 1
            )
            if edge:
                px[x, y] = dark
            elif x <= 3:
                px[x, y] = light
            else:
                px[x, y] = mid
    return img


def _value_noise(x: int, y: int, seed: int) -> float:
    """Cheap deterministic hash noise, 0..1 - breaks the perfect ellipse up."""
    n = (x * 374761393 + y * 668265263 + seed * 2654435761) & 0xFFFFFFFF
    n = (n ^ (n >> 13)) * 1274126177 & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


def fog_puff() -> Image.Image:
    """Ground mist: 96x40 soft ellipse, cream-grey, smooth alpha with noise.

    Smooth on purpose. This quad is seven metres wide, so a dithered alpha turns
    into a visible grid of squares across half the screen - which is exactly what
    the first version did (DESIGN_NOTES §15).
    """
    w, h = 96, 40
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    for y in range(h):
        for x in range(w):
            nx = (x - (w - 1) / 2.0) / (w / 2.0)
            ny = (y - (h - 1) / 2.0) / (h / 2.0)
            d = (nx * nx + ny * ny) ** 0.5
            if d >= 1.0:
                continue
            cover = (1.0 - d) ** 1.8
            wobble = 0.72 + 0.28 * _value_noise(x // 3, y // 3, 7)
            a = int(255 * cover * wobble * 0.55)
            if a <= 0:
                continue
            warm = 236 - int(16 * ny)
            px[x, y] = (warm, warm - 5, warm - 14, a)
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
