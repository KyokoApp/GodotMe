#!/usr/bin/env python3
"""Re - Traveller : audit the six packages before they are built.

Phase 8 asks for the smallest packages possible. The cheapest megabyte is the
one nobody packed - phase 7 found a 1,17 MB backdrop that had been shipped in
two packs for weeks without a single line of code loading it. That is exactly
the kind of waste this script hunts:

  * every path listed in FixtureBuilder.PACK_FILES must exist on disk (error);
  * every asset must be named somewhere in the code/resources (error) - a PNG
    that nothing references is dead weight in every download;
  * the same path in two packs is reported (warning: one download can replace
    a file the other pack also claims);
  * per-pack and total byte counts, so a size regression is visible in the log.

Run: python3 tools/pack_audit.py [--allow name,name]
Exit code 1 when an error is found, so CI fails instead of shipping it.
"""
from __future__ import annotations

import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIXTURES = os.path.join(ROOT, "launcher", "tests", "FixtureBuilder.gd")

TEXT_EXT = (".gd", ".tscn", ".tres", ".json", ".cfg", ".yml", ".yaml", ".gdshader")
ASSET_EXT = (".png", ".woff2", ".ttf", ".ogg", ".wav", ".jpg")


def pack_lists() -> dict[str, list[str]]:
    """Read the six file lists out of FixtureBuilder without running Godot.

    A state machine rather than a regex over the whole file: `"name": {` opens a
    pack, `"files": [` opens its list, and only string literals between those
    brackets count. A looser match also scooped up unrelated complaint strings
    from the manifest fixtures ("Manifest bertanda tangan.") and reported them as
    missing pack files.
    """
    lines = open(FIXTURES, encoding="utf-8").read().splitlines()
    packs: dict[str, list[str]] = {}
    current: str | None = None
    in_files = False
    for line in lines:
        stripped = line.strip()
        m = re.match(r'"([a-z]+)":\s*\{', stripped)
        if m and not in_files:
            current = m.group(1)
            packs[current] = []
            continue
        if current is None:
            continue
        if stripped.startswith('"files":'):
            in_files = True
            if stripped.endswith("],"):   # empty list on one line
                in_files = False
            continue
        if in_files:
            if stripped.startswith("]"):
                in_files = False
                continue
            m = re.match(r'"([^"]+)"', stripped)
            if m:
                packs[current].append(m.group(1))
    return packs


def references() -> str:
    """Concatenate every text file the game could name an asset in."""
    chunks: list[str] = []
    for base, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in (".git", ".tools", "docs", "node_modules")]
        for name in files:
            if not name.endswith(TEXT_EXT):
                continue
            path = os.path.join(base, name)
            try:
                chunks.append(open(path, encoding="utf-8", errors="ignore").read())
            except OSError:
                pass
    return "\n".join(chunks)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--allow", default="",
                    help="comma separated basenames that may be packed unused")
    args = ap.parse_args()
    allowed = {s for s in args.allow.split(",") if s}

    packs = pack_lists()
    if not packs:
        print("[PACK] gagal membaca daftar paket dari FixtureBuilder.gd")
        return 1
    blob = references()

    errors = 0
    warnings = 0
    seen: dict[str, list[str]] = {}
    total = 0
    print("[PACK] %d paket" % len(packs))
    for name in sorted(packs, key=lambda k: packs[k][0]):
        files = packs[name]
        size = 0
        unused: list[str] = []
        missing: list[str] = []
        for rel in files:
            abs_path = os.path.join(ROOT, "game" if rel.startswith("game/") else "", rel)
            # paths in the lists are relative to the Godot project root (game/)
            if not os.path.exists(abs_path):
                missing.append(rel)
                continue
            size += os.path.getsize(abs_path)
            base = os.path.basename(rel)
            if base.endswith(ASSET_EXT) and base not in allowed:
                if base not in blob or blob.count(base) <= 1:
                    # only the pack list mentions it: nothing loads this asset
                    unused.append(rel)
            seen.setdefault(rel, []).append(name)
        total += size
        status = "kosong" if not files else ("ok" if not missing and not unused else "PERIKSA")
        print("[PACK] %-11s %2d berkas  %8d B  %s" % (name, len(files), size, status))
        for rel in missing:
            print("  HILANG  %s" % rel)
            errors += 1
        for rel in unused:
            print("  TIDAK DIPAKAI  %s" % rel)
            errors += 1
    dup = {k: v for k, v in seen.items() if len(v) > 1}
    for rel, holders in dup.items():
        print("[PACK] ganda: %s di %s" % (rel, " + ".join(holders)))
        warnings += 1
    print("[PACK] total %d B (%.1f KB), %d galat, %d peringatan" % (
        total, total / 1024.0, errors, warnings))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
