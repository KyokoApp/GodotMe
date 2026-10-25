#!/usr/bin/env python3
"""Re - Traveller : pack the 24x24 UI icons into one atlas.

Why: seven tiny textures means seven texture binds per HUD frame on a phone GPU
that likes big textures and hates swaps. The icons are already one family on one
grid, so packing them is free.

Output (both shipped in `ui.pck`):
    game/game/assets/ui/atlas_ui.png    one row of 24x24 cells, 1 px padding
    game/game/assets/ui/atlas_ui.json   {cell, padding, entries: {name: {x,y}}}

The single PNGs stay in the repository as the authored source (and as the
fallback when the atlas is missing in an editor run). `pack_audit.py` proves the
atlas covers every icon the code asks for.

Run (Pillow needed):
    python3 tools/gen_atlas.py
"""
from __future__ import annotations

import json
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICONS = os.path.join(ROOT, "game", "game", "assets", "ui", "icons")
OUT_PNG = os.path.join(ROOT, "game", "game", "assets", "ui", "atlas_ui.png")
OUT_JSON = os.path.join(ROOT, "game", "game", "assets", "ui", "atlas_ui.json")

CELL = 24
PAD = 1


def main() -> None:
    names = sorted(f[:-4] for f in os.listdir(ICONS) if f.endswith(".png"))
    count = len(names)
    width = count * (CELL + PAD * 2)
    height = CELL + PAD * 2
    sheet = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    entries = {}
    for i, name in enumerate(names):
        img = Image.open(os.path.join(ICONS, name + ".png")).convert("RGBA")
        if img.size != (CELL, CELL):
            raise SystemExit("%s is %dx%d, expected %dx%d" % (name, *img.size, CELL, CELL))
        x = i * (CELL + PAD * 2) + PAD
        y = PAD
        sheet.alpha_composite(img, (x, y))
        entries[name] = {"x": x, "y": y, "w": CELL, "h": CELL}
    sheet.save(OUT_PNG)
    with open(OUT_JSON, "w", encoding="utf-8") as fh:
        json.dump({"cell": CELL, "padding": PAD, "entries": entries}, fh, indent=2)
        fh.write("\n")
    print("atlas %dx%d, %d ikon -> %s" % (width, height, count, os.path.basename(OUT_PNG)))


if __name__ == "__main__":
    main()
