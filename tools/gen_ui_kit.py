#!/usr/bin/env python3
"""Re - Traveller : pixel-art UI kit generator.

Produces the launcher's 9-slice panels, buttons, bars, icons and ornaments as
real PNG bitmaps (nearest-filtered, no anti-aliasing, no gradients-as-blur).

Style guide (see docs/DESIGN_NOTES.md):
  * warm storybook palette - parchment, walnut wood, aged brass, deep teal ink
  * 1px dark outline in warm brown (never pure black)
  * light comes from the upper-left, so bevels are light on top/left
  * every shape is drawn on an integer pixel grid

Run:  python3 tools/gen_ui_kit.py
"""
from __future__ import annotations

import os
import random
from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "launcher", "ui", "textures")

# ---------------------------------------------------------------- palette ----
INK        = (42, 28, 22, 255)      # warm near-black outline
INK_SOFT   = (58, 40, 30, 255)
WOOD_D     = (58, 38, 26, 255)
WOOD_M     = (92, 60, 38, 255)
WOOD_L     = (128, 86, 52, 255)
WOOD_H     = (162, 116, 70, 255)
PARCH_D    = (186, 156, 112, 255)
PARCH_M    = (222, 198, 152, 255)
PARCH_L    = (243, 228, 192, 255)
PARCH_H    = (252, 244, 220, 255)
BRASS_D    = (124, 84, 38, 255)
BRASS_M    = (188, 138, 60, 255)
BRASS_L    = (232, 190, 104, 255)
BRASS_H    = (252, 232, 170, 255)
TEAL_D     = (26, 62, 58, 255)
TEAL_M     = (38, 92, 84, 255)
TEAL_L     = (58, 126, 112, 255)
RUST_D     = (104, 42, 32, 255)
RUST_M     = (156, 64, 44, 255)
RUST_L     = (204, 96, 62, 255)
GREEN_D    = (44, 74, 44, 255)
GREEN_M    = (74, 112, 62, 255)
GREEN_L    = (118, 154, 84, 255)
CREAM      = (250, 240, 214, 255)
TRANSP     = (0, 0, 0, 0)


# --------------------------------------------------------------- helpers -----
def new(w, h):
    return Image.new("RGBA", (w, h), TRANSP)


def px(im, x, y, c):
    if 0 <= x < im.width and 0 <= y < im.height:
        im.putpixel((x, y), c)


def rect(im, x0, y0, x1, y1, c):
    """filled rect, inclusive coords"""
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            px(im, x, y, c)


def rect_ring(im, x0, y0, x1, y1, c, t=1):
    for i in range(t):
        rect(im, x0 + i, y0 + i, x1 - i, y0 + i, c)
        rect(im, x0 + i, y1 - i, x1 - i, y1 - i, c)
        rect(im, x0 + i, y0 + i, x0 + i, y1 - i, c)
        rect(im, x1 - i, y0 + i, x1 - i, y1 - i, c)


def rr_mask(w, h, r):
    """rounded-rect inside test, hard pixel edges (no AA)"""
    im = Image.new("L", (w, h), 0)
    p = im.load()
    for y in range(h):
        for x in range(w):
            cx = min(x, w - 1 - x)
            cy = min(y, h - 1 - y)
            if cx >= r or cy >= r:
                p[x, y] = 255
                continue
            # circle of radius r centred at (r, r)
            dx = r - cx
            dy = r - cy
            # +0.5 bias keeps corners a touch fuller, reads better at 1x
            if (dx - 0.5) ** 2 + (dy - 0.5) ** 2 <= r * r:
                p[x, y] = 255
    return im


def rr(im, x0, y0, x1, y1, r, c):
    m = rr_mask(x1 - x0 + 1, y1 - y0 + 1, r)
    layer = Image.new("RGBA", (x1 - x0 + 1, y1 - y0 + 1), c)
    im.paste(layer, (x0, y0), m)


