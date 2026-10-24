#!/usr/bin/env bash
# Publish a ready-built demo release from a flat directory of artifacts.
#
# Expected layout (produced by .github/workflows/release-demo.yml):
#   $REL/version.json                 <- manifest, package urls are bare file names
#   $REL/<pack>.pck                   <- exactly the packs the manifest lists
#   $REL/re-traveller-launcher.apk
#
# GitHub Release assets live in one flat namespace (no sub-directories), which
# is why the manifest inside $REL must reference "<pack>.pck" and not
# "packs/<pack>.pck": `releases/latest/download/<url>` has to resolve.
#
# Environment:
#   GH_TOKEN  token with contents:write (provided by GitHub Actions)
#   REPO      owner/name  (required: this script can run outside a git checkout,
#             where gh cannot infer the repository from a remote)
#   TAG       release tag, e.g. demo-v0.1.0
#   REL       artifact directory, defaults to /tmp/rel/release
set -euo pipefail

REL="${REL:-/tmp/rel/release}"
TAG="${TAG:-demo-v0.1.0}"
if [ -z "${REPO:-}" ]; then
  echo "REPO is required (owner/name)" >&2
  exit 2
fi
if [ -z "${GH_TOKEN:-}" ]; then
  echo "GH_TOKEN is required" >&2
  exit 2
fi

# Read the build id before moving into the artifact directory: this script can
# run from anywhere, but only the checkout has the launcher project file.
BUILD_ID=$(sed -n 's/^build_id="\(.*\)"/\1/p' "${SRC_DIR:-.}/launcher/project.godot" 2>/dev/null || true)
[ -n "${BUILD_ID:-}" ] || BUILD_ID="(tidak diketahui)"

cd "$REL"

for f in version.json re-traveller-launcher.apk; do
  [ -f "$f" ] || { echo "missing artifact: $REL/$f" >&2; exit 3; }
done
shopt -s nullglob
packs=(*.pck)
shopt -u nullglob
[ ${#packs[@]} -gt 0 ] || { echo "no .pck in $REL" >&2; exit 3; }
files=(version.json "${packs[@]}" re-traveller-launcher.apk)
echo "publishing tag=$TAG repo=$REPO from $REL"
ls -l "${files[@]}"

# Every package the manifest lists must be present, and vice versa: a stale pack
# left in the release would silently never be used.
python3 - "${files[@]}" <<'PY'
import json, sys
listed = {p["url"] for p in json.load(open("version.json"))["packages"]}
present = {f for f in sys.argv[1:] if f.endswith(".pck")}
if listed != present:
    sys.exit("manifest/asset mismatch: only-in-manifest=%s only-on-disk=%s"
             % (sorted(listed - present), sorted(present - listed)))
print("manifest matches", len(listed), "packages on disk")
PY

# Quoted heredoc: the note text is full of backticks (file names), and an
# unquoted heredoc executed them as commands, blanking the published notes.
cat > NOTES.md <<'MD'
## Re - Traveller — demo launcher + paket contoh

**Cara pakai di HP (sekali pasang):**

1. Unduh `re-traveller-launcher.apk`, izinkan "instal dari sumber tidak dikenal", lalu buka.
2. Launcher membaca `version.json` dari rilis ini (default `MANIFEST_URL`),
   memeriksa ukuran + SHA-256, lalu mengunduh enam paket.
3. Tekan **MAIN** — dunia contoh dimuat dari paket `.pck`, bukan dari APK.

Paket yang ada: `core`, `characters`, `enemies`, `world`, `ui`, `audio`.
Rilis berikutnya yang hanya mengubah satu paket akan diunduh sebagai
selisih (delta), bukan unduh ulang semuanya.

APK ini ditandatangani dengan kunci uji. Untuk distribusi, buat APK
bertanda tangan kunci Anda sendiri (`docs/BUILD_AND_RELEASE.md`).

**Build launcher:** `@BUILD_ID@` — nilai ini juga tampil di baris status
launcher. Kalau baris status belum menampilkan nilai yang sama, APK lama masih
terpasang.

> Kunci uji dibuat ulang setiap kali rilis dibangun, jadi Android akan menolak
> "pasang di atas" APK dari rilis berbeda. **Copot pemasangan aplikasi lama
> dulu**, baru pasang APK ini.
MD

sed -i "s/@BUILD_ID@/${BUILD_ID}/g" NOTES.md

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "release $TAG exists -> replacing assets"
  # Drop everything first so removed/renamed packs do not linger in the release.
  gh release view "$TAG" --repo "$REPO" --json assets --jq '.assets[].name' |
    while read -r name; do
      [ -n "$name" ] || continue
      gh release delete-asset "$TAG" "$name" -y --repo "$REPO" >/dev/null 2>&1 || true
    done
  gh release upload "$TAG" "${files[@]}" --repo "$REPO"
  gh release edit "$TAG" --notes-file NOTES.md --latest --repo "$REPO"
else
  echo "release $TAG does not exist -> creating"
  gh release create "$TAG" "${files[@]}" \
    --title "Re - Traveller demo (launcher + paket)" \
    --notes-file NOTES.md --latest --repo "$REPO"
fi

echo "assets now on the release:"
gh release view "$TAG" --repo "$REPO" --json assets \
  --jq '.assets[] | "  \(.name) \(.size)"'
