#!/usr/bin/env python3
"""Periksa APK hasil build: isi `assets/public/` harus sama dengan arsip asli.

Dipakai `.github/workflows/blockzone-apk.yml` tepat setelah `assembleDebug`,
supaya build yang hijau benar-benar berarti "APK-nya berisi game yang sama",
bukan sekadar "Gradle tidak error".

    python3 blockzone/tools/verify_apk.py android/app/build/outputs/apk/debug/app-debug.apk

Pengecualian yang disengaja: `update-config.js`. Di APK asli berkas itu menunjuk
`https://KyokoApp.github.io/rpg/` yang sudah 404; build baru mengarahkannya ke
situs BlockZone yang hidup. Berkas itu diperiksa isinya (bukan md5-nya).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent          # blockzone/
INFO = ROOT / "APK_INFO.json"
PREFIX = "assets/public/"
REWRITTEN = {"update-config.js"}


def md5(data: bytes) -> str:
    return hashlib.md5(data).hexdigest()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("apk")
    ap.add_argument("--expect-url", default="", help="URL updater yang diharapkan ada di update-config.js")
    args = ap.parse_args()

    apk = Path(args.apk)
    if not apk.is_file():
        print(f"APK tidak ada: {apk}", file=sys.stderr)
        return 1

    info = json.loads(INFO.read_text(encoding="utf-8"))
    expected: dict[str, str] = info["integrity_md5"]

    with zipfile.ZipFile(apk) as z:
        names = z.namelist()
        inside = {n[len(PREFIX):]: n for n in names if n.startswith(PREFIX)}

        print(f"APK      : {apk.name} ({apk.stat().st_size} byte)")
        print(f"berkas web di dalam APK: {len(inside)}")
        for k in sorted(inside):
            print(f"  {PREFIX}{k}")

        problems: list[str] = []
        for name, want in sorted(expected.items()):
            if name not in inside:
                problems.append(f"hilang: {PREFIX}{name}")
                continue
            data = z.read(inside[name])
            if name in REWRITTEN:
                text = data.decode("utf-8", "ignore")
                if "BZ_UPDATE" not in text:
                    problems.append(f"{name}: bukan berkas update-config yang sah")
                elif args.expect_url and args.expect_url not in text:
                    problems.append(f"{name}: URL {args.expect_url} tidak ada di isinya")
                else:
                    print(f"  {name}: ditulis ulang (URL updater) — sesuai rencana")
                continue
            got = md5(data)
            if got != want:
                problems.append(f"berbeda: {PREFIX}{name} ({got} != {want})")
            else:
                print(f"  {name}: md5 cocok")

        extra = sorted(set(inside) - set(expected))
        if extra:
            print(f"  catatan: berkas tambahan di APK: {', '.join(extra)}")

    if problems:
        print("\nAPK TIDAK SESUAI ARSIP:", file=sys.stderr)
        for p in problems:
            print("  - " + p, file=sys.stderr)
        return 1

    print("\nAPK sesuai arsip: semua berkas web md5-nya cocok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
