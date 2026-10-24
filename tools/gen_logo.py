#!/usr/bin/env python3
"""Re - Traveller : logo / icon pipeline.

Takes the painted crest in assets_src/raw_crest.png and bakes it down to a
genuine pixel-art bitmap for the launcher: crop -> integer downscale (box
averaging, which is the correct resampling for pixel art) -> palette snap to a
fixed 32-colour warm scheme -> hard-edged alpha.  No anti-aliasing survives.

Outputs
  launcher/ui/textures/logo_crest.png   128x128  (launcher title screen)
  launcher/icon/icon.png                512x512  (Android adaptive icon fg)
  launcher/icon/icon_bg.png             512x512  (Android adaptive icon bg)
"""
from __future__ import annotations

import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets_src", "raw_crest.png")
TEX = os.path.join(ROOT, "launcher", "ui", "textures")
ICON = os.path.join(ROOT, "launcher", "icon")

# Warm 32-colour crest palette: brass ramp, teal ramp, cream, deep ink.
PALETTE = [
    (26, 22, 18), (42, 30, 22), (62, 42, 30), (86, 56, 34),
    (112, 72, 40), (138, 92, 46), (166, 114, 52), (190, 138, 60),
    (214, 164, 78), (232, 190, 104), (246, 214, 140), (252, 234, 180),
    (255, 246, 214),
    # teal / deep green shading ramp
    (12, 44, 44), (18, 60, 58), (26, 80, 76), (36, 100, 92),
    (48, 122, 108), (66, 144, 122),
    # leaf greens
    (44, 76, 44), (62, 98, 52), (84, 122, 62), (110, 150, 78),
    # browns / leather
    (74, 48, 30), (98, 66, 38), (124, 86, 48), (150, 108, 62),
    # warm highlights
    (240, 206, 150), (222, 176, 116), (200, 152, 88), (176, 124, 66),
    (255, 252, 240),
]
BG = (5, 80, 79)          # flat teal of the source render
BG_OUT = (26, 80, 76)     # teal used for icon background plate


def snap(im: Image.Image, palette) -> Image.Image:
    """Nearest-palette snap (Euclidean in RGB). Keeps the art honest."""
    out = Image.new("RGB", im.size)
    ip, op = im.load(), out.load()
    cache: dict[tuple[int, int, int], tuple[int, int, int]] = {}
    for y in range(im.height):
        for x in range(im.width):
            c = ip[x, y][:3]
            got = cache.get(c)
            if got is None:
                best, bd = palette[0], 1 << 30
                for p in palette:
                    d = (c[0] - p[0]) ** 2 * 0.30 + (c[1] - p[1]) ** 2 * 0.59 + (c[2] - p[2]) ** 2 * 0.11
                    if d < bd:
                        bd, best = d, p
                got = best
                cache[c] = got
            op[x, y] = got
    return out


def bake(target: int) -> Image.Image:
    """crop the crest, integer-downscale, snap palette, rebuild alpha"""
    src = Image.open(SRC).convert("RGB")
    # content box of the crest (measured: 128,106 - 896,922)
    box = (120, 98, 904, 930)
    art = src.crop(box)
    # squish to a square canvas first so the crest is centred (it is 768x832)
    square = Image.new("RGB", (max(art.size), max(art.size)), BG)
    square.paste(art, ((square.width - art.width) // 2, (square.height - art.height) // 2))
    # integer box-downscale in two steps so huge ratios stay crisp
    cur = square
    while cur.width // 2 >= target:
        cur = cur.resize((cur.width // 2, cur.height // 2), Image.BOX)
    if cur.width != target:
        cur = cur.resize((target, target), Image.BOX)
    cur = snap(cur, PALETTE)

    # alpha: flood-fill the background teal inward from the border only, so the
    # shield's own teal field stays solid instead of becoming a hole
    rgba = cur.convert("RGBA")
    p = rgba.load()
    w, h = rgba.size
    seen = bytearray(w * h)
    stack = [(x, 0) for x in range(w)] + [(x, h - 1) for x in range(w)]
    stack += [(0, y) for y in range(h)] + [(w - 1, y) for y in range(h)]
    while stack:
        x, y = stack.pop()
        if not (0 <= x < w and 0 <= y < h):
            continue
        i = y * w + x
        if seen[i]:
            continue
        seen[i] = 1
        r, g, b, _ = p[x, y]
        if abs(r - BG[0]) + abs(g - BG[1]) + abs(b - BG[2]) < 60:
            p[x, y] = (r, g, b, 0)
            stack += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    return rgba


def make_icon(crest: Image.Image) -> None:
    """Adaptive icon: 512 fg (crest with safe-zone padding) + 512 bg plate."""
    os.makedirs(ICON, exist_ok=True)
    fg = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    # adaptive-icon safe zone is the centre 66%: keep the crest inside ~384px
    inner = bake(384)
    fg.paste(inner, ((512 - inner.width) // 2, (512 - inner.height) // 2), inner)
    fg.save(os.path.join(ICON, "icon.png"))

    bg = Image.new("RGBA", (512, 512), BG_OUT + (255,))
    # subtle storybook vignette + woven texture for the background plate
    d = bg.load()
    for y in range(512):
        for x in range(512):
            nx = abs(x - 256) / 256
            ny = abs(y - 256) / 256
            k = min(1.0, (nx * nx + ny * ny) ** 1.6)
            r, g, b, a = d[x, y]
            f = 1.0 - 0.42 * k
            if (x // 4 + y // 4) % 2 == 0:
                f *= 1.04
            d[x, y] = (int(r * f), int(g * f), int(b * f), 255)
    bg.save(os.path.join(ICON, "icon_bg.png"))


def main():
    os.makedirs(TEX, exist_ok=True)
    crest256 = bake(256)
    crest256.save(os.path.join(TEX, "logo_crest.png"))
    print("logo_crest.png 256x256")
    crest256.resize((128, 128), Image.NEAREST).save(os.path.join(TEX, "logo_crest_128.png"))
    print("logo_crest_128.png 128x128 (exact 2:1 from the 256 master)")
    crest256.resize((64, 64), Image.NEAREST).save(os.path.join(TEX, "logo_crest_small.png"))
    print("logo_crest_small.png 64x64")
    make_icon(crest256)
    print("icon.png / icon_bg.png 512x512")


if __name__ == "__main__":
    main()