def rr_ring(im, x0, y0, x1, y1, r, c, t=1):
    w, h = x1 - x0 + 1, y1 - y0 + 1
    outer = rr_mask(w, h, r)
    inner = rr_mask(w - 2 * t, h - 2 * t, max(0, r - t))
    big = Image.new("L", (w, h), 0)
    big.paste(inner, (t, t))
    layer = Image.new("RGBA", (w, h), c)
    diff = Image.new("L", (w, h))
    o, b, d = outer.load(), big.load(), diff.load()
    for y in range(h):
        for x in range(w):
            d[x, y] = 255 if (o[x, y] and not b[x, y]) else 0
    im.paste(layer, (x0, y0), diff)


def shade_bevel(im, x0, y0, x1, y1, r, t, light, dark, base=None):
    """bevel band of thickness t just inside the outer edge"""
    w, h = x1 - x0 + 1, y1 - y0 + 1
    outer = rr_mask(w, h, r)
    inner = rr_mask(w - 2 * t, h - 2 * t, max(0, r - t))
    o = outer.load()
    inn = Image.new("L", (w, h), 0)
    inn.paste(inner, (t, t))
    i = inn.load()
    lay = Image.new("RGBA", (w, h), TRANSP)
    lp = lay.load()
    for y in range(h):
        for x in range(w):
            if o[x, y] and not i[x, y]:
                # which side of the band: compare to band centre-line
                # top/left half -> light, bottom/right -> dark
                if (y - 0) < (h - 1 - y) and (x - 0) < (w - 1 - x):
                    lp[x, y] = light
                elif (y < t) or (x < t):
                    lp[x, y] = light
                elif (y > h - 1 - t) or (x > w - 1 - t):
                    lp[x, y] = dark
                else:
                    lp[x, y] = dark
    im.paste(lay, (x0, y0), lay)


def hline(im, x0, x1, y, c):
    rect(im, x0, y, x1, y, c)


def dither_fill(im, x0, y0, x1, y1, c, seed, density=0.06, step=2):
    rnd = random.Random(seed)
    for y in range(y0, y1 + 1, step):
        for x in range(x0, x1 + 1, step):
            if rnd.random() < density:
                px(im, x, y, c)


def sparkle(im, cx, cy, size, col_core=BRASS_H, col_arm=BRASS_M, wrap=None):
    """4-point star, integer symmetric"""
    px(im, cx, cy, col_core)
    if size >= 2:
        for d in (1, 2):
            col = col_arm if d == 2 else col_core
            for sx, sy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                px(im, cx + sx * d, cy + sy * d, col)
    if size >= 3:
        for sx, sy in ((1, 1), (-1, 1), (1, -1), (-1, -1)):
            px(im, cx + sx, cy + sy, col_arm)


def save(im, name):
    path = os.path.join(OUT, name)
    os.makedirs(OUT, exist_ok=True)
    im.save(path)
    print("  %-28s %dx%d" % (name, im.width, im.height))


