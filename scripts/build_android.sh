#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# LANTERNFALL Part 1 — Build APK Android lewat Godot CLI (Godot 4.7.2)
#
# Pakai:
#   ./scripts/build_android.sh              # debug APK (debug keystore bawaan)
#   ./scripts/build_android.sh release      # release APK (butuh keystore rilis)
#
# Keystore rilis (opsional) — isi lewat environment variable:
#   export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$PWD/android/keystore/release.keystore"
#   export GODOT_ANDROID_KEYSTORE_RELEASE_USER="lanternfall"
#   export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="********"
#
# Syarat lokal:
#   • godot 4.7.2-stable ada di PATH
#   • export templates 4.7.2.stable sudah terpasang
#   • Android SDK (untuk apksigner) → jalankan `python3 scripts/setup-godot-ci.py`
#     sekali untuk mendaftarkan path SDK ke editor settings Godot.
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
KEYSTORE_DEBUG_PATH="${PROJECT_ROOT}/android/keystore/debug.keystore"
BUILD_DIR="${PROJECT_ROOT}/build"
GODOT_BIN="${GODOT_BIN:-godot}"
PRESET_NAME="Android (arm64-v8a Release/Debug)"
MODE="${1:-debug}"

mkdir -p "${PROJECT_ROOT}/android/keystore" "${BUILD_DIR}"

if [ ! -f "${KEYSTORE_DEBUG_PATH}" ]; then
    echo "[1/4] Membuat debug.keystore Android (CN=Android Debug, O=Android, C=US)..."
    keytool -genkeypair -v \
        -keystore "${KEYSTORE_DEBUG_PATH}" \
        -alias androiddebugkey \
        -keyalg RSA -keysize 2048 -validity 10000 \
        -storepass android -keypass android \
        -dname "CN=Android Debug,O=Android,C=US"
fi

echo "[2/4] Import resource & validasi proyek (Godot headless)..."
"${GODOT_BIN}" --headless --path "${PROJECT_ROOT}" --import

OUT_APK="${BUILD_DIR}/LANTERNFALL_Part1_arm64.apk"

echo "[3/4] Ekspor APK Android (arm64-v8a, minSdk 24, GL Compatibility) mode: ${MODE}..."
if [ "${MODE}" = "release" ]; then
    "${GODOT_BIN}" --headless --path "${PROJECT_ROOT}" \
        --export-release "${PRESET_NAME}" "${OUT_APK}"
else
    "${GODOT_BIN}" --headless --path "${PROJECT_ROOT}" \
        --export-debug "${PRESET_NAME}" "${OUT_APK}"
fi

echo "[4/4] Selesai!"
ls -lh "${OUT_APK}"
echo "APK siap dipasang: ${OUT_APK}"
