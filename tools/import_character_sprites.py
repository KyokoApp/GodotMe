#!/usr/bin/env python3
"""Re - Traveller : character sprite pipeline (Knight / Soldier / Orc).

One strip per animation, one `CharacterDef` resource per character. This script
is the single source of truth for *what the strips must be*, so a wrong or
truncated export fails the build instead of being guessed around:

  * `--import` copies the untouched source strips from `assets_src/characters/`
    into `game/game/assets/characters/<id>/` and regenerates the `.tres`
    definitions (pivot included, measured from the IDLE bounding box).
  * `--check` verifies the shipped strips against the same table and exits 1 on
    any width/height mismatch, empty frame or stale pivot. This is what CI runs.
  * `--report` prints the measured inventory (widths, pivot, metres tall).

Rules kept by design:
  * every strip is horizontal, frames left to right, transparent background,
    character faces RIGHT (left direction is `flip_h` at runtime);
  * no shadow is baked into the shipped strips: Soldier/Orc ship the pack's
    "without shadows" variant, the shadowed one is kept in assets_src as a
    backup only;
  * nothing is resampled - the PNG bytes are copied verbatim, so the pixel grid
    the artist drew is the pixel grid the engine samples.

Usage (Pillow is needed; in this sandbox use /tmp/venv/bin/python):
    python3 tools/import_character_sprites.py --report
    python3 tools/import_character_sprites.py --import
    python3 tools/import_character_sprites.py --check
"""
from __future__ import annotations

import argparse
import os
import shutil
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets_src", "characters")
OUT = os.path.join(ROOT, "game", "game", "assets", "characters")
RES = os.path.join(ROOT, "game", "game", "characters", "data")

# World metres per *source pixel* for a scale-1.0 character. One global number
# for every actor (see docs/DESIGN_NOTES.md); per-character `pixel_scale` is a
# multiplier on top of it and only exists because the packs differ in
# resolution.
WORLD_PIXEL_SIZE = 0.05

# anim name -> (file, frames, fps, loop, hold_last)
# Frame counts are the verified ones from the packs (width / frame width).
SPEC = {
    "knight": {
        "display_name": "Ksatria",
        "role": "player",
        "frame_size": (112, 96),
        "pixel_scale": 1.0,
        "walk_stride_m": 0.90,
        "run_stride_m": 1.90,
        "body_radius_m": 0.34,
        "idle_anim": "idle",
        "anims": [
            ("idle", "idle.png", 14, 9.0, True, False),
            ("walk", "walk.png", 8, 11.0, True, False),
            ("run", "run.png", 8, 13.0, True, False),
            ("attack_1", "attack_1.png", 8, 14.0, False, False),
            ("attack_2", "attack_2.png", 9, 14.0, False, False),
            ("attack_3", "attack_3.png", 11, 15.0, False, False),
            ("block", "block.png", 6, 10.0, False, True),
            ("hurt", "hurt.png", 8, 12.0, False, False),
            ("death", "death.png", 15, 11.0, False, True),
            # shipped but unused: no jump in the game yet, kept on purpose
            ("jump_start", "jump_start.png", 3, 12.0, False, True),
            ("jump_transition", "jump_transition.png", 3, 12.0, False, True),
            ("jump_fall", "jump_fall.png", 3, 12.0, True, False),
        ],
    },
    "soldier": {
        "display_name": "Penjaga Bram",
        "role": "npc",
        "frame_size": (100, 100),
        "pixel_scale": 1.5,
        "walk_stride_m": 0.75,
        "run_stride_m": 0.0,
        "body_radius_m": 0.28,
        "idle_anim": "idle",
        "anims": [
            ("idle", "idle.png", 6, 8.0, True, False),
            ("walk", "walk.png", 8, 10.0, True, False),
            ("attack_1", "attack_1.png", 6, 13.0, False, False),
            ("attack_2", "attack_2.png", 6, 13.0, False, False),
            ("attack_3", "attack_3.png", 9, 14.0, False, False),
            ("hurt", "hurt.png", 4, 12.0, False, False),
            ("death", "death.png", 4, 11.0, False, True),
        ],
    },
    "orc": {
        "display_name": "Orc Perampok",
        "role": "enemy",
        "frame_size": (100, 100),
        "pixel_scale": 1.75,
        "walk_stride_m": 0.70,
        "run_stride_m": 0.0,
        "body_radius_m": 0.30,
        "idle_anim": "idle",
        "anims": [
            ("idle", "idle.png", 6, 9.0, True, False),
            ("walk", "walk.png", 8, 10.0, True, False),
            ("attack_1", "attack_1.png", 6, 13.0, False, False),
            ("attack_2", "attack_2.png", 6, 13.0, False, False),
            ("hurt", "hurt.png", 4, 12.0, False, False),
            ("death", "death.png", 4, 11.0, False, True),
        ],
    },
}