# ---------------------------------------------------------------- panels -----
def panel_parchment():
    """Nine-patch parchment card. margin 20 -> 24x24 seamless centre tile."""
    w = h = 64
    m = 20
    im = new(w, h)
    rr(im, 0, 0, w - 1, h - 1, 10, INK)              # outline
    rr(im, 1, 1, w - 2, h - 2, 9, BRASS_D)           # brass frame
    rr(im, 2, 2, w - 3, h - 3, 9, BRASS_M)
    rr(im, 3, 3, w - 4, h - 4, 8, BRASS_L)
    rr(im, 4, 4, w - 5, h - 5, 8, BRASS_M)
    rr(im, 5, 5, w - 6, h - 6, 7, BRASS_D)           # frame bottom shading
    rr(im, 6, 6, w - 7, h - 7, 7, INK_SOFT)          # groove
    rr(im, 7, 7, w - 8, h - 8, 6, PARCH_D)           # parchment field
    rr(im, 8, 8, w - 9, h - 9, 6, PARCH_M)
    # deliberately no interior noise: a 9-sliced centre is stretched, so any
    # per-pixel texture would smear into blocks. Warm flat parchment it is.
    # inner shadow at the top of the field + light at the bottom
    for x in range(9, w - 9):
        if im.getpixel((x, 8))[3]:
            px(im, x, 8, PARCH_D)
    for x in range(9, w - 9):
        if im.getpixel((x, h - 9))[3]:
            px(im, x, h - 9, PARCH_L)
    for y in range(9, h - 9):
        if im.getpixel((8, y))[3]:
            px(im, 8, y, PARCH_D)
    # corner rivets (inside the 20px margin so 9-slice keeps them put)
    for cx, cy in ((11, 11), (w - 12, 11), (11, h - 12), (w - 12, h - 12)):
        px(im, cx, cy, BRASS_H)
        px(im, cx - 1, cy, BRASS_L)
        px(im, cx, cy - 1, BRASS_L)
        px(im, cx + 1, cy, BRASS_D)
        px(im, cx, cy + 1, BRASS_D)
        px(im, cx - 1, cy - 1, INK_SOFT)
        px(im, cx + 1, cy + 1, INK_SOFT)
    save(im, "panel_parchment.png")


def panel_ink():
    """Dark carte-ink panel for logs / status strips."""
    w = h = 48
    pad = 14
    im = new(w, h)
    rr(im, 0, 0, w - 1, h - 1, 8, INK)
    rr(im, 1, 1, w - 2, h - 2, 7, BRASS_D)
    rr(im, 2, 2, w - 3, h - 3, 7, TEAL_D)
    rr(im, 3, 3, w - 4, h - 4, 6, (32, 52, 50, 255))
    save(im, "panel_ink.png")


def button_wood():
    for state, top, mid, bot, edge in (
        ("normal",  WOOD_H, WOOD_M, WOOD_D, INK),
        ("hover",   (196, 148, 92, 255), (128, 86, 52, 255), WOOD_D, INK),
    ):
        w, h = 64, 32
        im = new(w, h)
        rr(im, 0, 0, w - 1, h - 1, 7, edge)
        rr(im, 1, 1, w - 2, h - 2, 6, BRASS_D)
        rr(im, 2, 2, w - 3, h - 3, 6, top)
        rr(im, 3, 3, w - 4, h - 4, 5, mid)
        # bevel
        hline(im, 4, w - 5, 3, top)
        hline(im, 4, w - 5, h - 4, bot)
        # plank grain
        rnd = random.Random(11)
        for y in range(5, h - 5):
            if rnd.random() < 0.30:
                x0 = rnd.randint(4, w - 10)
                ln = rnd.randint(3, 9)
                hline(im, x0, min(x0 + ln, w - 5), y, WOOD_D)
        # two brass studs
        for cx in (8, w - 9):
            cy = h // 2
            px(im, cx, cy - 1, BRASS_H)
            px(im, cx - 1, cy, BRASS_L)
            px(im, cx, cy, BRASS_L)
            px(im, cx + 1, cy, BRASS_D)
            px(im, cx - 1, cy + 1, BRASS_D)
            px(im, cx, cy + 1, BRASS_D)
        save(im, "button_wood_%s.png" % state)

    # pressed: sink the plate by moving the bevel
    w, h = 64, 32
    im = new(w, h)
    rr(im, 0, 0, w - 1, h - 1, 7, INK)
    rr(im, 1, 1, w - 2, h - 2, 6, BRASS_D)
    rr(im, 2, 2, w - 3, h - 3, 6, WOOD_D)
    rr(im, 3, 3, w - 4, h - 4, 5, WOOD_M)
    hline(im, 4, w - 5, 3, WOOD_D)
    hline(im, 4, w - 5, h - 4, WOOD_H)
    rnd = random.Random(12)
    for y in range(5, h - 5):
        if rnd.random() < 0.25:
            x0 = rnd.randint(4, w - 10)
            hline(im, x0, min(x0 + 6, w - 5), y, (70, 46, 30, 255))
    save(im, "button_wood_pressed.png")


