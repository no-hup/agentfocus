#!/usr/bin/env bash
# smoke-real.sh — control-plane e2e against the REAL agentfocus product (agy core).
#
# Spawns a REAL Terminal.app tab (tty + TERM_SESSION_ID), writes a registry entry
# as the emit hook would, runs `agentfocus focus` / `focus-next`, asserts frontmost
# app + focused tab identity — no human eyes required.
#
# CRITICAL TCC TRAP:
#   Terminal spawned via osascript often CANNOT read ~/Desktop, ~/Documents, ~/Downloads.
#   All scripts/outputs used by the spawned tab live under /tmp or ~/.local/share.
#   This file may live in the git checkout on Desktop; it only runs in the *current*
#   shell. The tab runs a copy under ~/.local/share/agentfocus/selftest-run/.
#
# Prerequisites:
#   - Aqua GUI login session
#   - Automation: Terminal (osascript control)
#   - agy CLI at ~/.local/share/agentfocus/bin/agentfocus (or on PATH)
#
# Does NOT claim live focus is verified until YOU run it and see PASS.
set -euo pipefail

REG_DIR="${HOME}/.local/share/agentfocus/registry"
BIN_DIR="${HOME}/.local/share/agentfocus/bin"
RUN_DIR="${HOME}/.local/share/agentfocus/selftest-run"
CLI_CANDIDATES=(
  "${BIN_DIR}/agentfocus"
  "${HOME}/.local/bin/agentfocus"
)
CLI=""

PASS=0
FAIL=0
note() { echo "$*"; }
pass() { echo "PASS  $*"; PASS=$((PASS + 1)); }
fail() { echo "FAIL  $*"; FAIL=$((FAIL + 1)); }

mkdir -p "$REG_DIR" "$RUN_DIR"

# --- resolve CLI ---
for c in "${CLI_CANDIDATES[@]}"; do
  if [ -x "$c" ]; then CLI="$c"; break; fi
done
if [ -z "$CLI" ] && command -v agentfocus >/dev/null 2>&1; then
  CLI="$(command -v agentfocus)"
fi
if [ -z "$CLI" ]; then
  fail "agentfocus CLI not found (expected $BIN_DIR/agentfocus). Install agy core first."
  echo "RESULT: FAIL (missing CLI)"
  exit 1
fi
note "CLI: $CLI"

# --- Automation preflight ---
if ! osascript -e 'tell application "Terminal" to get version' >/dev/null 2>&1; then
  fail "Cannot control Terminal.app via osascript (Automation TCC?). Human must Allow once."
  echo "RESULT: FAIL (Automation)"
  exit 1
fi
pass "Terminal Automation available"

# --- spawn real tab: dump identity to /tmp (never Desktop) ---
SESSION_ID="smoke-real-$(uuidgen | tr '[:upper:]' '[:lower:]')"
OUT="${RUN_DIR}/${SESSION_ID}.env.json"
DONE="${RUN_DIR}/${SESSION_ID}.done"
rm -f "$OUT" "$DONE"

# Script the tab runs — kept under ~/.local/share so TCC does not block it
TAB_SCRIPT="${RUN_DIR}/${SESSION_ID}.tab.sh"
cat > "$TAB_SCRIPT" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
OUT="$1"
DONE="$2"
# Emit identity the real hook would see
TTY_PATH="$(tty 2>/dev/null || echo unknown)"
node -e '
  const fs = require("fs");
  const out = process.argv[1];
  const rec = {
    term_program: process.env.TERM_PROGRAM || "",
    term_session_id: process.env.TERM_SESSION_ID || "",
    tty: process.argv[2] || "",
    cwd: process.cwd(),
    pid: process.pid
  };
  fs.writeFileSync(out, JSON.stringify(rec) + "\n");
' "$OUT" "$TTY_PATH"
echo ok > "$DONE"
# Keep tab alive while the harness runs; it removes the keep-file on exit so
# this returns to the prompt cleanly (no orphaned process → no "terminate?" dialog).
KEEP="${DONE}.keep"
: > "$KEEP"
for _ in $(seq 1 120); do [ -f "$KEEP" ] || break; sleep 0.5; done
EOS
chmod +x "$TAB_SCRIPT"
KEEP_FILE="${DONE}.keep"
# On exit, release the tab's keep-file so its loop ends → returns to prompt →
# closing that Terminal window no longer prompts "terminate running processes?".
cleanup_tab() { rm -f "${KEEP_FILE:-}" 2>/dev/null || true; }
trap cleanup_tab EXIT

# Copy is already under ~/.local/share; invoke via absolute path
note "Spawning Terminal.app tab…"
osascript -e "tell application \"Terminal\" to do script \"bash $(printf %q "$TAB_SCRIPT") $(printf %q "$OUT") $(printf %q "$DONE")\"" >/dev/null

# Poll for completion marker (async do script)
DEADLINE=$((SECONDS + 45))
while [ ! -f "$DONE" ]; do
  if [ "$SECONDS" -ge "$DEADLINE" ]; then
    fail "Timed out waiting for real-tab env dump at $DONE"
    echo "RESULT: FAIL (spawn timeout)"
    exit 1
  fi
  sleep 0.5
done
pass "Real tab env captured: $OUT"

TERM_PROGRAM="$(node -e 'const r=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.stdout.write(r.term_program||"")' "$OUT")"
IDENTITY="$(node -e 'const r=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.stdout.write(r.term_session_id||"")' "$OUT")"
TTY_VAL="$(node -e 'const r=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.stdout.write(r.tty||"")' "$OUT")"
CWD_VAL="$(node -e 'const r=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.stdout.write(r.cwd||"")' "$OUT")"

