#!/usr/bin/env python3
"""Re - Traveller : release builder.

Turns a Godot export of the *game* project into the release folder the launcher
expects:

    dist/v<version>/
        version.json          <- Config.MANIFEST_URL points at this file
        version.json.sig      <- detached RSA-SHA256 signature (optional)
        packs/core.pck
        packs/characters.pck
        packs/enemies.pck
        packs/world.pck
        packs/ui.pck
        packs/audio.pck

Every .pck is hashed with SHA-256 and listed in the manifest in load order.
Because package file names are version-free, only changed packages get new
hashes - the launcher then downloads just those (delta update).

Usage
  # from exported packs (recommended: one PCK export per package)
  python3 tools/make_release.py --version 1.2.0 \\
      --packs core=build/core.pck characters=build/characters.pck \\
      --changelog-file CHANGELOG.md --out dist/v1.2.0 \\
      --sign-key ~/retraveller_manifest_private.pem

  # quick single-package release straight from a folder export
  python3 tools/make_release.py --version 1.2.0 --single-pck build/re-traveller.pck

Notes
  * The APK is never rebuilt for a content update.
  * min_launcher_version is copied from Config.LAUNCHER_VERSION unless you pass
    --min-launcher.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import shutil
import subprocess
import sys

PACK_ORDER = [
    ("core", 10),
    ("characters", 20),
    ("enemies", 30),
    ("world", 40),
    ("ui", 50),
    ("audio", 60),
]
ORDER = dict(PACK_ORDER)


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def read_launcher_version(repo: str) -> int:
    cfg = os.path.join(repo, "launcher", "scripts", "Config.gd")
    try:
        with open(cfg, encoding="utf-8") as fh:
            for line in fh:
                if "const LAUNCHER_VERSION" in line:
                    return int(line.split(":=")[1].strip())
    except OSError:
        pass
    return 1


def changelog_lines(path: str | None, inline: list[str]) -> list[str]:
    if inline:
        return inline
    if not path:
        return []
    out: list[str] = []
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            line = line.lstrip("-*• ").strip()
            if line:
                out.append(line)
    return out[:12]


def sign_manifest(manifest_path: str, key_path: str) -> None:
    sig_path = manifest_path + ".sig"
    # openssl gives us a detached, binary RSA-SHA256 signature over the exact
    # bytes of version.json; the launcher verifies it with the public key it
    # ships inside the APK.
    subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", key_path, "-out", sig_path + ".bin", manifest_path],
        check=True,
    )
    with open(sig_path + ".bin", "rb") as fh:
        raw = fh.read()
    os.remove(sig_path + ".bin")
    with open(sig_path, "w", encoding="utf-8") as fh:
        fh.write(base64.b64encode(raw).decode())
    print(f"  signed   -> {os.path.basename(sig_path)} ({len(raw)} bytes)")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", required=True)
    ap.add_argument("--out", required=True, help="output folder, e.g. dist/v1.2.0")
    ap.add_argument("--packs", nargs="*", default=[], help="name=path pairs")
    ap.add_argument("--single-pck", help="use one pck for every package slot")
    ap.add_argument("--main-scene", default="res://game/Main.tscn")
    ap.add_argument("--changelog-file", default=None)
    ap.add_argument("--changelog", nargs="*", default=[], help="inline changelog lines")
    ap.add_argument("--min-launcher", type=int, default=None)
    ap.add_argument("--sign-key", default=None)
    ap.add_argument("--base-url", default="")
    ap.add_argument("--release-dir", default="")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.abspath(args.out)
    packs_dir = os.path.join(out, "packs")

    sources: list[tuple[str, str]] = []
    if args.single_pck:
        for name, _order in PACK_ORDER:
            sources.append((name, args.single_pck))
    for pair in args.packs:
        if "=" not in pair:
            print(f"bad --packs entry: {pair}", file=sys.stderr)
            return 2
        name, path = pair.split("=", 1)
        if name not in ORDER:
            print(f"unknown package '{name}' (expected one of {list(ORDER)})", file=sys.stderr)
            return 2
        sources.append((name, path))
    if not sources:
        print("nothing to package: pass --packs or --single-pck", file=sys.stderr)
        return 2

    if not args.dry_run:
        os.makedirs(packs_dir, exist_ok=True)

    packages = []
    total = 0
    print(f"Re - Traveller release {args.version} -> {out}")
    for name, src in sorted(sources, key=lambda s: ORDER[s[0]]):
        if not os.path.isfile(src):
            print(f"missing pack for '{name}': {src}", file=sys.stderr)
            return 2
        dst = os.path.join(packs_dir, f"{name}.pck")
        digest = sha256_file(src)
        size = os.path.getsize(src)
        total += size
        if not args.dry_run:
            shutil.copyfile(src, dst)
        packages.append({
            "name": name,
            "url": f"packs/{name}.pck",
            "size": size,
            "sha256": digest,
            "load_order": ORDER[name],
        })
        print(f"  {name:<11} {size:>10,} B  {digest[:12]}…")

    manifest = {
        "schema": 1,
        "game": "re-traveller",
        "version": args.version,
        "min_launcher_version": args.min_launcher if args.min_launcher is not None
        else read_launcher_version(repo),
        "released_at": __import__("datetime").datetime.now(
            __import__("datetime").timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "main_scene": args.main_scene,
        "changelog": changelog_lines(args.changelog_file, args.changelog),
        "packages": packages,
    }
    if args.base_url:
        for pkg in packages:
            pkg["url"] = f"{args.base_url.rstrip('/')}/{pkg['url']}"

    body = json.dumps(manifest, indent=2, ensure_ascii=False) + "\n"
    manifest_path = os.path.join(out, "version.json")
    if args.dry_run:
        print(body)
        return 0
    with open(manifest_path, "w", encoding="utf-8") as fh:
        fh.write(body)
    print(f"  manifest   {manifest_path}  ({total/1048576:.1f} MB total)")

    if args.sign_key:
        sign_manifest(manifest_path, args.sign_key)

    if args.release_dir:
        # convenient flat folder for "upload everything in here" hosting
        flat = os.path.abspath(args.release_dir)
        os.makedirs(os.path.join(flat, "packs"), exist_ok=True)
        for pkg in packages:
            shutil.copyfile(os.path.join(out, pkg["url"]), os.path.join(flat, pkg["url"]))
        shutil.copyfile(manifest_path, os.path.join(flat, "version.json"))
        if os.path.exists(manifest_path + ".sig"):
            shutil.copyfile(manifest_path + ".sig", os.path.join(flat, "version.json.sig"))
        print(f"  flat copy  {flat}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
