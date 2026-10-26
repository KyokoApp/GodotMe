#!/usr/bin/env python3
"""Re - Traveller : compose the step-3B building sheet.

The brief asks for four sides of the buildings, in daylight and at night. CI
takes one capture per side per phase (the stage in `BuildingTest.tscn`), and this
script arranges the eight frames into one contact sheet with a label on each, so
a reviewer can see the kit from every direction without opening eight files.

Usage
  python3 tools/building_sheet.py --dir docs/screenshots/bangunan \
      --out docs/screenshots/bangunan/kit_bangunan.png
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
WARM = (232, 188, 96)

# (file stem, label) in the order they are laid out: the four sides across the
# top row in daylight, the same four below at night.
ROWS = [
    [("depan", "DEPAN · SIANG"), ("kanan", "KANAN · SIANG"),
     ("belakang", "BELAKANG · SIANG"), ("kiri", "KIRI · SIANG")],
    [("depan", "DEPAN · MALAM"), ("kanan", "KANAN · MALAM"),
     ("belakang", "BELAKANG · MALAM"), ("kiri", "KIRI · MALAM")],
]
PHASES = ["siang", "malam"]


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


def shot_path(directory: str, side: str, phase: str) -> str:
    """The CI writes 50_bangunan_<side>_<phase>.png; accept either spelling."""
    for name in (f"50_bangunan_{side}_{phase}.png", f"bangunan_{side}_{phase}.png",
                 f"{side}_{phase}.png"):
        path = os.path.join(directory, name)
        if os.path.exists(path):
            return path
    return ""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--columns", type=int, default=4)
    ap.add_argument("--cell-width", type=int, default=480)
    args = ap.parse_args()

    shots = {}
    for phase in PHASES:
        for side, _label in ROWS[0]:
            path = shot_path(args.dir, side, phase)
            if path:
                shots[(side, phase)] = Image.open(path).convert("RGB")
    if not shots:
        print(f"[SHEET] tidak ada tangkapan di {args.dir}", file=sys.stderr)
        return 1

    sample = next(iter(shots.values()))
    cell_w = args.cell_width
    cell_h = max(1, round(cell_w * sample.height / sample.width))
    pad = 14
    label_h = 30
    cols = args.columns
    rows = len(ROWS)
    sheet_w = cols * cell_w + (cols + 1) * pad
    sheet_h = rows * (cell_h + label_h) + (rows + 1) * pad + 46

    sheet = Image.new("RGB", (sheet_w, sheet_h), BG)
    draw = ImageDraw.Draw(sheet)
    title_font = load_font(24)
    label_font = load_font(17)
    draw.text((pad, pad), "KIT BANGUNAN YAROS · 4 SISI × SIANG/MALAM", font=title_font,
              fill=INK)
    draw.text((pad, pad + 30), "diukur dari tahap uji: satu menara, tiga rumah, gerbang, "
              "sumur, dermaga, papan, obor", font=label_font, fill=DIM)

    y = pad + 46
    for row_index, row in enumerate(ROWS):
        phase = PHASES[min(row_index, len(PHASES) - 1)]
        x = pad
        for side, label in row:
            img = shots.get((side, phase))
            if img is not None:
                sheet.paste(img.resize((cell_w, cell_h), Image.LANCZOS), (x, y))
            else:
                draw.rectangle([x, y, x + cell_w, y + cell_h], fill=(40, 34, 28))
                draw.text((x + pad, y + cell_h // 2), "(tidak ada tangkapan)",
                          font=label_font, fill=DIM)
            draw.text((x + 8, y + cell_h + 6), label, font=label_font,
                      fill=WARM if phase == "malam" else INK)
            x += cell_w + pad
        y += cell_h + label_h + pad

    os.makedirs(os.path.dirname(os.path.abspath(args.out)) or ".", exist_ok=True)
    sheet.save(args.out, optimize=True)
    print(f"[SHEET] {args.out} {sheet.width}x{sheet.height}, {len(shots)} bidikan")
    return 0


if __name__ == "__main__":
    sys.exit(main())