if [ -z "$IDENTITY" ]; then
  fail "TERM_SESSION_ID empty in real tab (got term_program=$TERM_PROGRAM tty=$TTY_VAL)"
  echo "RESULT: FAIL (no identity)"
  exit 1
fi
pass "identity_handle=TERM_SESSION_ID=$IDENTITY tty=$TTY_VAL"

# --- write registry as emit hook would ---
# ts must be epoch-ms (number) to match the product contract (emit.js writes Date.now()).
# An ISO string here makes the CLI's `now - ts` staleness check NaN → session filtered out.
TS="$(node -e 'process.stdout.write(String(Date.now()))')"
REG_FILE="${REG_DIR}/${SESSION_ID}.json"
node -e '
  const fs = require("fs");
  const [path, session_id, term_program, identity_handle, tty, cwd, ts] = process.argv.slice(1);
  const rec = {
    session_id,
    term_program: term_program || "Apple_Terminal",
    identity_handle,
    tty,
    cwd,
    title: "smoke-real",
    waiting: true,
    ts
  };
  fs.writeFileSync(path, JSON.stringify(rec, null, 2) + "\n");
' "$REG_FILE" "$SESSION_ID" "$TERM_PROGRAM" "$IDENTITY" "$TTY_VAL" "$CWD_VAL" "$TS"
pass "registry written $REG_FILE"

# --- activate another app first so focus must switch ---
open -a "Finder" 2>/dev/null || true
sleep 0.4

# --- agentfocus focus <id> ---
note "Running: $CLI focus $SESSION_ID"
if "$CLI" focus "$SESSION_ID" 2>"${RUN_DIR}/${SESSION_ID}.focus.err"; then
  pass "agentfocus focus exited 0"
else
  fail "agentfocus focus failed: $(tr '\n' ' ' <"${RUN_DIR}/${SESSION_ID}.focus.err")"
fi
sleep 0.8

# --- assert frontmost is Terminal ---
FRONT_RAW="$(lsappinfo info -only name "$(lsappinfo front)" 2>/dev/null || true)"
FRONT="$(echo "$FRONT_RAW" | sed -E 's/.*="([^"]*)".*/\1/')"
if [ "$FRONT" = "Terminal" ]; then
  pass "frontmost=Terminal"
else
  fail "frontmost=\"$FRONT\" expected Terminal"
fi

# --- assert focused tab session / tty matches ---
FOCUSED_TTY="$(osascript -e 'tell application "Terminal" to get tty of selected tab of front window' 2>/dev/null || true)"
# Normalize /dev/ prefix
norm() { echo "$1" | sed 's|^/dev/||'; }
if [ -n "$FOCUSED_TTY" ] && [ "$(norm "$FOCUSED_TTY")" = "$(norm "$TTY_VAL")" ]; then
  pass "focused tab tty matches ($FOCUSED_TTY)"
else
  # Some Terminal builds expose tty differently; try session id via contents is unreliable.
  # Soft-fail detail:
  if [ -z "$FOCUSED_TTY" ]; then
    fail "could not read Terminal selected tab tty (Automation partial?)"
  else
    fail "focused tty=$FOCUSED_TTY expected=$TTY_VAL"
  fi
fi

# --- focus-next path ---
# Ensure waiting=true still (re-write)
node -e '
  const fs = require("fs");
  const p = process.argv[1];
  const r = JSON.parse(fs.readFileSync(p, "utf8"));
  r.waiting = true;
  r.ts = process.argv[2];
  fs.writeFileSync(p, JSON.stringify(r, null, 2) + "\n");
' "$REG_FILE" "$(node -e 'process.stdout.write(String(Date.now()))')"

open -a "Finder" 2>/dev/null || true
sleep 0.3
note "Running: $CLI focus-next"
if "$CLI" focus-next 2>"${RUN_DIR}/${SESSION_ID}.focus-next.err"; then
  pass "agentfocus focus-next exited 0"
else
  fail "agentfocus focus-next failed: $(tr '\n' ' ' <"${RUN_DIR}/${SESSION_ID}.focus-next.err")"
fi
sleep 0.7
FRONT2_RAW="$(lsappinfo info -only name "$(lsappinfo front)" 2>/dev/null || true)"
FRONT2="$(echo "$FRONT2_RAW" | sed -E 's/.*="([^"]*)".*/\1/')"
if [ "$FRONT2" = "Terminal" ]; then
  pass "focus-next frontmost=Terminal"
else
  fail "focus-next frontmost=\"$FRONT2\" expected Terminal"
fi

# --- optional list ---
if "$CLI" list >/tmp/agentfocus-smoke-real-list.txt 2>/dev/null; then
  if grep -q "$SESSION_ID" /tmp/agentfocus-smoke-real-list.txt 2>/dev/null; then
    pass "list includes session_id"
  else
    note "NOTE  list ran but session_id not grepped (format may differ) — not a hard fail"
  fi
else
  note "NOTE  list not available or failed — skip"
fi

echo
echo "=== summary ==="
echo "passed=$PASS failed=$FAIL session_id=$SESSION_ID identity=$IDENTITY"
echo "registry=$REG_FILE"
echo "run_dir=$RUN_DIR"
echo
echo "TCC reminder: never put hook/CLI runtime paths on ~/Desktop (Terminal cannot read)."
if [ "$FAIL" -gt 0 ]; then
  echo "RESULT: FAIL"
  exit 1
fi
echo "RESULT: PASS"
exit 0
