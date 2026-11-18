#!/usr/bin/env bash
# Runs the headless test suite. Fails on any failed check OR any engine/script
# error in the output (Godot keeps running after script errors).
# Usage: GODOT=/path/to/godot tests/run.sh
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path . --import >/dev/null 2>&1
out="$("$GODOT" --headless --path . --script res://tests/run_tests.gd 2>&1)"; code=$?
echo "$out"
if echo "$out" | grep -qE '^(SCRIPT )?ERROR'; then echo "Engine/script errors found — failing."; exit 1; fi
exit $code
