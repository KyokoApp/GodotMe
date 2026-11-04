#!/usr/bin/env bash
# Jalankan BlockZone di browser lokal: ./serve.sh [port]
set -e
cd "$(dirname "$0")/www"
exec python3 -m http.server "${1:-8080}" --bind 0.0.0.0
