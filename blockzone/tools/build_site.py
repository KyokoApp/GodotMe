#!/usr/bin/env python3
"""Bangun situs statis BlockZone untuk GitHub Pages dari `blockzone/www` yang utuh.

Aturan main:

* Semua berkas di `www/` disalin **apa adanya**, lalu md5-nya diperiksa terhadap
  `APK_INFO.json`. Kalau ada satu byte yang berubah, skrip gagal — arsip pulihan
  ini tidak boleh diam-diam diedit.
* **Satu-satunya** berkas yang ditulis ulang adalah `update-config.js`, karena
  alamat updater aslinya (`https://KyokoApp.github.io/rpg/`) sudah mati bersama
  repo lama. Alamat barunya diisi lewat `--base-url`.
* Hasil akhir: `OUT/blockzone/` (game) + `OUT/index.html` (pengalih ke game).

Contoh:

    python3 blockzone/tools/build_site.py \
        --out dist/site --base-url https://kyokoapp.github.io/GodotMe/blockzone/

    # hanya memeriksa keutuhan arsip, tanpa menulis apa pun:
    python3 blockzone/tools/build_site.py --check-only
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent                      # blockzone/
WWW = ROOT / "www"
INFO = ROOT / "APK_INFO.json"
GAME_DIR = "blockzone"                  # nama folder di dalam situs

ROOT_INDEX = """<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>BlockZone</title>
<link rel="icon" href="{dir}/icon.jpg">
<meta http-equiv="refresh" content="0; url={dir}/">
<style>
  html, body {{ margin: 0; height: 100%; background: #000; color: #fff;
    font-family: system-ui, -apple-system, "Segoe UI", sans-serif; }}
  a {{ color: #fff; }}
  .wrap {{ height: 100%; display: flex; flex-direction: column; gap: 14px;
    align-items: center; justify-content: center; text-align: center; padding: 24px; }}
  img {{ width: 76px; height: 76px; border-radius: 18px;
    box-shadow: 0 0 34px rgba(255,255,255,.22); }}
  .t {{ font-size: 12px; font-weight: 700; letter-spacing: 3px;
    color: rgba(255,255,255,.6); }}
</style>
</head>
<body>
<div class="wrap">
  <img src="{dir}/icon.jpg" alt="">
  <div class="t">MEMBUKA BLOCKZONE…</div>
  <a href="{dir}/">Lanjut manual</a>
</div>
</body>
</html>
"""


def md5(path: Path) -> str:
    return hashlib.md5(path.read_bytes()).hexdigest()


def expected_hashes() -> dict[str, str]:
    info = json.loads(INFO.read_text(encoding="utf-8"))
    return dict(info["integrity_md5"])


def check_archive() -> list[str]:
    """Periksa md5 semua berkas arsip. Kembalikan daftar masalah (kosong = aman)."""
    exp = expected_hashes()
    problems: list[str] = []
    for name, want in sorted(exp.items()):
        p = WWW / name
        if not p.is_file():
            problems.append(f"hilang: www/{name}")
            continue
        got = md5(p)
        if got != want:
            problems.append(f"berubah: www/{name} (md5 {got} != {want})")
    extra = sorted(
        str(p.relative_to(WWW)) for p in WWW.rglob("*")
        if p.is_file() and str(p.relative_to(WWW)) not in exp
    )
    for name in extra:
        problems.append(f"tak terdaftar: www/{name}")
    return problems


def update_config(base_url: str) -> str:
    return f'window.BZ_UPDATE = {{ url: "{base_url}" }};\n'


def build(out: Path, base_url: str, flat: bool = False) -> None:
    if not base_url.endswith("/"):
        raise SystemExit("--base-url harus berakhiran '/'")

    problems = check_archive()
    if problems:
        print("ARSIP TIDAK UTUH:", file=sys.stderr)
        for p in problems:
            print("  - " + p, file=sys.stderr)
        raise SystemExit(1)

    if flat:
        # untuk repo terpisah (BlockZone): isi www/ langsung di akar situs,
        # jadi URL-nya https://<user>.github.io/BlockZone/ tanpa subfolder
        if out.exists():
            shutil.rmtree(out)
        shutil.copytree(WWW, out)
        (out / "update-config.js").write_text(update_config(base_url), encoding="utf-8")
        print(f"situs siap di {out} (mode datar, akar = www/)")
        print(f"  update-config.js -> {base_url}")
        return

    dest = out / GAME_DIR
    if dest.exists():
        shutil.rmtree(dest)
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(WWW, dest)

    cfg = dest / "update-config.js"
    cfg.write_text(update_config(base_url), encoding="utf-8")

    (out / "index.html").write_text(ROOT_INDEX.format(dir=GAME_DIR), encoding="utf-8")

    print(f"situs siap di {out}")
    print(f"  {GAME_DIR}/            game (9 berkas arsip, md5 terverifikasi)")
    print(f"  {GAME_DIR}/update-config.js  -> {base_url}")
    print("  index.html          pengalih ke game")


def main() -> int:
    ap = argparse.ArgumentParser(description="Bangun situs BlockZone untuk GitHub Pages")
    ap.add_argument("--out", help="folder keluaran situs")
    ap.add_argument("--base-url", help="URL publik situs, mis. https://kyokoapp.github.io/GodotMe/blockzone/")
    ap.add_argument("--check-only", action="store_true", help="hanya periksa keutuhan arsip")
    ap.add_argument("--flat", action="store_true",
                    help="isi www/ ditaruh di akar keluaran (untuk repo terpisah, tanpa subfolder)")
    args = ap.parse_args()

    if args.check_only:
        problems = check_archive()
        if problems:
            print("ARSIP TIDAK UTUH:", file=sys.stderr)
            for p in problems:
                print("  - " + p, file=sys.stderr)
            return 1
        print(f"arsip utuh: {len(expected_hashes())} berkas, md5 cocok semua")
        return 0

    if not args.out or not args.base_url:
        ap.error("--out dan --base-url wajib (atau pakai --check-only)")
    build(Path(args.out), args.base_url, flat=args.flat)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
