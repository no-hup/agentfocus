#!/usr/bin/env bash
# Self-check for adapters/editor_window.js.
#
# Why this exists: a verifier that silently always misses is a REGRESSION, not a
# safe default — bare `open -a <root>` lands correctly most of the time today, and
# an always-miss verifier would downgrade every one of those clicks to app-level
# activate. So this asserts against THIS machine's real window state, plus a
# synthetic fixture for the two cases live state can't be relied on to contain.
set -uo pipefail

MOD="$(cd "$(dirname "$0")/.." && pwd)/adapters/editor_window.js"
APP="${1:-Visual Studio Code}"
PASS=0; FAIL=0

check() { # check <name> <expected> <actual>
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "PASS  $1";
  else FAIL=$((FAIL+1)); echo "FAIL  $1"; echo "        expected: '$2'"; echo "        actual:   '$3'"; fi
}
match() { node "$MOD" "$1" "$2" | sed -n 's/^match\t//p'; }

# --- live state -------------------------------------------------------------
OPEN="$(node "$MOD" "$APP" | sed -n 's/^open\t//p')"   # bash 3.2 on macOS: no mapfile
COUNT="$(printf '%s\n' "$OPEN" | grep -c . || true)"
if [ "$COUNT" -eq 0 ]; then
  echo "SKIP  no open-folder state for \"$APP\" (editor never run, or one untitled window)"
  echo "      live checks skipped; synthetic checks still run"
else
  echo "live: $COUNT open folder(s) for \"$APP\""
  F="$(printf '%s\n' "$OPEN" | head -1)"
  check "exact cwd matches its own window"      "$F"  "$(match "$APP" "$F")"
  check "deep subdir walks up to its window"    "$F"  "$(match "$APP" "$F/no/such/sub/dir")"
  check "unopened path is a miss"               ""    "$(match "$APP" /nonexistent-agentfocus-xyz)"
fi

# --- synthetic fixture: single-window state, %-encoding, $HOME refusal --------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/Library/Application Support/Fake/User/globalStorage"
# openedWindows is EMPTY on purpose: the editor only writes it when >1 window is
# open, so a one-window session lives in lastActiveWindow alone.
cat > "$TMP/Library/Application Support/Fake/User/globalStorage/storage.json" <<EOF
{"windowsState":{"openedWindows":[],"lastActiveWindow":{"folder":"file://$TMP/My%20Proj"}}}
EOF
mkdir -p "$TMP/My Proj/src"
fmatch() { HOME="$TMP" node "$MOD" Fake "$1" | sed -n 's/^match\t//p'; }

check "single-window state (lastActiveWindow only)" "$TMP/My Proj"  "$(fmatch "$TMP/My Proj")"
check "percent-encoded folder + walk-up"            "$TMP/My Proj"  "$(fmatch "$TMP/My Proj/src")"
check "unrelated sibling is a miss"                 ""              "$(fmatch "$TMP")"

# $HOME open as a window: exact match allowed, ancestor match refused (raising the
# home window for a deep session is a guess, and a wrong raise is worse than none).
cat > "$TMP/Library/Application Support/Fake/User/globalStorage/storage.json" <<EOF
{"windowsState":{"openedWindows":[],"lastActiveWindow":{"folder":"file://$TMP"}}}
EOF
check "\$HOME as exact cwd is honoured"   "$TMP"  "$(fmatch "$TMP")"
check "\$HOME as ancestor is refused"     ""      "$(fmatch "$TMP/My Proj/src")"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
