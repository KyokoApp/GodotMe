#!/usr/bin/env python3
"""Susun `blockzone/src/` menjadi satu `game.html` dan buktikan hasilnya identik.

Refactor hanya boleh dilakukan kalau bisa dibuktikan tidak mengubah satu byte pun.
Skrip ini karena itu gagal (exit 1) kalau hasil build berbeda dari
`blockzone/www/game.html` — berkas yang md5-nya sudah dikunci di `APK_INFO.json`.

    python3 blockzone/tools/build_game.py            # tulis blockzone/build/game.html
    python3 blockzone/tools/build_game.py --check    # hanya periksa, tidak menulis
"""

from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent                     # blockzone/
SRC = ROOT / "src"
GOLDEN = ROOT / "www" / "game.html"    # acuan: berkas asli dari APK

PARTS = {
    "{{STYLE}}": SRC / "style.css",
    "{{BOOT_JS}}": SRC / "js" / "01-boot.js",
    "{{GAME_JS}}": SRC / "js" / "02-game.js",
}


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def build() -> bytes:
    template = (SRC / "game.template.html").read_text(encoding="utf-8")
    for token, path in PARTS.items():
        if token not in template:
            raise SystemExit(f"token {token} tidak ada di src/game.template.html")
        text = path.read_text(encoding="utf-8")
        if text.endswith("\n"):
            text = text[:-1]
        template = template.replace(token, text)
    return template.encode("utf-8")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(ROOT / "build" / "game.html"))
    ap.add_argument("--check", action="store_true", help="jangan tulis apa pun")
    args = ap.parse_args()

    built = build()
    golden = GOLDEN.read_bytes()

    if built != golden:
        print("HASIL BUILD BERBEDA DARI ARSIP — refactor ditolak", file=sys.stderr)
        print(f"  build : {len(built)} byte  sha256 {sha256(built)}", file=sys.stderr)
        print(f"  arsip : {len(golden)} byte  sha256 {sha256(golden)}", file=sys.stderr)
        for i, (a, b) in enumerate(zip(built, golden)):
            if a != b:
                lo = max(0, i - 60)
                print(f"  byte pertama yang beda di offset {i}:", file=sys.stderr)
                print(f"    build: {built[lo:i + 60]!r}", file=sys.stderr)
                print(f"    arsip: {golden[lo:i + 60]!r}", file=sys.stderr)
                break
        return 1

    print(f"identik: {len(built)} byte, sha256 {sha256(built)}")
    if not args.check:
        out = Path(args.out)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(built)
        print(f"ditulis: {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
