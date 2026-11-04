#!/usr/bin/env python3
"""Pecah `blockzone/www/game.html` (3.286 baris) menjadi sumber terpisah di `blockzone/src/`.

Ini skrip sekali jalan — dijalankan sekali untuk menghasilkan `src/`, lalu hasilnya
di-commit. Yang dipakai sehari-hari adalah `build_game.py`, yang menyusun ulang
`src/` menjadi `game.html` dan memastikan hasilnya **byte-identik** dengan arsip.

Bagian yang dipecah (batasnya baris tetap, karena berkas aslinya terkunci md5):

| Bagian | Baris asli | Keluaran |
| --- | --- | --- |
| CSS di dalam `<style>` | 9-532 | `src/style.css` |
| skrip boot (layar "ようこそ") | 545-570 | `src/js/01-boot.js` |
| skrip game utama | 702-3284 | `src/js/02-game.js` |
| sisanya | - | `src/game.template.html` |

Jalankan dari akar repo:

    python3 blockzone/tools/split_game.py
"""

from __future__ import annotations

import hashlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent      # blockzone/
WWW = ROOT / "www"
SRC = ROOT / "src"

# (nama berkas, baris awal, baris akhir) — 1-based, inklusif
PARTS = [
    ("style.css", 9, 532),
    ("js/01-boot.js", 545, 570),
    ("js/02-game.js", 702, 3284),
]

TOKENS = {"style.css": "{{STYLE}}", "js/01-boot.js": "{{BOOT_JS}}", "js/02-game.js": "{{GAME_JS}}"}


def sha256(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def main() -> int:
    html = (WWW / "game.html").read_text(encoding="utf-8")
    lines = html.split("\n")

    print(f"game.html: {len(lines)} baris, sha256 {sha256(html.encode())[:16]}…")

    for token in TOKENS.values():
        if token in html:
            print(f"token {token} sudah ada di berkas asli — batal", file=sys.stderr)
            return 1

    # Ekstrak tiap bagian, lalu ganti isinya dengan token di salinan template.
    template_lines = list(lines)
    extracted: dict[str, str] = {}
    # diproses dari bawah ke atas supaya nomor baris bagian lain tidak bergeser
    for name, start, end in sorted(PARTS, key=lambda x: x[1], reverse=True):
        body = "\n".join(lines[start - 1:end])
        extracted[name] = body
        # token menggantikan baris start..end (indeks start-1..end-1)
        template_lines[start - 1:end] = [TOKENS[name]]

    template = "\n".join(template_lines)

    (SRC / "js").mkdir(parents=True, exist_ok=True)
    for name, body in sorted(extracted.items()):
        # ditulis dengan newline di akhir (rapi untuk editor), builder membuangnya lagi
        (SRC / name).write_text(body + "\n", encoding="utf-8")
        print(f"  src/{name}: {len(body.splitlines())} baris, {len(body)} byte")
    (SRC / "game.template.html").write_text(template, encoding="utf-8")
    print(f"  src/game.template.html: {len(template.splitlines())} baris, {len(template)} byte")

    # Bukti: susun ulang di memori dan bandingkan byte-per-byte.
    rebuilt = template
    for name, token in TOKENS.items():
        rebuilt = rebuilt.replace(token, extracted[name])
    same = rebuilt.encode() == html.encode()
    print(f"rekonstruksi byte-identik: {'YA' if same else 'TIDAK'}")
    if not same:
        return 1
    print(f"sha256 {sha256(rebuilt.encode())}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