def button_gold():
    """Primary action - the Main / Play button."""
    for state, t, m, b in (
        ("normal", BRASS_H, BRASS_L, BRASS_M),
        ("hover",  (255, 244, 200, 255), BRASS_H, BRASS_L),
        ("pressed", BRASS_L, BRASS_M, BRASS_D),
    ):
        w, h = 96, 40
        im = new(w, h)
        rr(im, 0, 0, w - 1, h - 1, 9, INK)
        rr(im, 1, 1, w - 2, h - 2, 8, BRASS_D)
        rr(im, 2, 2, w - 3, h - 3, 8, t)
        rr(im, 3, 3, w - 4, h - 4, 7, m)
        rr(im, 4, 4, w - 5, h - 5, 6, b if state != "pressed" else m)
        hline(im, 5, w - 6, 4, t)
        # engraved inner line
        rr_ring(im, 6, 6, w - 7, h - 7, 5, BRASS_D)
        # corner flourishes
        for cx, cy in ((9, 9), (w - 10, 9), (9, h - 10), (w - 10, h - 10)):
            px(im, cx, cy, BRASS_H)
            px(im, cx - 1, cy, BRASS_D)
            px(im, cx + 1, cy, BRASS_D)
            px(im, cx, cy - 1, BRASS_D)
            px(im, cx, cy + 1, BRASS_D)
        save(im, "button_gold_%s.png" % state)


def progress_bar():
    # track: dark recessed channel, 9-slice, margin 8
    w, h = 64, 20
    im = new(w, h)
    rr(im, 0, 0, w - 1, h - 1, 6, INK)
    rr(im, 1, 1, w - 2, h - 2, 5, BRASS_D)
    rr(im, 2, 2, w - 3, h - 3, 4, (28, 34, 30, 255))
    rr(im, 3, 3, w - 4, h - 4, 4, (20, 26, 24, 255))
    hline(im, 4, w - 5, 3, (12, 16, 14, 255))
    save(im, "bar_track.png")

    # fill: warm brass, one highlight band, one shadow band. No interior detail
    # because the 9-slice centre is stretched horizontally.
    im = new(w, h)
    rr(im, 0, 0, w - 1, h - 1, 5, BRASS_M)
    rr(im, 1, 1, w - 2, h - 5, 5, BRASS_L)
    hline(im, 2, w - 3, 1, BRASS_H)
    hline(im, 2, w - 3, 2, BRASS_H)
    hline(im, 1, w - 2, h - 3, BRASS_M)
    hline(im, 1, w - 2, h - 2, BRASS_D)
    save(im, "bar_fill.png")

    # glowing tip cap
    im = new(10, 20)
    rect(im, 0, 2, 9, 17, (255, 236, 178, 255))
    rect(im, 2, 4, 9, 15, CREAM)
    rect(im, 0, 5, 0, 14, BRASS_H)
    save(im, "bar_cap.png")


# ----------------------------------------------------------------- icons -----
def icon_frame():
    """Iron thumbnail frame for the crest/logo."""
    s = 64
    im = new(s, s)
    rr(im, 0, 0, s - 1, s - 1, 12, INK)
    rr(im, 1, 1, s - 2, s - 2, 11, BRASS_M)
    rr(im, 2, 2, s - 3, s - 3, 10, BRASS_L)
    rr(im, 3, 3, s - 4, s - 4, 10, BRASS_M)
    rr(im, 4, 4, s - 5, s - 5, 9, BRASS_D)
    rr(im, 5, 5, s - 6, s - 6, 8, INK)
    rr(im, 6, 6, s - 7, s - 7, 8, TEAL_D)
    rr(im, 7, 7, s - 8, s - 8, 7, TRANSP)
    for cx, cy in ((10, 10), (s - 11, 10), (10, s - 11), (s - 11, s - 11)):
        sparkle(im, cx, cy, 2, BRASS_H, BRASS_M)
    save(im, "icon_frame.png")


