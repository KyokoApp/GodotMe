#!/usr/bin/env python3
"""Re - Traveller : audit the step-3B building kit before Godot is even started.

The kit is two files that have to agree: `tools/gen_building_kit.py` writes the
atlas PNG and `building_kit.json`, and `BuildingKit.gd` asks for cells BY NAME.
Nothing at runtime complains when they disagree - a wall whose cell name is a
typo simply is not drawn, and the building behind it still looks plausible in a
screenshot. So this script is the cheap gate (a second, not a five-minute Godot
round trip) for exactly that class of mistake:

  * every cell named in BuildingKit.gd exists in the manifest;
  * every cell's rect is inside the atlas and its uv matches the rect;
  * the PNG on disk is the size the manifest claims;
  * no cell is fully transparent (an empty cell is an invisible wall);
  * every kind the manifest promises can be built (has variants, a block radius
    that matches the collision contract RegionData signed off in step 2).

Run: python3 tools/kit_audit.py
Exit code 1 on an error, so CI fails instead of shipping it.
"""
from __future__ import annotations

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
META = os.path.join(ROOT, "game", "game", "world", "building_kit.json")
ATLAS = os.path.join(ROOT, "game", "game", "world", "textures", "building_atlas.png")
KIT = os.path.join(ROOT, "game", "game", "world", "BuildingKit.gd")
REGION_DATA = os.path.join(ROOT, "game", "game", "world", "RegionData.gd")

# The collision radii step 2 shipped. A house may change shape in step 3B; it
# may not change how much room it takes when the knight walks into it.
BLOCK_CONTRACT = {"cottage": 2.0, "tower": 2.4, "gate": 2.2, "well": 0.9}


def required_cells() -> list[str]:
    """The cell names BuildingKit.gd's `required_cells()` lists."""
    text = open(KIT, encoding="utf-8").read()
    m = re.search(r"func required_cells\(\) -> Array:\s*return \[(.*?)\]", text, re.S)
    if not m:
        return []
    return re.findall(r'"([^"]+)"', m.group(1))


def region_block_radii() -> dict[str, float]:
    """Block radii as RegionData declares them, so the two cannot drift."""
    text = open(REGION_DATA, encoding="utf-8").read()
    out: dict[str, float] = {}
    block = re.search(r"static func blocker_radius.*?:\s*\n(.*?)\n\n\n", text, re.S)
    if not block:
        return out
    for name, value in re.findall(r'"([a-z_]+)":\s*([0-9.]+)', block.group(1)):
        out[name] = float(value)
    return out


def main() -> int:
    errors: list[str] = []
    warnings: list[str] = []
    if not os.path.exists(META):
        print(f"[KIT] galat: {META} tidak ada (jalankan tools/gen_building_kit.py)")
        return 1
    meta = json.load(open(META, encoding="utf-8"))
    cells = meta.get("cells", [])
    kinds = meta.get("kinds", {})
    width, height = meta.get("atlas", [0, 0])
    print(f"[KIT] manifest: {len(cells)} sel, {len(kinds)} jenis, atlas {width}x{height}")

    names: dict[str, dict] = {}
    for cell in cells:
        name = cell.get("name", "")
        if not name:
            errors.append("sel tanpa nama")
            continue
        if name in names:
            errors.append(f"sel ganda: {name}")
        names[name] = cell
        uv = cell.get("uv", [])
        rect = cell.get("rect", [])
        if len(uv) < 4 or len(rect) < 4:
            errors.append(f"{name}: uv/rect tidak lengkap")
            continue
        if rect[0] < 0 or rect[1] < 0 or rect[0] + rect[2] > width or rect[1] + rect[3] > height:
            errors.append(f"{name}: rect keluar atlas")
        # uv must be exactly rect / atlas, or the paint and the sampler disagree
        want = [rect[0] / width, rect[1] / height, rect[2] / width, rect[3] / height]
        for got, expect in zip(uv, want):
            if abs(got - expect) > 1e-4:
                errors.append(f"{name}: uv {uv} != rect/atlas {['%.4f' % v for v in want]}")
                break

    for name in required_cells():
        if name not in names:
            errors.append(f"kode meminta sel '{name}' yang tidak ada di manifest")

    if not os.path.exists(ATLAS):
        errors.append(f"atlas tidak ada: {ATLAS}")
    else:
        try:
            from PIL import Image  # noqa: PLC0415 - optional, only for the size check
        except ImportError:
            warnings.append("Pillow tidak ada: ukuran PNG tidak diperiksa")
        else:
            img = Image.open(ATLAS)
            if img.size != (width, height):
                errors.append(f"PNG {img.size[0]}x{img.size[1]} != manifest {width}x{height}")
            rgba = img.convert("RGBA")
            for name, cell in names.items():
                rect = cell.get("rect", [0, 0, 1, 1])
                crop = rgba.crop((rect[0], rect[1], rect[0] + rect[2], rect[1] + rect[3]))
                if not crop.getbbox():
                    errors.append(f"{name}: sel kosong (tidak ada piksel)")

    for kind, spec in kinds.items():
        if int(spec.get("variants", 0)) < 1:
            errors.append(f"{kind}: tanpa varian")
        for key in ("w", "d", "h"):
            if float(spec.get(key, 0.0)) <= 0.0:
                errors.append(f"{kind}: {key} nol")
        if kind in BLOCK_CONTRACT:
            if abs(float(spec.get("block_radius", -1.0)) - BLOCK_CONTRACT[kind]) > 1e-6:
                errors.append(
                    f"{kind}: block_radius {spec.get('block_radius')} != kontrak "
                    f"langkah 2 {BLOCK_CONTRACT[kind]}")

    radii = region_block_radii()
    for kind, want in BLOCK_CONTRACT.items():
        if kind in radii and abs(radii[kind] - want) > 1e-6:
            errors.append(f"RegionData.{kind} = {radii[kind]}, kontrak {want}")

    # the shape of the village, printed so a change is visible in the log
    rows = []
    for kind in sorted(kinds):
        spec = kinds[kind]
        rows.append(f"{kind} {spec['w']}x{spec['d']}x{spec['h']} m, "
                    f"{spec['variants']} varian, radius {spec['block_radius']}")
    for row in rows:
        print(f"[KIT]   {row}")

    for w in warnings:
        print(f"[KIT] peringatan: {w}")
    for e in errors:
        print(f"[KIT] galat: {e}")
    if errors:
        return 1
    print(f"[KIT] kit sah: {len(names)} sel, {len(kinds)} jenis, "
          f"{os.path.getsize(ATLAS)} B atlas")
    return 0


if __name__ == "__main__":
    sys.exit(main())