# Extra files that ride along in the character folder but are not animations.
EXTRAS = {
    "knight": ["LICENSE.txt"],
    "soldier": ["arrow_100.png", "arrow_32.png", "SOURCE.txt"],
    "orc": ["SOURCE.txt"],
}


def bbox_union(img: Image.Image, fw: int, fh: int) -> tuple[int, int, int, int]:
    """Union of the non-transparent pixel bounds over every frame of a strip."""
    box = None
    for i in range(img.width // fw):
        b = img.crop((i * fw, 0, (i + 1) * fw, fh)).getbbox()
        if b is None:
            continue
        box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]),
                                     max(box[2], b[2]), max(box[3], b[3]))
    if box is None:
        raise SystemExit("strip is fully transparent: %s" % img.filename)
    return box


def measure(cid: str) -> dict:
    """Validate one character's source strips and derive its pivot/size."""
    spec = SPEC[cid]
    fw, fh = spec["frame_size"]
    src_dir = os.path.join(SRC, cid)
    problems: list[str] = []
    anims = []
    idle_box = None
    for name, file, frames, fps, loop, hold in spec["anims"]:
        path = os.path.join(src_dir, file)
        if not os.path.isfile(path):
            problems.append("%s/%s: file missing" % (cid, file))
            continue
        with Image.open(path) as im:
            im = im.convert("RGBA")
            if im.height != fh:
                problems.append("%s/%s: height %d, expected %d"
                                % (cid, file, im.height, fh))
            if im.width != frames * fw:
                problems.append(
                    "%s/%s: width %d != %d frames x %d px (%d)"
                    % (cid, file, im.width, frames, fw, frames * fw))
                continue
            box = bbox_union(im, fw, fh)
            if name == spec["idle_anim"]:
                idle_box = box
            anims.append({
                "name": name, "file": file, "frames": frames, "fps": fps,
                "loop": loop, "hold_last": hold,
                "bbox": box,
            })
    if idle_box is None:
        raise SystemExit("%s: no usable idle strip, cannot place the feet" % cid)
    pivot_x = round((idle_box[0] + idle_box[2]) / 2.0, 1)
    pivot_y = float(idle_box[3])
    return {
        "id": cid,
        "spec": spec,
        "anims": anims,
        "problems": problems,
        "pivot": (pivot_x, pivot_y),
        # body width at the feet is what the blob shadow and the collision
        # circle are sized from; content height is what the ruler shows.
        "body_width_px": idle_box[2] - idle_box[0],
        "content_height_px": idle_box[3] - idle_box[1],
    }


def world_height_m(info: dict) -> float:
    return info["content_height_px"] * WORLD_PIXEL_SIZE * info["spec"]["pixel_scale"]


def write_tres(info: dict, path: str) -> None:
    spec = info["spec"]
    fw, fh = spec["frame_size"]
    lines = [
        "[gd_resource type=\"Resource\" format=3]",
        "",
        "[ext_resource type=\"Script\" path=\"res://game/characters/CharacterDef.gd\" id=\"1_def\"]",
        "",
        "[resource]",
        "script = ExtResource(\"1_def\")",
        "id = \"%s\"" % info["id"],
        "display_name = \"%s\"" % spec["display_name"],
        "role = \"%s\"" % spec["role"],
        "sprite_dir = \"res://game/assets/characters/%s\"" % info["id"],
        "frame_size = Vector2i(%d, %d)" % (fw, fh),
        "pixel_scale = %.3f" % spec["pixel_scale"],
        "pivot = Vector2(%s, %s)" % (info["pivot"][0], info["pivot"][1]),
        "body_width_px = %d" % info["body_width_px"],
        "content_height_px = %d" % info["content_height_px"],
        "world_pixel_size = %.4f" % WORLD_PIXEL_SIZE,
        "walk_stride_m = %.3f" % spec["walk_stride_m"],
        "run_stride_m = %.3f" % spec["run_stride_m"],
        "body_radius_m = %.3f" % spec["body_radius_m"],
        "animations = [",
    ]
    blocks = []
    for a in info["anims"]:
        # no trailing commas anywhere: the .tres reader is happier without them
        blocks.append("{\n" + ",\n".join([
            "\"name\": \"%s\"" % a["name"],
            "\"file\": \"%s\"" % a["file"],
            "\"frames\": %d" % a["frames"],
            "\"fps\": %.1f" % a["fps"],
            "\"loop\": %s" % ("true" if a["loop"] else "false"),
            "\"hold_last\": %s" % ("true" if a["hold_last"] else "false"),
        ]) + "\n}")
    lines += [",\n".join(blocks) + "]\n"]
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))


