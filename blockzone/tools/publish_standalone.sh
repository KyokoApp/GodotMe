#!/usr/bin/env bash
# Terbitkan BlockZone sebagai repo GitHub terpisah + Pages, sekali jalan.
#
# Hasilnya: https://github.com/<owner>/BlockZone  (kode situs di akar repo)
#           https://<owner>.github.io/BlockZone/  (game langsung main)
#
# Kenapa repo terpisah tidak dibuat otomatis dari sesi agent: aturan sesi hanya
# mengizinkan push ke satu branch di repo GodotMe. Jadi skrip ini dijalankan
# sendiri oleh pemilik akun (atau di sesi lain) — isinya sudah diuji kering
# dengan --dry-run.
#
# Pemakaian:
#   blockzone/tools/publish_standalone.sh --dry-run     # lihat rencananya saja
#   blockzone/tools/publish_standalone.sh               # buat repo + terbitkan
#   blockzone/tools/publish_standalone.sh --repo BlockZone --owner KyokoApp
#
# Butuh: git, gh (sudah `gh auth login`), python3.

set -euo pipefail

REPO="BlockZone"
OWNER="KyokoApp"
DRY=0
DESC="BlockZone - Battle Royale (pulihan dari APK, arsip byte-identik)"

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --repo) REPO="${2:?}"; shift ;;
    --owner) OWNER="${2:?}"; shift ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "argumen tidak dikenal: $1" >&2; exit 2 ;;
  esac
  shift
done

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

OWNER_LC="$(printf '%s' "$OWNER" | tr '[:upper:]' '[:lower:]')"
SITE_URL="https://${OWNER_LC}.github.io/${REPO}/"

echo "== 1/5 bangun situs (mode datar, akar = www/) =="
python3 "$HERE/build_site.py" --flat --out "$WORK/site" --base-url "$SITE_URL"

cd "$WORK/site"
echo "== 2/5 siapkan commit =="
git init -q -b main
git add -A
git -c user.name="BlockZone publisher" -c user.email="blockzone@local" \
    commit -q -m "BlockZone v1.0.3 - situs from APK archive

Dibangun oleh blockzone/tools/publish_standalone.sh dari
KyokoApp/GodotMe (folder blockzone/). Berkas game identik dengan
assets/public di dalam APK asli; hanya update-config.js yang
diarahkan ke ${SITE_URL}."
echo "   commit: $(git log --oneline -1)"

if [ "$DRY" = "1" ]; then
  cat <<EOF

== mode kering, tidak ada yang dikirim ke GitHub ==
   repo tujuan : $OWNER/$REPO
   URL situs   : $SITE_URL
   yang akan dijalankan:
     gh repo create $OWNER/$REPO --public
     git push origin main
     gh api -X POST repos/$OWNER/$REPO/pages -f 'source[branch]=main' -f 'source[path]=/'
EOF
  exit 0
fi

echo "== 3/5 buat repo (kalau belum ada) =="
if gh repo view "$OWNER/$REPO" >/dev/null 2>&1; then
  echo "   repo $OWNER/$REPO sudah ada, dipakai"
else
  gh repo create "$OWNER/$REPO" --public --description "$DESC"
fi

echo "== 4/5 kirim isi situs =="
git remote add origin "https://github.com/$OWNER/$REPO.git"
git push -u origin main

echo "== 5/5 aktifkan Pages (source: branch main, path /) =="
if gh api "repos/$OWNER/$REPO/pages" >/dev/null 2>&1; then
  echo "   Pages sudah aktif"
else
  gh api -X POST "repos/$OWNER/$REPO/pages" \
      -f 'source[branch]=main' -f 'source[path]=/' >/dev/null
  echo "   Pages diaktifkan"
fi

echo
echo "selesai: $SITE_URL"
echo "(Pages perlu ~1 menit untuk terbit pertama kali)"
