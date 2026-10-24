#!/usr/bin/env bash
# Re - Traveller launcher test driver.
#
#   GODOT=/path/to/godot tools/run_launcher_tests.sh            # every case
#   GODOT=/path/to/godot tools/run_launcher_tests.sh partial_update
#
# Cases are independent: each one gets its own sandbox (--data-root) and its own
# manifest, so they can also run as a CI matrix.
set -uo pipefail

GODOT=${GODOT:-godot}
PORT=${PORT:-8765}
HOST="http://127.0.0.1:${PORT}"
FIX=${FIXTURES:-/tmp/rt_fixtures}
KEY=${SIGN_KEY:-}
FAILED=0
SERVER_PID=""

cleanup() { [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null; return 0; }
trap cleanup EXIT

note() { printf '\n=== %s ===\n' "$*"; }
fail() { printf 'FAILED: %s\n' "$*"; FAILED=1; }

godot_headless() { "$GODOT" --headless --path launcher "$@"; }

run_scenario() { # run_scenario <name> <data-root> [extra...]
  local name=$1 root=$2; shift 2
  note "scenario: $name ($root)"
  timeout -k 5 110 "$GODOT" --headless --path launcher res://tests/TestRunner.tscn -- \
      --scenario="$name" --data-root="user://$root" --budget=95 "$@"
  local code=$?
  [ $code -ne 0 ] && fail "$name (exit $code)"
  return $code
}

prepare() {
  note "import projects"
  timeout 240 "$GODOT" --headless --path launcher --import 2>&1 | tail -3
  timeout 240 "$GODOT" --headless --path game --import 2>&1 | tail -3
  note "build fixtures -> $FIX"
  rm -rf "$FIX"; mkdir -p "$FIX"
  timeout -k 5 180 "$GODOT" --headless --path launcher res://tests/FixtureBuilder.tscn -- \
      --game-dir="$PWD/game" --out="$FIX" ${KEY:+--private-key="$KEY"}
  [ -f "$FIX/manifests/v100.json" ] || { fail "fixtures missing"; return 1; }
  note "start test server"
  python3 tools/testserver.py --root "$FIX" --port "$PORT" >/tmp/rt_server.log 2>&1 &
  SERVER_PID=$!
  for _ in $(seq 1 40); do curl -sf "$HOST/_health" >/dev/null && break; sleep 0.25; done
  curl -sf "$HOST/_health" >/dev/null || { fail "server did not start"; cat /tmp/rt_server.log; return 1; }
}

case_manifest() { # name manifest data-root
  run_scenario "$1" "$3" --manifest="$HOST/$2"
}

run_case() {
  case "$1" in
    unit)              run_scenario unit t_unit ;;
    first_install)     case_manifest first_install v100.json t_first ;;
    partial_update)    case_manifest partial_update v110.json t_partial ;;
    resume)            case_manifest resume slow.json t_resume ;;
    bad_hash)          case_manifest bad_hash v110_badhash.json t_bad ;;
    offline)           case_manifest offline v110.json t_offline ;;
    launcher_too_old)  case_manifest launcher_too_old v100_toonew.json t_old ;;
    blocked)           case_manifest blocked v110.json t_blocked ;;
    signed_ok)         run_scenario signed_ok t_signed --manifest="$HOST/v100_signed.json" --require-signature=1 ;;
    signed_bad)        run_scenario signed_bad t_signbad --manifest="$HOST/v100_badsig.json" --require-signature=1 ;;
    crash)
      # 1) install a healthy build, 2) install the rigged build and let it crash,
      # 3) start again: the launcher must roll back on its own.
      case_manifest first_install v100.json t_crash
      note "scenario: install_and_boot (paket sengaja rusak, proses harus mati)"
      timeout -k 5 110 "$GODOT" --headless --path launcher res://tests/TestRunner.tscn -- \
          --scenario=install_and_boot --data-root="user://t_crash" --budget=95 \
          --manifest="$HOST/v120_broken.json" 2>&1 | tail -14
      local code=${PIPESTATUS[0]}
      [ "$code" -eq 0 ] && fail "paket rusak TIDAK membuat aplikasi mati"
      run_scenario startup_rollback t_crash --manifest="$HOST/v110.json"
      ;;
    capture)           run_scenario capture t_capture --manifest="$HOST/slow.json" --captures="${CAPTURES:-/tmp/shots}" ;;
    *) fail "unknown case $1"; return 1 ;;
  esac
}

ALL_CASES="unit first_install partial_update resume bad_hash offline launcher_too_old blocked signed_ok signed_bad crash"

prepare || exit 1
if [ $# -gt 0 ]; then
  for c in "$@"; do run_case "$c"; done
else
  for c in $ALL_CASES; do run_case "$c"; done
fi

note "result"
if [ $FAILED -ne 0 ]; then echo "SUITE FAILED"; exit 1; fi
echo "SUITE PASSED"