def parse_tres_pivot(path: str) -> tuple[float, float] | None:
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                if line.startswith("pivot = Vector2("):
                    body = line.strip()[len("pivot = Vector2("):-1]
                    a, b = body.split(",")
                    return (float(a), float(b))
    except OSError:
        return None
    return None


def do_report() -> int:
    print("character  canvas   frames  content  height   pivot          scale")
    for cid in SPEC:
        info = measure(cid)
        spec = info["spec"]
        for p in info["problems"]:
            print("  !! " + p)
        print("%-9s %3dx%-4d %6d %7dpx %6.2fm  (%s, %s)  x%.2f" % (
            cid, spec["frame_size"][0], spec["frame_size"][1],
            len(info["anims"]), info["content_height_px"], world_height_m(info),
            info["pivot"][0], info["pivot"][1], spec["pixel_scale"]))
        for a in info["anims"]:
            print("    %-16s %2df @%4.1ffps %-5s %s px  bbox=%s" % (
                a["name"], a["frames"], a["fps"],
                "loop" if a["loop"] else ("hold" if a["hold_last"] else "once"),
                a["frames"] * spec["frame_size"][0], a["bbox"]))
        if info["problems"]:
            return 1
    return 0


def do_import() -> int:
    bad = 0
    for cid in SPEC:
        info = measure(cid)
        if info["problems"]:
            for p in info["problems"]:
                print("FAIL " + p, file=sys.stderr)
            bad = 1
            continue
        dst = os.path.join(OUT, cid)
        os.makedirs(dst, exist_ok=True)
        os.makedirs(RES, exist_ok=True)
        for a in info["anims"]:
            shutil.copyfile(os.path.join(SRC, cid, a["file"]),
                            os.path.join(dst, a["file"]))
        for extra in EXTRAS.get(cid, []):
            src = os.path.join(SRC, cid, extra)
            if os.path.isfile(src):
                shutil.copyfile(src, os.path.join(dst, extra))
            else:
                print("note: %s/%s has no source copy (written by hand)" % (cid, extra))
        tres = os.path.join(RES, cid + ".tres")
        write_tres(info, tres)
        print("[%s] %d anims, pivot (%s, %s), %.2f m tall -> %s" % (
            cid, len(info["anims"]), info["pivot"][0], info["pivot"][1],
            world_height_m(info), os.path.relpath(tres, ROOT)))
    return bad


def do_check() -> int:
    """CI gate: shipped strips must match the table, pivots must be current."""
    bad = 0
    for cid in SPEC:
        info = measure(cid)
        for p in info["problems"]:
            print("FAIL " + p, file=sys.stderr)
            bad = 1
        dst = os.path.join(OUT, cid)
        fw, fh = info["spec"]["frame_size"]
        for a in info["anims"]:
            path = os.path.join(dst, a["file"])
            if not os.path.isfile(path):
                print("FAIL %s/%s missing from the game assets" % (cid, a["file"]),
                      file=sys.stderr)
                bad = 1
                continue
            with Image.open(path) as im:
                im = im.convert("RGBA")
                if im.width != a["frames"] * fw or im.height != fh:
                    print("FAIL %s/%s shipped %dx%d, expected %dx%d" % (
                        cid, a["file"], im.width, im.height, a["frames"] * fw, fh),
                        file=sys.stderr)
                    bad = 1
                elif im.getbbox() is None:
                    print("FAIL %s/%s is fully transparent" % (cid, a["file"]),
                          file=sys.stderr)
                    bad = 1
        tres = os.path.join(RES, cid + ".tres")
        if not os.path.isfile(tres):
            print("FAIL %s missing" % os.path.relpath(tres, ROOT), file=sys.stderr)
            bad = 1
            continue
        pivot = parse_tres_pivot(tres)
        if pivot is None or abs(pivot[0] - info["pivot"][0]) > 0.05 \
                or abs(pivot[1] - info["pivot"][1]) > 0.05:
            print("FAIL %s pivot %s is stale, measured %s" % (cid, pivot, info["pivot"]),
                  file=sys.stderr)
            bad = 1
        print("[check] %-8s %2d anims  %d px tall (%.2f m)  pivot %s  %s" % (
            cid, len(info["anims"]), info["content_height_px"],
            world_height_m(info), info["pivot"], "ok" if not bad else "see above"))
    if bad:
        print("character sprite check FAILED", file=sys.stderr)
    else:
        print("character sprite check ok")
    return bad


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--import", dest="do_import", action="store_true")
    ap.add_argument("--check", dest="do_check", action="store_true")
    ap.add_argument("--report", action="store_true")
    args = ap.parse_args()
    if args.do_import:
        return do_import()
    if args.do_check:
        return do_check()
    return do_report()


if __name__ == "__main__":
    sys.exit(main())
