#!/usr/bin/env python3
"""Re - Traveller : launcher backdrop, glow, scrim and boot splash.

Sources are the painted originals in assets_src/. Everything produced here is a
bitmap PNG (nearest filtered at runtime) - no procedural drawing happens in the
game itself.

Run: python3 tools/gen_backdrop.py
"""
from __future__ import annotations

import io
import os
import tempfile

from PIL import Image, ImageDraw, ImageFont
from fontTools.ttLib import TTFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEX = os.path.join(ROOT, "launcher", "ui", "textures")
FONTS = os.path.join(ROOT, "launcher", "ui", "fonts")
SRC = os.path.join(ROOT, "assets_src")

CREAM = (250, 240, 214, 255)
BRASS = (232, 190, 104, 255)
INK = (26, 20, 16, 255)


def crop_16_9(im: Image.Image) -> Image.Image:
    w, h = im.size
    target = 16 / 9
    if w / h > target:
        nw = int(h * target)
        return im.crop(((w - nw) // 2, 0, (w - nw) // 2 + nw, h))
    nh = int(w / target)
    return im.crop((0, (h - nh) // 2, w, (h - nh) // 2 + nh))


def make_bg() -> None:
    src = Image.open(os.path.join(SRC, "raw_bg_a.png")).convert("RGB")
    art = crop_16_9(src)
    # Two-step box reduction keeps the painted pixel clusters readable at 720p
    big = art.resize((2560, 1440), Image.LANCZOS)
    out = big.resize((1280, 720), Image.BOX)
    out.save(os.path.join(TEX, "bg_sky.png"))
    print("bg_sky.png 1280x720")

    # darkened variant used behind the modal / as a fallback
    dark = out.point(lambda v: int(v * 0.62))
    dark.save(os.path.join(TEX, "bg_sky_dim.png"))
    print("bg_sky_dim.png 1280x720")


def make_glow() -> None:
    size = 128
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = im.load()
    c = (size - 1) / 2
    for y in range(size):
        for x in range(size):
            d = ((x - c) ** 2 + (y - c) ** 2) ** 0.5 / c
            a = max(0.0, 1.0 - d) ** 2.6
            # band the alpha in 6 steps: stays in the pixel-art idiom
            a = round(a * 6) / 6
            if a <= 0:
                continue
            px[x, y] = (255, 226, 158, int(a * 220))
    im.save(os.path.join(TEX, "fx_glow.png"))
    print("fx_glow.png 128x128")


def make_scrim() -> None:
    """L-shaped warm scrim so parchment-free text always stays legible."""
    W, H = 256, 144
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = im.load()
    for y in range(H):
        for x in range(W):
            nx = x / (W - 1)
            ny = y / (H - 1)
            # a soft left wash for the title column, plus a gentle bottom fade.
            # 32 alpha steps keeps it banded-but-smooth instead of blocky.
            left = max(0.0, 1.0 - nx / 0.34) ** 1.15
            bottom = max(0.0, (ny - 0.62) / 0.38) ** 1.7
            a = min(0.82, left * 0.66 + bottom * 0.34)
            if a > 0:
                px[x, y] = (20, 14, 11, int(a * 255))
    im.save(os.path.join(TEX, "overlay_scrim_left.png"))
    print("overlay_scrim_left.png 256x144")


# ------------------------------------------------------------------ splash ---
def _ttf_from_woff2(woff2_path: str) -> str:
    font = TTFont(woff2_path)
    font.flavor = None
    fd, tmp = tempfile.mkstemp(suffix=".ttf")
    os.close(fd)
    font.save(tmp)
    return tmp


def pixel_text(text: str, font_path: str, size: int, color) -> Image.Image:
    """Render text at 4x then box-downscale + alpha threshold = hard pixel edges."""
    scale = 4
    f = ImageFont.truetype(font_path, size * scale)
    box = f.getbbox(text)
    w = max(1, box[2] - box[0])
    h = max(1, box[3] - box[1])
    big = Image.new("L", (w + 8, h + 8), 0)
    d = ImageDraw.Draw(big)
    d.text((4 - box[0], 4 - box[1]), text, font=f, fill=255)
    small = big.resize((max(1, big.width // scale), max(1, big.height // scale)), Image.BOX)
    small = small.point(lambda v: 255 if v >= 128 else 0)
    out = Image.new("RGBA", small.size, color[:3] + (0,))
    out.putalpha(small)
    return out


def make_splash() -> None:
    """Boot splash: crest on a warm wash. Text is rendered live by the scene so
    the real font is always crisp and can be localised."""
    W, H = 960, 540
    im = Image.new("RGBA", (W, H), (26, 20, 16, 255))
    px = im.load()
    cx, cy = W * 0.5, H * 0.5
    for y in range(H):
        for x in range(W):
            d = (((x - cx) / (W * 0.58)) ** 2 + ((y - cy) / (H * 0.58)) ** 2) ** 0.5
            k = max(0.0, 1.0 - d) ** 1.6
            px[x, y] = (int(26 + 36 * k), int(20 + 27 * k), int(16 + 13 * k), 255)
    crest = Image.open(os.path.join(TEX, "logo_crest.png")).convert("RGBA")
    wm = Image.open(os.path.join(TEX, "logo_wordmark.png")).convert("RGBA")
    total_h = crest.height + 26 + wm.height
    top = int(cy - total_h / 2)
    im.alpha_composite(crest, (int(cx - crest.width / 2), top))
    im.alpha_composite(wm, (int(cx - wm.width / 2), top + crest.height + 26))
    im.convert("RGB").save(os.path.join(TEX, "splash_boot.png"))
    print("splash_boot.png 960x540 (crest only)")


def make_wordmark() -> None:
    """'RE - TRAVELLER' set in the logo face with wide tracking, baked to pixels."""
    ttf = _ttf_from_woff2(os.path.join(FONTS, "PixelifySans-SemiBold.woff2"))
    try:
        text = "RE - TRAVELLER"
        size = 64
        scale = 4
        f = ImageFont.truetype(ttf, size * scale)
        tracking = int(size * 0.18) * scale
        # measure
        widths = []
        for ch in text:
            bb = f.getbbox(ch if ch != " " else "n")
            widths.append(f.getlength(ch) if ch != " " else f.getlength("n") * 0.55)
        total = int(sum(widths) + tracking * (len(text) - 1)) + 8 * scale
        h = int(size * scale * 1.5)
        big = Image.new("L", (total, h), 0)
        d = ImageDraw.Draw(big)
        x = 4 * scale
        for ch, w in zip(text, widths):
            if ch != " ":
                d.text((x, 2 * scale), ch, font=f, fill=255)
            x += w + tracking
        small = big.resize((max(1, big.width // scale), max(1, big.height // scale)), Image.BOX)
        small = small.point(lambda v: 255 if v >= 128 else 0)
        # trim empty rows/cols
        bbox = small.getbbox()
        small = small.crop(bbox)
        # cream fill with a warm drop shadow two pixels down
        out = Image.new("RGBA", (small.width, small.height + 2), (0, 0, 0, 0))
        shadow = Image.new("RGBA", small.size, (26, 16, 10, 200))
        shadow.putalpha(small.point(lambda v: 200 if v else 0))
        out.alpha_composite(shadow, (0, 2))
        cream = Image.new("RGBA", small.size, CREAM)
        cream.putalpha(small)
        out.alpha_composite(cream, (0, 0))
        out.save(os.path.join(TEX, "logo_wordmark.png"))
        print("logo_wordmark.png %dx%d" % out.size)
    finally:
        os.remove(ttf)


def main():
    os.makedirs(TEX, exist_ok=True)
    make_wordmark()
    make_bg()
    make_glow()
    make_scrim()
    make_splash()


if __name__ == "__main__":
    main()
