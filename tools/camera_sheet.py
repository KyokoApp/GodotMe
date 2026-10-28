#!/usr/bin/env python3
"""Re - Traveller : compose the step-3A camera comparison sheet.

The brief asks to look at pitch x FOV before anything is locked, so CI takes one
capture per combination and this script arranges them into a single sheet with a
label on every frame. Nothing here decides anything: the numbers stay in
`game/world/camera.json` until the owner picks a cell.

Usage
  python3 tools/camera_sheet.py --dir docs/screenshots/camera \
      --out docs/screenshots/camera/sudut_kamera.png \
      --pitches 25,30,35,40,50,38 --fovs 25,32,40 \
      --recommend 30,32 --current 38,30
"""
from __future__ import annotations

import argparse
import os
import sys

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:  # pragma: no cover - CI installs pillow first
    print("butuh pillow: python3 -m pip install pillow", file=sys.stderr)
    raise

BG = (26, 22, 18)
INK = (246, 236, 214)
DIM = (176, 162, 140)
HILITE = (232, 188, 96)


def load_font(size: int):
    for name in ("DejaVuSans-Bold.ttf", "DejaVuSans.ttf", "arial.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    try:
        return ImageFont.load_default(size=size)
    except TypeError:
        return ImageFont.load_default()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--pitches", default="25,30,35,40,50,38")
    ap.add_argument("--fovs", default="25,32,40")
    ap.add_argument("--recommend", default="30,32")
    ap.add_argument("--current", default="38,30")
    args = ap.parse_args()

    pitches = [int(v) for v in args.pitches.split(",") if v.strip()]
    fovs = [int(v) for v in args.fovs.split(",") if v.strip()]
    rec_pitch, rec_fov = [int(v) for v in args.recommend.split(",")]
    cur_pitch, cur_fov = [int(v) for v in args.current.split(",")]

    shots = {}
    missing = []
    for p in pitches:
        for f in fovs:
            name = f"p{p:02d}f{f:02d}.png"
            path = os.path.join(args.dir, name)
            if not os.path.exists(path):
                missing.append(name)
                continue
            shots[(p, f)] = Image.open(path).convert("RGB")
    if not shots:
        print(f"tidak ada tangkapan di {args.dir}", file=sys.stderr)
        return 1
    for name in missing:
        print(f"[SHEET] lewat: {name} tidak ada")

    cell_w = max(img.width for img in shots.values())
    cell_h = max(img.height for img in shots.values())
    pad = 14
    label_h = 34
    head_h = 96
    left_w = 74
    cols = len(fovs)
    rows = len(pitches)
    width = left_w + cols * (cell_w + pad) + pad
    height = head_h + rows * (cell_h + label_h + pad) + pad

    sheet = Image.new("RGB", (width, height), BG)
    draw = ImageDraw.Draw(sheet)
    title = load_font(30)
    body = load_font(20)
    small = load_font(17)

    draw.text((pad + 4, 10), "Sudut kamera Re - Traveller (3A)", font=title, fill=INK)
    draw.text((pad + 4, 48),
              "pitch = derajat menunduk di bawah garis horizontal (90 = tegak lurus ke bawah). "
              "FOV = sudut vertikal, kamera perspektif.",
              font=small, fill=DIM)
    draw.text((pad + 4, 70),
              "Bingkai bertanda KUNING = rekomendasi awal (belum final). Bingkai biru = nilai lama 3A.",
              font=small, fill=DIM)

    for c, f in enumerate(fovs):
        cx = left_w + c * (cell_w + pad)
        label = f"FOV {f}"
        tw = draw.textlength(label, font=body)
        draw.text((cx + (cell_w - tw) / 2, head_h - 34), label, font=body, fill=INK)
    for r, p in enumerate(pitches):
        cy = head_h + r * (cell_h + label_h + pad)
        draw.text((pad + 6, cy + cell_h / 2 - 12), f"P{p}", font=body, fill=INK)

    for r, p in enumerate(pitches):
        for c, f in enumerate(fovs):
            img = shots.get((p, f))
            cx = left_w + c * (cell_w + pad)
            cy = head_h + r * (cell_h + label_h + pad)
            if img is None:
                draw.rectangle([cx, cy, cx + cell_w, cy + cell_h], outline=DIM, width=1)
                draw.text((cx + 8, cy + 8), "tidak ada", font=small, fill=DIM)
                continue
            sheet.paste(img, (cx, cy))
            cap = f"P{p} F{f}"
            note = ""
            if (p, f) == (rec_pitch, rec_fov):
                note = "  REKOMENDASI"
                draw.rectangle([cx - 3, cy - 3, cx + cell_w + 3, cy + cell_h + 3],
                               outline=HILITE, width=3)
            if (p, f) == (cur_pitch, cur_fov):
                note = (note + "  NILAI LAMA").strip()
                draw.rectangle([cx - 6, cy - 6, cx + cell_w + 6, cy + cell_h + 6],
                               outline=(110, 170, 220), width=2)
            draw.text((cx + 2, cy + cell_h + 7), cap + note, font=small,
                      fill=HILITE if (p, f) == (rec_pitch, rec_fov) else INK)

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    sheet.save(args.out)
    print(f"[SHEET] {args.out} {sheet.width}x{sheet.height}, {len(shots)} tangkapan")
    return 0


if __name__ == "__main__":
    sys.exit(main())
