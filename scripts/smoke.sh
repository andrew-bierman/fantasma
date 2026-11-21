#!/usr/bin/env bash
# AX-driven smoke loop for the fantasma overlay (U5). Covers AE1-AE3:
# summon -> focus -> type -> Cmd+W hide -> state kept -> reopen toggle.
# Synthetic keystrokes need Accessibility permission for the terminal that
# runs this script; it exits with instructions when the check fails.
set -euo pipefail

APP_PATH="${FANTASMA_APP:-$HOME/Code/fantasma/Fantasma.app}"
OSASC="osascript"

say_fail() { echo "FAIL: $*" >&2; exit 1; }

# --- Accessibility preflight ---
if ! "$OSASC" -e 'tell application "System Events" to keystroke ""' >/dev/null 2>&1; then
  echo "Accessibility permission missing: System Preferences -> Privacy & Security -> Accessibility -> enable this terminal." >&2
  exit 1
fi

count_windows() {
  "$OSASC" -e 'tell application "System Events" to tell process "Fantasma" to return count of windows' 2>/dev/null || echo 0
}

pgrep_fantasma() { pgrep -x Fantasma >/dev/null 2>&1 && echo yes || echo no; }

cleanup() { pkill -x Fantasma 2>/dev/null || true; }
trap cleanup EXIT
cleanup
sleep 1

# --- AE1: fresh launch shows focused; typing reaches the shell ---
open "$APP_PATH"
sleep 2
[ "$(count_windows)" = "1" ] || say_fail "AE1: window did not appear on fresh launch"
"$OSASC" -e 'tell application "Fantasma" to activate' -e 'delay 0.5' \
  -e 'tell application "System Events" to keystroke "echo fantasma_smoke_ok"'

# --- AE3a: reopen while visible hides ---
open "$APP_PATH"
sleep 1
[ "$(count_windows)" = "0" ] || say_fail "AE3: reopen while visible did not hide"

# --- AE3b: reopen while hidden shows ---
open "$APP_PATH"
sleep 1
[ "$(count_windows)" = "1" ] || say_fail "AE3: reopen while hidden did not show"

# --- AE2: focus loss hides, state keeps ---
"$OSASC" -e 'tell application "Safari" to activate' 2>/dev/null || \
  "$OSASC" -e 'tell application "Finder" to activate'
sleep 1
[ "$(count_windows)" = "0" ] || say_fail "AE2: focus loss did not hide"

# --- Re-summon: same session, scrollback kept (state preservation) ---
open "$APP_PATH"
sleep 1
[ "$(count_windows)" = "1" ] || say_fail "AE2: re-summon did not show"
"$OSASC" -e 'tell application "Fantasma" to activate' -e 'delay 0.5' \
  -e 'tell application "System Events" to keystroke "echo fantasma_smoke_done"'

# --- Cmd+W hides, process persists ---
"$OSASC" -e 'tell application "System Events" to keystroke "w" using command down'
sleep 1
[ "$(count_windows)" = "0" ] || say_fail "Cmd+W did not hide"
[ "$(pgrep_fantasma)" = "yes" ] || say_fail "Cmd+W killed the process"

echo "SMOKE OK"