def icons():
    S = 24
    # play
    im = new(S, S)
    for i in range(11):
        y0, y1 = 4 + i, 4 + i
        yy = 19 - i
        rect(im, 6 + i, y0, 6 + i, yy, CREAM)
    # outline
    out = []
    for y in range(S):
        for x in range(S):
            if im.getpixel((x, y))[3]:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < S and 0 <= ny < S and not im.getpixel((nx, ny))[3]:
                        out.append((nx, ny))
    for x, y in out:
        px(im, x, y, INK)
    save(im, "icon_play.png")

    # retry (circular arrow)
    im = new(S, S)
    cx, cy, r = 12, 12, 7
    for a in range(0, 360, 6):
        import math
        rad = math.radians(a)
        if 330 <= a <= 360:
            continue
        for rr_ in (r - 1, r):
            x = int(round(cx + rr_ * math.cos(rad)))
            y = int(round(cy + rr_ * math.sin(rad)))
            px(im, x, y, CREAM if rr_ == r else BRASS_H)
    # arrow head at the gap (top right)
    for i in range(4):
        rect(im, 16 + 0, 3 + i, 19, 3 + i, CREAM)
    px(im, 16, 3, INK); px(im, 19, 6, INK)
    save(im, "icon_retry.png")

    # check
    im = new(S, S)
    for i in range(5):
        px(im, 5 + i, 12 + i, GREEN_L)
        px(im, 6 + i, 12 + i, GREEN_L)
    for i in range(9):
        px(im, 10 + i, 16 - i, GREEN_L)
        px(im, 11 + i, 16 - i, GREEN_L)
    save(im, "icon_check.png")

    # warning
    im = new(S, S)
    for y in range(S):
        half = int((y - 3) * 0.62)
        if 3 <= y <= 21:
            rect(im, 12 - half, y, 11 + half, y, BRASS_L)
    rect_ring(im, 3, 20, 20, 21, INK)
    for y in range(8, 16):
        rect(im, 11, y, 12, y, INK)
    rect(im, 11, 18, 12, 18, INK)
    save(im, "icon_warn.png")

    # download arrow + tray
    im = new(S, S)
    rect(im, 11, 3, 13, 13, CREAM)
    for i in range(4):
        rect(im, 11 - i, 12 - i, 13 + i, 12 - i, CREAM)
    rect(im, 4, 18, 19, 20, BRASS_L)
    rect(im, 4, 18, 4, 20, BRASS_H)
    save(im, "icon_download.png")

    # cloud-off / offline
    im = new(S, S)
    rect(im, 6, 13, 18, 16, CREAM)
    rect(im, 8, 10, 15, 12, CREAM)
    rect(im, 10, 8, 13, 9, CREAM)
    for i in range(16):
        px(im, 5 + i, 5 + i, RUST_M)
        px(im, 6 + i, 5 + i, RUST_L)
    save(im, "icon_offline.png")

    # gear
    im = new(S, S)
    import math
    for a in range(0, 360, 45):
        rad = math.radians(a)
        for d in (7, 8, 9):
            x = int(round(12 + d * math.cos(rad)))
            y = int(round(12 + d * math.sin(rad)))
            rect(im, x - 1, y - 1, x + 1, y + 1, BRASS_L)
    for a in range(0, 360, 8):
        rad = math.radians(a)
        for d in (5, 6):
            x = int(round(12 + d * math.cos(rad)))
            y = int(round(12 + d * math.sin(rad)))
            px(im, x, y, BRASS_L)
    rect(im, 10, 10, 13, 13, TEAL_D)
    save(im, "icon_gear.png")

    # page / changelog
    im = new(S, S)
    rect(im, 5, 3, 18, 20, PARCH_L)
    rect(im, 18, 3, 18, 20, PARCH_D)
    rect(im, 5, 20, 18, 20, PARCH_D)
    for y in (8, 12, 16):
        rect(im, 8, y, 15, y, BRASS_M)
    save(im, "icon_scroll.png")


