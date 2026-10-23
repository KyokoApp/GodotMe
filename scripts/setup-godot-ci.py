#!/usr/bin/env python3
"""Menambal editor settings Godot supaya ekspor Android jalan di CI.

Godot 4.x **tidak** membaca `ANDROID_HOME` dari environment: path Android SDK
dan Java SDK diambil dari editor settings (`export/android/android_sdk_path`
dan `export/android/java_sdk_path`). Kalau dua nilai ini kosong, ekspor Android
langsung gagal dengan pesan "Android SDK path must be configured in Editor
Settings".

Skrip ini menulis nilai tersebut ke file settings Godot
(`~/.config/godot/editor_settings-4.7.tres`). File yang sudah dibuat Godot
dipertahankan — cuma baris yang relevan yang diganti/ditambahkan.

Dipakai oleh .github/workflows/build-android.yml dan bisa juga dipakai lokal:

    python3 scripts/setup-godot-ci.py --sdk "$ANDROID_HOME" --java "$JAVA_HOME"
"""

from __future__ import annotations

import argparse
import os
import sys

SETTINGS_DIR = os.path.expanduser(os.path.join("~", ".config", "godot"))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--sdk", required=True, help="Path Android SDK (punya direktori build-tools/)")
    parser.add_argument("--java", required=True, help="Path Java SDK (punya bin/java)")
    parser.add_argument(
        "--settings-file",
        default=os.environ.get("GODOT_EDITOR_SETTINGS", "editor_settings-4.7.tres"),
        help="Nama file editor settings (default: editor_settings-4.7.tres)",
    )
    parser.add_argument("--strict", action="store_true", help="Keluar dengan error kalau path tidak valid")
    return parser


def validate(sdk_path: str, java_path: str, strict: bool) -> None:
    problems = []
    if not os.path.isdir(os.path.join(sdk_path, "build-tools")):
        problems.append(f"Android SDK tidak punya direktori build-tools: {sdk_path}")
    if not os.path.exists(os.path.join(java_path, "bin", "java")):
        problems.append(f"Java SDK tidak punya bin/java: {java_path}")
    for problem in problems:
        print(f"[peringatan] {problem}", file=sys.stderr)
    if problems and strict:
        sys.exit(1)


def apply_settings(path: str, values: dict[str, str]) -> None:
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as handle:
            lines = handle.read().splitlines()
    else:
        lines = [
            '[gd_resource type="EditorSettings" format=3]',
            "",
            "[resource]",
        ]

    # Indeks baris "[resource]" — seluruh setting disimpan di bawahnya.
    try:
        resource_index = next(i for i, line in enumerate(lines) if line.strip() == "[resource]")
    except StopIteration:
        lines += ["", "[resource]"]
        resource_index = len(lines) - 1

    for key, value in values.items():
        entry = f'{key} = "{value}"'
        replaced = False
        for i in range(resource_index + 1, len(lines)):
            stripped = lines[i].strip()
            if stripped.startswith(key + " ") or stripped.startswith(key + "="):
                lines[i] = entry
                replaced = True
                break
        if not replaced:
            lines.insert(resource_index + 1, entry)

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines).rstrip() + "\n")


def main() -> None:
    args = build_parser().parse_args()
    validate(args.sdk, args.java, args.strict)

    settings_path = os.path.join(SETTINGS_DIR, args.settings_file)
    apply_settings(settings_path, {
        "export/android/android_sdk_path": args.sdk,
        "export/android/java_sdk_path": args.java,
    })

    print(f"✅ Editor settings ditulis: {settings_path}")
    for key, value in (
        ("android_sdk_path", args.sdk),
        ("java_sdk_path", args.java),
    ):
        print(f"   export/android/{key} = {value}")


if __name__ == "__main__":
    main()
