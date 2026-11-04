#!/usr/bin/env python3
"""Setel project Android hasil `npx cap add android` supaya sama dengan APK asli.

Dipakai oleh `.github/workflows/blockzone-apk.yml` (dan bisa dipakai lokal).
Dijalankan **setelah** `npx cap add android`, dari folder `blockzone/apk`.

Yang disetel (semua diambil dari berkas asli, bukan karangan):

| Nilai | Sumber |
| --- | --- |
| appId `com.kyoko.squarezone` | `capacitor.config.json` (asli dari APK) |
| appName `BlockZone` | `capacitor.config.json` (asli dari APK) |
| versionName `1.0.3`, versionCode `3` | `APK_INFO.json` (asli dari APK) |
| minSdk `24`, targetSdk `36` | `APK_INFO.json` (asli dari APK) |
| landscape | `game.html` memanggil `enterFullscreenLandscape()` |

Contoh:

    python3 ../../tools/patch_android.py --android android --www www
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent            # blockzone/tools
ROOT = HERE.parent                                # blockzone/


def fail(msg: str) -> None:
    print("GAGAL: " + msg, file=sys.stderr)
    raise SystemExit(1)


def load_info() -> dict:
    return json.loads((ROOT / "APK_INFO.json").read_text(encoding="utf-8"))


def sub(pattern: str, repl: str, text: str, what: str, path: Path) -> str:
    new, n = re.subn(pattern, repl, text, count=1, flags=re.MULTILINE)
    if n == 0:
        fail(f"pola untuk {what} tidak ditemukan di {path}")
    return new


def patch_gradle(path: Path, info: dict) -> None:
    """Setel applicationId + versi tanpa merusak indentasi berkas Gradle."""
    app = info["app"]
    text = path.read_text(encoding="utf-8")

    text = sub(r'^(\s*)applicationId\s+.*$',
               rf'\g<1>applicationId "{app["package"]}"', text, "applicationId", path)
    text = sub(r'^(\s*)versionCode\s+\d+.*$',
               rf'\g<1>versionCode {app["versionCode"]}', text, "versionCode", path)
    text = sub(r'^(\s*)versionName\s+.*$',
               rf'\g<1>versionName "{app["versionName"]}"', text, "versionName", path)
    text = sub(r'^(\s*)namespace\s+.*$',
               rf'\g<1>namespace "{app["package"]}"', text, "namespace", path)

    path.write_text(text, encoding="utf-8")
    print(f"  {path}: applicationId={app['package']} {app['versionName']} ({app['versionCode']})")


def patch_variables(path: Path, info: dict) -> None:
    """capacitor-cordova-android-plugins/variables.gradle ada di Cap 6-; Cap 7+ pakai
    android/variables.gradle. Keduanya dicek, mana yang ada."""
    app = info["app"]
    if not path.is_file():
        print(f"  (lewati {path.name}: tidak ada)")
        return
    text = path.read_text(encoding="utf-8")
    # template Capacitor menulisnya di dalam blok `ext { ... }` ("minSdkVersion = 23"),
    # versi lama memakai awalan "ext.". Keduanya ditangani.
    text = sub(r'^(\s*)(?:ext\.)?(minSdkVersion)(\s*=\s*)\d+',
               rf'\g<1>\g<2>\g<3>{app["minSdk"]}', text, "minSdkVersion", path)
    text = sub(r'^(\s*)(?:ext\.)?(targetSdkVersion)(\s*=\s*)\d+',
               rf'\g<1>\g<2>\g<3>{app["targetSdk"]}', text, "targetSdkVersion", path)
    path.write_text(text, encoding="utf-8")
    print(f"  {path}: minSdk {app['minSdk']} / targetSdk {app['targetSdk']}")


def patch_manifest(path: Path, admob_app_id: str | None) -> None:
    text = path.read_text(encoding="utf-8")

    if "android:screenOrientation" not in text:
        # AndroidManifest APK asli memakai screenOrientation=6 (sensorLandscape).
        new, n = re.subn(
            r'(<activity\b[^>]*android:name="\.MainActivity")',
            r'\1\n            android:screenOrientation="sensorLandscape"',
            text,
            count=1,
        )
        if n == 0:
            fail(f"<activity .MainActivity> tidak ditemukan di {path}")
        text = new
        print(f"  {path.name}: orientasi dikunci sensorLandscape (sama dengan APK asli)")
    else:
        print(f"  {path.name}: screenOrientation sudah ada, dibiarkan")

    if admob_app_id and "com.google.android.gms.ads.APPLICATION_ID" not in text:
        new, n = re.subn(
            r'</application>',
            '    <meta-data\n'
            '        android:name="com.google.android.gms.ads.APPLICATION_ID"\n'
            f'        android:value="{admob_app_id}" />\n'
            '</application>',
            text,
            count=1,
        )
        if n == 0:
            fail(f"</application> tidak ditemukan di {path}")
        text = new
        print(f"  {path.name}: AdMob App ID disuntikkan")

    path.write_text(text, encoding="utf-8")


def patch_strings(path: Path, app: dict) -> None:
    if not path.is_file():
        print(f"  (lewati {path.name}: tidak ada)")
        return
    text = path.read_text(encoding="utf-8")
    values = {
        "app_name": app["name"],
        "title_activity_main": app["name"],
        "package_name": app["package"],
        "custom_url_scheme": app["package"],
    }
    for key, val in values.items():
        text = re.sub(rf'(<string name="{key}">).*?(</string>)', rf'\g<1>{val}\g<2>', text)
    path.write_text(text, encoding="utf-8")
    print(f"  {path.name}: app_name={app['name']}, package_name={app['package']}")


def patch_update_config(www: Path, base_url: str) -> None:
    cfg = www / "update-config.js"
    if not cfg.is_file():
        fail(f"{cfg} tidak ada")
    before = cfg.read_text(encoding="utf-8")
    cfg.write_text(f'window.BZ_UPDATE = {{ url: "{base_url}" }};\n', encoding="utf-8")
    print(f"  www/update-config.js: URL updater -> {base_url}")
    print(f"    sebelum: {before.strip()}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--android", default="android", help="folder project Android (relatif ke cwd)")
    ap.add_argument("--www", default="www", help="folder web assets (relatif ke cwd)")
    ap.add_argument("--update-url", default=os.environ.get("BLOCKZONE_UPDATE_URL", ""),
                    help="URL situs untuk updater; kosong = biarkan asli (menunjuk /rpg/ yang 404)")
    args = ap.parse_args()

    android = Path(args.android)
    www = Path(args.www)
    if not android.is_dir():
        fail(f"folder android tidak ada: {android} (jalankan `npx cap add android` dulu)")

    info = load_info()
    print("menyetel project Android:")

    patch_variables(android / "variables.gradle", info)
    patch_gradle(android / "app" / "build.gradle", info)
    patch_manifest(android / "app" / "src" / "main" / "AndroidManifest.xml",
                   os.environ.get("ADMOB_APP_ID") or None)
    patch_strings(android / "app" / "src" / "main" / "res" / "values" / "strings.xml",
                  info["app"])
    if args.update_url:
        patch_update_config(www, args.update_url.rstrip("/") + "/")

    print("selesai")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
