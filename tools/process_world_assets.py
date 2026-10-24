#!/usr/bin/env python3
"""Turn the generated world art in assets_src/world into game-ready textures.

The source images are AI-generated bitmap illustrations on a flat magenta
chroma key. This script does the mechanical, repeatable part:

  * removes the chroma key with a feathered tolerance (no white halo),
  * crops to the sprite's real bounds,
  * downscales with LANCZOS and then quantises to a small palette, which is what
    turns an illustration into a crisp pixel-art sprite of the target size,
  * keeps a hard alpha edge (pixel art has no soft shadows),
  * makes the ground tile wrap seamlessly (edge blend in both axes).

Everything is deterministic: run it again and you get byte-identical PNGs.

    python3 tools/process_world_assets.py
    python3 tools/process_world_assets.py --only tree_pine
"""
from __future__ import annotations

import argparse
import os
import sys

from PIL import Image

SRC = os.path.join(os.path.dirname(__file__), "..", "assets_src", "world")
OUT = os.path.join(os.path.dirname(__file__), "..", "game", "game", "world", "textures")

# name -> (output width, output height, palette size)
SPRITES = {
    "tree_pine": (192, 320, 26),
    "tree_oak": (320, 240, 30),
    "bush": (112, 88, 22),
    "rock": (144, 96, 22),
    "cottage": (352, 264, 32),
}

# tiles: name -> palette size
TILES = {"grass_tile": 32, "path_tile": 26}
TILE_SIZE = 256


def chroma_key(img: Image.Image) -> Image.Image:
    """Drop the magenta key. Alpha is binary on purpose: pixel art, not a cutout."""
    img = img.convert("RGBA")
    px = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, _ = px[x, y]
            # magenta: strong red+blue, weak green. Distance-based so in-sprite
            # purples (there are none in this palette) are not eaten by accident.
            spill = min(r, b) - g
            if spill > 70:
                px[x, y] = (0, 0, 0, 0)
            elif spill > 40:
                # anti-aliased rim pixel: keep the colour but let it fade
                px[x, y] = (r, g, b, 120)
            else:
                px[x, y] = (r, g, b, 255)
    return img


def trim(img: Image.Image) -> Image.Image:
    bbox = img.getbbox()
    return img.crop(bbox) if bbox else img


def pixelate(img: Image.Image, size: tuple[int, int], colors: int) -> Image.Image:
    """Downscale + quantise: the standard way to get crisp game pixel art."""
    alpha = img.getchannel("A")
    small = img.resize(size, Image.LANCZOS)
    # quantise only RGB, then re-apply a hard alpha mask
    rgb = small.convert("RGB")
    quant = rgb.quantize(colors=colors, method=Image.MEDIANCUT, dither=Image.NONE)
    out = quant.convert("RGBA")
    mask = alpha.resize(size, Image.LANCZOS).point(lambda v: 255 if v > 110 else 0)
    out.putalpha(mask)
    return out


def make_seamless(img: Image.Image, blend: int = 48) -> Image.Image:
    """Blend opposite edges so the texture wraps without a visible seam."""
    img = img.convert("RGB")
    w, h = img.size
    px = img.load()

    def mix(a: tuple[int, int, int], b: tuple[int, int, int], t: float):
        return tuple(int(round(a[i] * (1 - t) + b[i] * t)) for i in range(3))

    # horizontal wrap
    for y in range(h):
        for i in range(blend):
            t = i / (blend - 1) * 0.5
            left = px[i, y]
            right = px[w - 1 - i, y]
            px[i, y] = mix(left, right, t)
            px[w - 1 - i, y] = mix(right, left, t)
    # vertical wrap (uses the already-blended rows)
    for x in range(w):
        for i in range(blend):
            t = i / (blend - 1) * 0.5
            top = px[x, i]
            bottom = px[x, h - 1 - i]
            px[x, i] = mix(top, bottom, t)
            px[x, h - 1 - i] = mix(bottom, top, t)
    return img


def save(img: Image.Image, name: str) -> None:
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".png")
    img.save(path, optimize=True)
    print("  %-14s %4dx%-4d %8d bytes" % (name + ".png", img.width, img.height,
                                          os.path.getsize(path)))


def ground(name: str, colors: int) -> None:
    src = Image.open(os.path.join(SRC, name + ".png"))
    tile = src.convert("RGB").resize((TILE_SIZE, TILE_SIZE), Image.LANCZOS)
    tile = make_seamless(tile, blend=40)
    tile = tile.quantize(colors=colors, method=Image.MEDIANCUT, dither=Image.NONE).convert("RGB")
    save(tile, name)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="", help="process a single sprite")
    args = ap.parse_args()

    if not os.path.isdir(SRC):
        print("missing source dir %s" % SRC, file=sys.stderr)
        return 1
    print("Re - Traveller world textures ->", os.path.normpath(OUT))
    names = [args.only] if args.only else list(SPRITES)
    for name in names:
        src_path = os.path.join(SRC, name + ".png")
        if not os.path.exists(src_path):
            print("  skip %s (no source)" % name)
            continue
        img = trim(chroma_key(Image.open(src_path)))
        save(pixelate(img, SPRITES[name][:2], SPRITES[name][2]), name)
    for name, colors in TILES.items():
        if args.only and args.only != name:
            continue
        if os.path.exists(os.path.join(SRC, name + ".png")):
            ground(name, colors)
    print("done")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
