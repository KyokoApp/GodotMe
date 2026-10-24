#!/usr/bin/env bash
# Re - Traveller launcher test driver.
# Usage:  GODOT=/path/to/godot tools/run_launcher_tests.sh
# Requires: godot 4.7.x headless, python3, curl.
set -uo pipefail

GODOT=${GODOT:-godot}
PORT=${PORT:-8765}
HOST="http://127.0.0.1:${PORT}"
FIX=${FIXTURES:-/tmp/rt_fixtures}
KEY=${SIGN_KEY:-}
FAILED=0
SERVER_PID=""

cleanup() {
  if [ -n "$SERVER_PID" ]; then kill "$SERVER_PID" 2>/dev/null; fi
}
trap cleanup EXIT

note() { printf '\n\033[1m=== %s\033[0m\n' "$*"; }
fail() { printf '\033[31mFAILED: %s\033[0m\n' "$*"; FAILED=1; }

scen() { # scen <name> <data-root> [extra args...]
  local name=$1; local root=$2; shift 2
  note "scenario: $name ($root)"
  timeout -k 5 100 "$GODOT" --headless --path launcher res://tests/TestRunner.tscn -- \
      --scenario="$name" --data-root="user://$root" --budget=70 "$@"
  local code=$?
  if [ $code -ne 0 ]; then fail "$name (exit $code)"; fi
  return $code
}

note "importing launcher project"
timeout 180 "$GODOT" --headless --path launcher --import 2>&1 | tail -5
timeout 180 "$GODOT" --headless --path game --import 2>&1 | tail -5

note "building fixtures into $FIX"
rm -rf "$FIX"
mkdir -p "$FIX"
timeout -k 5 120 "$GODOT" --headless --path launcher res://tests/FixtureBuilder.tscn -- \
    --game-dir="$PWD/game" --out="$FIX" ${KEY:+--private-key="$KEY"}
if [ ! -f "$FIX/manifests/v100.json" ]; then
  fail "fixtures were not built"; exit 1
fi

note "starting test server on $HOST"
python3 tools/testserver.py --root "$FIX" --port "$PORT" >/tmp/rt_server.log 2>&1 &
SERVER_PID=$!
sleep 1
curl -sf "$HOST/_health" >/dev/null || { fail "test server did not start"; cat /tmp/rt_server.log; exit 1; }

# ---------------------------------------------------------------- scenarios --
scen unit t_unit

scen first_install t_first --manifest="$HOST/manifests/v100.json"
scen partial_update t_first --manifest="$HOST/manifests/v110.json"
scen offline t_first --manifest="http://127.0.0.1:1/version.json"

scen resume t_resume --manifest="$HOST/manifests/slow.json"
scen bad_hash t_bad --manifest="$HOST/manifests/v110_badhash.json"
scen launcher_too_old t_old --manifest="$HOST/manifests/v100_toonew.json"

# rollback: healthy install -> broken install that crashes on boot -> recovery
scen first_install t_rb --manifest="$HOST/manifests/v100.json"
note "scenario: install_and_boot (the sample pack is rigged to crash)"
timeout -k 5 100 "$GODOT" --headless --path launcher res://tests/TestRunner.tscn -- \
    --scenario=install_and_boot --data-root="user://t_rb" --budget=70 \
    --manifest="$HOST/manifests/v120_broken.json" 2>&1 | tail -12
code=${PIPESTATUS[0]}
if [ "$code" -eq 0 ]; then fail "broken pack did NOT crash the app (rollback test is meaningless)"; fi
scen startup_rollback t_rb

# blocked version gate
scen first_install t_block --manifest="$HOST/manifests/v100.json"
scen prepare_block t_block
scen blocked t_block --manifest="$HOST/manifests/v110.json"

# signature
if [ -n "$KEY" ] && [ -f "$FIX/manifests/v100_signed.json" ]; then
  scen first_install t_signed --manifest="$HOST/manifests/v100_signed.json" --require-signature=1
  scen bad_hash t_badsig --manifest="$HOST/manifests/v100_badsig.json" --require-signature=1
fi

# ------------------------------------------------------------ request audit --
note "request audit"
BAD_UPD_REQ=$(curl -s "$HOST/_requests" | python3 -c "
import json,sys
rows=json.load(sys.stdin)
chars=[r for r in rows if 'characters_110' in r['path']]
print(len(chars))
")
echo "characters_110 requests: $BAD_UPD_REQ (expected 1: delta update hits only the changed pack)"
[ "$BAD_UPD_REQ" = "1" ] || fail "delta update fetched the changed pack $BAD_UPD_REQ times"

note "result"
if [ $FAILED -ne 0 ]; then echo "SUITE FAILED"; exit 1; fi
echo "SUITE PASSED"
