#!/usr/bin/env bash
# Publish a ready-built demo release from a directory of artifacts.
#
# Expected layout (produced by the release-demo workflow):
#   $REL/version.json  $REL/packs/*.pck  $REL/re-traveller-launcher.apk
#
# Environment:
#   GH_TOKEN  token with contents:write (provided by GitHub Actions)
#   REPO      owner/name  (required: this script runs outside a git checkout,
#             so gh cannot infer the repository from a remote)
#   TAG       release tag, e.g. demo-v0.1.0
#   REL       artifact directory, defaults to /tmp/rel
set -euo pipefail

REL="${REL:-/tmp/rel}"
TAG="${TAG:-demo-v0.1.0}"
if [ -z "${REPO:-}" ]; then
  echo "REPO is required (owner/name)" >&2
  exit 2
fi
if [ -z "${GH_TOKEN:-}" ]; then
  echo "GH_TOKEN is required" >&2
  exit 2
fi

cd "$REL"

# Fail early with a readable message instead of letting gh complain.
for f in version.json re-traveller-launcher.apk; do
  [ -f "$f" ] || { echo "missing artifact: $REL/$f" >&2; exit 3; }
done
shopt -s nullglob
packs=(packs/*.pck)
shopt -u nullglob
[ ${#packs[@]} -gt 0 ] || { echo "no packs in $REL/packs" >&2; exit 3; }
echo "publishing tag=$TAG repo=$REPO"
ls -l version.json re-traveller-launcher.apk "${packs[@]}"

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
MD

# Creating a release for a tag that does not exist yet needs --target, otherwise
# gh points the new tag at the repository's default branch, which may not even
# contain this workflow yet.
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "release $TAG exists -> updating assets"
  for a in version.json "${packs[@]}" re-traveller-launcher.apk; do
    gh release delete-asset "$TAG" "$(basename "$a")" -y --repo "$REPO" >/dev/null 2>&1 || true
  done
  gh release upload "$TAG" version.json "${packs[@]}" re-traveller-launcher.apk \
    --clobber --repo "$REPO"
  gh release edit "$TAG" --notes-file NOTES.md --latest --repo "$REPO"
else
  echo "release $TAG does not exist -> creating"
  gh release create "$TAG" version.json "${packs[@]}" re-traveller-launcher.apk \
    --title "Re - Traveller demo (launcher + paket)" \
    --notes-file NOTES.md --latest --repo "$REPO"
fi

gh release view "$TAG" --repo "$REPO" --json assets \
  --jq '.assets[] | "\(.name) \(.size)"'