def ornaments():
    # divider: leafy brass rule, centre diamond, scrollwork ends. 128x16.
    W, H = 128, 16
    im = new(W, H)
    cy = 7
    for x0, x1 in ((12, 54), (74, 116)):
        hline(im, x0, x1, cy - 1, BRASS_M)
        hline(im, x0, x1, cy, BRASS_D)
        hline(im, x0, x1, cy + 1, TEAL_D)
        for lx in (x0 + 10, x0 + 30):
            if lx + 6 > x1:
                continue
            px(im, lx, cy - 2, GREEN_M)
            px(im, lx + 1, cy - 3, GREEN_L)
            px(im, lx + 2, cy - 2, GREEN_M)
            px(im, lx + 3, cy - 1, GREEN_D)
            px(im, lx, cy + 2, GREEN_D)
    for side in (0, 1):
        bx = 8 if side == 0 else W - 9
        d = 1 if side == 0 else -1
        px(im, bx, cy, BRASS_L)
        px(im, bx - d, cy - 1, BRASS_M)
        px(im, bx - d, cy + 1, BRASS_M)
        px(im, bx - 2 * d, cy, BRASS_D)
        px(im, bx - 3 * d, cy - 2, BRASS_D)
        px(im, bx - 3 * d, cy + 2, BRASS_D)
    for i, col in enumerate((BRASS_H, BRASS_L, BRASS_M, BRASS_D)):
        hline(im, 64 - 3 + i, 64 + 3 - i, cy - 3 + i, col)
    for i, col in enumerate((BRASS_D, BRASS_M, BRASS_L, BRASS_H)):
        hline(im, 64 - 3 + i, 64 + 3 - i, cy + i, col)
    save(im, "ornament_divider.png")

    # corner flourish for panels: 24x24, top-left orientation
    im = new(24, 24)
    for i in range(14):
        px(im, 3 + i, 3, BRASS_M)
        px(im, 3, 3 + i, BRASS_M)
    for i in range(14):
        px(im, 4 + i, 4, BRASS_D)
        px(im, 4, 4 + i, BRASS_D)
    for i in range(7):
        px(im, 5 + i, 5 + i, GREEN_M)
    px(im, 6, 6, BRASS_L)
    px(im, 7, 7, BRASS_L)
    for i in range(4):
        px(im, 8 + i, 3, GREEN_L)
        px(im, 3, 8 + i, GREEN_L)
    px(im, 5, 3, GREEN_M)
    px(im, 3, 5, GREEN_M)
    save(im, "ornament_corner.png")

    # 4-point star, used for sparkles and dust motes
    im = new(8, 8)
    sparkle(im, 4, 4, 3, CREAM, BRASS_L)
    save(im, "fx_spark.png")

    # soft round mote for ambient dust (4x4: a speck, not a square)
    im = new(4, 4)
    px(im, 1, 1, (255, 246, 214, 235))
    px(im, 2, 1, (255, 236, 176, 200))
    px(im, 1, 2, (255, 236, 176, 200))
    px(im, 2, 2, (255, 220, 150, 160))
    save(im, "fx_mote.png")

    # vignette overlay 256x144, stretched over the screen. Warm, banded.
    W, H = 256, 144
    im = new(W, H)
    for y in range(H):
        for x in range(W):
            nx = abs(x - (W - 1) / 2) / ((W - 1) / 2)
            ny = abs(y - (H - 1) / 2) / ((H - 1) / 2)
            v = max(nx ** 2.4, ny ** 2.6)
            a = int(min(1.0, v * 1.15) ** 1.5 * 205)
            a = (a // 10) * 10
            px(im, x, y, (28, 18, 14, a))
    save(im, "overlay_vignette.png")


def main():
    print("Re - Traveller UI kit ->", os.path.normpath(OUT))
    panel_parchment()
    panel_ink()
    button_wood()
    button_gold()
    progress_bar()
    icon_frame()
    icons()
    ornaments()
    print("done")


if __name__ == "__main__":
    main()
