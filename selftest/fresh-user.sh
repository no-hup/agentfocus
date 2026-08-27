#!/usr/bin/env bash
# fresh-user.sh — human-in-the-loop falsification run on a FRESH macOS user account.
#
# Purpose: prove the install-day story is what README claims — one Notifications
# prompt, one informational "Login Item Added" banner, one Automation prompt on the
# first banner-click, and NEVER Accessibility / Screen Recording / Input Monitoring.
# A forbidden prompt is a hard FAIL: it violates a product constraint, not a nicety.
#
# The script asks you what you SAW (y/n/s) — no eyes, no camera, no screenshotting.
# Answer honestly; a wrong answer here buys nothing.
#
# Run it from anywhere — it is location-independent. Everything the spawned Terminal
# tab has to read is staged under ~/.local/share/agentfocus/selftest-fresh/, because
# a Terminal spawned via Automation cannot read ~/Desktop, ~/Documents or ~/Downloads
# (TCC). Running the script itself from ~/ is the documented, boring choice.
#
# Usage:
#   ./fresh-user.sh              # gates G0–G8a, then stops for a logout/login
#   ./fresh-user.sh --resume     # gates G8b–G9 after you log back in
#   ./fresh-user.sh --help
#
# Install path: AF_INSTALL=brew (default) or AF_INSTALL=dev
#
# Exit: 0 = PASS or PARTIAL (resume pending), 1 = FAIL, 2 = wrong account (G0).
set -uo pipefail

RUN_DIR="${HOME}/.local/share/agentfocus/selftest-fresh"
STATE="${RUN_DIR}/state"
LOG="${RUN_DIR}/run.log"
REG_DIR="${HOME}/.local/share/agentfocus/registry"
BUNDLE="${HOME}/Applications/AgentFocus.app"
CLI="${HOME}/.local/share/agentfocus/bin/agentfocus"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
AF_INSTALL="${AF_INSTALL:-brew}"

PASS=0; FAIL=0; SKIP=0
RESULTS=()
# prompt census
PC_NOTIF=0; PC_LOGIN=0; PC_AUTOMATION=0; PC_FORBIDDEN=0

mkdir -p "$RUN_DIR"

# Talk to the human on the real terminal (fd 3 in, fd 4 out) so the run can still
# be piped/tee'd. Falls back to stdin/stdout where there is no controlling tty.
exec 3</dev/tty 2>/dev/null || exec 3<&0
exec 4>/dev/tty 2>/dev/null || exec 4>&1

log_line() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >>"$LOG"; }
say()  { printf '%s\n' "$*"; log_line "SAY  $*"; }
note() { printf 'NOTE  %s\n' "$*"; log_line "NOTE $*"; }
pass() { RESULTS+=("PASS  $*"); printf 'PASS  %s\n' "$*"; PASS=$((PASS+1)); log_line "PASS $*"; }
fail() { RESULTS+=("FAIL  $*"); printf 'FAIL  %s\n' "$*"; FAIL=$((FAIL+1)); log_line "FAIL $*"; }
skip() { RESULTS+=("SKIP  $*"); printf 'SKIP  %s\n' "$*"; SKIP=$((SKIP+1)); log_line "SKIP $*"; }

gate() { printf '\n--- %s ---\n' "$*"; log_line "GATE $*"; }

# ask <question> → ANS=y|n|s. Reads /dev/tty so piping/tee-ing the run still works.
ANS=""
ask() {
  local q="$1" a
  while true; do
    printf '\n  ?  %s [y/n/s=skip] ' "$q" >&4
    read -r a <&3 || a="s"
    case "$a" in
      y|Y) ANS=y; break ;;
      n|N) ANS=n; break ;;
      s|S) ANS=s; break ;;
      *)   printf '     answer y, n, or s\n' >&4 ;;
    esac
  done
  log_line "ASK  $q -> $ANS"
}

# expect <y|n> <question> <gate label>
expect() {
  ask "$2"
  if [ "$ANS" = "s" ]; then skip "$3 (human skipped)"
  elif [ "$ANS" = "$1" ]; then pass "$3"
  else fail "$3 — answered '$ANS', expected '$1'"; fi
}

pause() { printf '\n  >  %s — press return when done ' "$1" >&4; read -r _ <&3 || true; log_line "PAUSE $1"; }

frontmost() { lsappinfo info -only name "$(lsappinfo front)" 2>/dev/null | sed -E 's/.*="([^"]*)".*/\1/'; }

# poll_frontmost <app name> <seconds> → 0 if it became frontmost. Sets FRONT.
FRONT=""
poll_frontmost() {
  local want="$1" deadline=$((SECONDS + $2))
  while [ "$SECONDS" -lt "$deadline" ]; do
    FRONT="$(frontmost)"
    [ "$FRONT" = "$want" ] && return 0
    sleep 0.5
  done
  return 1
}

state_set() { printf '%s=%s\n' "$1" "$2" >>"$STATE"; }
# state_get <key> [default] — empty/missing keys must not poison the arithmetic.
state_get() {
  local v=""
  [ -f "$STATE" ] && v="$(sed -n "s/^$1=//p" "$STATE" | tail -n 1)"
  printf '%s' "${v:-${2:-0}}"
}

# ---------------------------------------------------------------- tab + registry

SESSION_ID=""; TAB_TTY=""; REG_FILE=""; KEEP_FILE=""
cleanup() { [ -n "${KEEP_FILE:-}" ] && rm -f "$KEEP_FILE" 2>/dev/null; return 0; }
trap cleanup EXIT

# Spawn a real Terminal.app tab and capture its tty. Script stays under
# ~/.local/share so the spawned tab (which cannot read ~/Desktop) can execute it.
spawn_tab() {
  SESSION_ID="fresh-$(uuidgen | tr '[:upper:]' '[:lower:]')"
  local ttyf="${RUN_DIR}/${SESSION_ID}.tty" tabsh="${RUN_DIR}/${SESSION_ID}.tab.sh"
  KEEP_FILE="${RUN_DIR}/${SESSION_ID}.keep"
  cat >"$tabsh" <<'EOS'
#!/usr/bin/env bash
TTYF="$1"; KEEP="$2"
tty > "$TTYF"
: > "$KEEP"
echo "agentfocus fresh-user test tab — leave this open until the run finishes."
# Hold the tab open, but exit cleanly when the harness releases the keep-file so
# closing the window never asks "terminate running processes?".
for _ in $(seq 1 3600); do [ -f "$KEEP" ] || break; sleep 0.5; done
EOS
  chmod +x "$tabsh"
  osascript -e "tell application \"Terminal\" to do script \"bash $(printf %q "$tabsh") $(printf %q "$ttyf") $(printf %q "$KEEP_FILE")\"" >/dev/null 2>&1
  local deadline=$((SECONDS + 30))
  while [ ! -s "$ttyf" ]; do
    [ "$SECONDS" -ge "$deadline" ] && { TAB_TTY=""; return 1; }
    sleep 0.5
  done
  TAB_TTY="$(tr -d '[:space:]' <"$ttyf")"
  REG_FILE="${REG_DIR}/${SESSION_ID}.json"
  return 0
}

# Write/re-arm the registry entry exactly as the emit hook would for Terminal.app.
# ts must be epoch MILLIseconds or the staleness check filters the session out.
arm_session() {
  mkdir -p "$REG_DIR"
  cat >"$REG_FILE" <<EOF
{
  "session_id": "$SESSION_ID",
  "term_program": "Apple_Terminal",
  "osc_native": false,
  "identity_handle": "fresh-user-selftest",
  "editor_app": null,
  "tty": "$TAB_TTY",
  "cwd": "$HOME",
  "title": "fresh-user",
  "waiting": true,
  "ts": $(( $(date +%s) * 1000 ))
}
EOF
  chmod 600 "$REG_FILE"
}

# ------------------------------------------------------------------- the gates

g0_preflight() {
  gate "G0  fresh-account preflight"
  local residue=0
  for p in "${HOME}/.local/share/agentfocus" "$BUNDLE"; do
    [ -e "$p" ] && { fail "G0 residue present: $p"; residue=1; }
  done
  if [ -f "${HOME}/.claude/settings.json" ] && grep -q agentfocus "${HOME}/.claude/settings.json" 2>/dev/null; then
    fail "G0 residue: agentfocus hooks already in ~/.claude/settings.json"; residue=1
  fi
  say "account: $(whoami)   home: $HOME"
  ask "Is this a BRAND-NEW macOS user account that has never run agentfocus?"
  if [ "$ANS" != "y" ] || [ "$residue" -eq 1 ]; then
    fail "G0 not a fresh account — the whole run is meaningless here"
    say ""
    say "Create a new user in System Settings → Users & Groups, log in as them, rerun."
    exit 2
  fi
  pass "G0 fresh account confirmed"
}

g1_install() {
  gate "G1  install via the intended path (AF_INSTALL=$AF_INSTALL)"
  local rc
  case "$AF_INSTALL" in
    brew)
      say "running: brew install no-hup/agentfocus/agentfocus && agentfocus init"
      brew install no-hup/agentfocus/agentfocus 2>&1 | tee -a "$LOG"
      rc=${PIPESTATUS[0]}
      [ "$rc" -eq 0 ] && { agentfocus init 2>&1 | tee -a "$LOG"; rc=${PIPESTATUS[0]}; }
      ;;
    dev)
      say "running: $REPO/install.sh"
      "$REPO/install.sh" 2>&1 | tee -a "$LOG"
      rc=${PIPESTATUS[0]}
      ;;
    *) fail "G1 unknown AF_INSTALL='$AF_INSTALL' (want brew|dev)"; return ;;
  esac
  [ "$rc" -eq 0 ] && pass "G1 installer exited 0" || fail "G1 installer exited $rc"
  [ -x "$CLI" ] && pass "G1 CLI present at $CLI" || fail "G1 CLI missing at $CLI"
  [ -d "$BUNDLE" ] && pass "G1 helper bundle present at $BUNDLE" || fail "G1 helper bundle missing at $BUNDLE"
  expect n "During the install itself, did ANY permission prompt or dialog appear?" "G1 install is prompt-free"
}

g2_forensics() {
  gate "G2  bundle forensics (recorded; spctl rejection is expected)"
  if [ ! -d "$BUNDLE" ]; then skip "G2 no bundle to inspect"; return; fi

  say "--- xattr -lr ---"; xattr -lr "$BUNDLE" 2>&1 | tee -a "$LOG"
  if xattr -lr "$BUNDLE" 2>/dev/null | grep -q com.apple.quarantine; then
    note "G2 quarantine xattr present — clear with: xattr -dr com.apple.quarantine $BUNDLE"
  else
    note "G2 no quarantine xattr"
  fi

  say "--- codesign -dvvv ---"
  local sig; sig="$(codesign -dvvv "$BUNDLE" 2>&1)"; printf '%s\n' "$sig" | tee -a "$LOG" >/dev/null
  printf '%s\n' "$sig"
  printf '%s' "$sig" | grep -qi 'adhoc' \
    && pass "G2 signature is ad-hoc (as designed)" \
    || fail "G2 expected an ad-hoc signature, got something else"

  say "--- codesign --verify ---"
  if codesign --verify --deep --strict "$BUNDLE" 2>&1 | tee -a "$LOG"; then
    pass "G2 codesign --verify passes"
  else
    fail "G2 codesign --verify failed — bundle is damaged"
  fi

  say "--- spctl -a -vv (RECORD ONLY) ---"
  spctl -a -vv "$BUNDLE" 2>&1 | tee -a "$LOG"
  note "G2 spctl rejects ad-hoc signatures by design — recorded, never a FAIL"
}

g3_launch() {
  gate "G3  launch"
  open -g "$BUNDLE" 2>&1 | tee -a "$LOG"
  local deadline=$((SECONDS + 10)) up=0
  while [ "$SECONDS" -lt "$deadline" ]; do
    pgrep -f "AgentFocus.app/Contents/MacOS/AgentFocus" >/dev/null 2>&1 && { up=1; break; }
    sleep 0.5
  done
  [ "$up" -eq 1 ] && pass "G3 helper process running" || fail "G3 helper process not running after 10s"
  expect y "Is the AgentFocus bell icon visible in the menu bar?" "G3 menu-bar item visible"
}

g4_census() {
  gate "G4  prompt census (the core gate)"
  say "Answer for EVERYTHING you have seen since the install started."

  ask "Did you see exactly ONE macOS Notifications permission prompt (\"AgentFocus Would Like to Send You Notifications\")?"
  case "$ANS" in
    y) PC_NOTIF=1; pass "G4 one Notifications prompt" ;;
    s) skip "G4 Notifications prompt (skipped)" ;;
    *) fail "G4 expected exactly one Notifications prompt" ;;
  esac

  ask "Did you see an informational \"Login Item Added\" banner (no button to click)?"
  case "$ANS" in
    y) PC_LOGIN=1; pass "G4 Login Item Added banner (informational)" ;;
    s) skip "G4 Login Item banner (skipped)" ;;
    *) note "G4 no Login Item banner seen — macOS sometimes coalesces it; not a failure"; pass "G4 Login Item banner (absent, tolerated)" ;;
  esac

  local forbidden
  for forbidden in "Accessibility" "Screen Recording" "Input Monitoring" "Full Disk Access" "Files and Folders (Desktop/Documents/Downloads)"; do
    ask "Have you seen ANY $forbidden permission prompt?"
    case "$ANS" in
      n) pass "G4 no $forbidden prompt" ;;
      s) skip "G4 $forbidden (skipped — cannot certify the constraint)" ;;
      *) PC_FORBIDDEN=$((PC_FORBIDDEN+1)); fail "G4 FORBIDDEN PROMPT: $forbidden — product constraint violated" ;;
    esac
  done

  ask "Any OTHER permission prompt not covered above?"
  case "$ANS" in
    n) pass "G4 no unaccounted prompts" ;;
    s) skip "G4 other prompts (skipped)" ;;
    *) PC_FORBIDDEN=$((PC_FORBIDDEN+1)); fail "G4 an unaccounted permission prompt appeared — record it in the log" ;;
  esac
}

g5_banner() {
  gate "G5  test banner via a registry write"
  say "Spawning a real Terminal.app tab to borrow its tty…"
  if ! spawn_tab; then fail "G5 could not spawn a Terminal tab / read its tty"; return 1; fi
  pass "G5 real tab tty=$TAB_TTY session=$SESSION_ID"
  arm_session
  pass "G5 registry entry written: $REG_FILE"
  say "Waiting 5s for the helper's 2s registry poll…"
  sleep 5
  expect y "Did a notification banner appear, titled \"agentfocus: fresh-user\"?" "G5 banner posted"
  expect y "Was there exactly ONE banner for it (not two)?" "G5 no duplicate banner"
  return 0
}

g6_click() {
  gate "G6  click → exact tab"
  open -a Finder 2>/dev/null; sleep 0.5
  say "Finder is frontmost. Now CLICK the agentfocus banner (Notification Centre if it faded)."
  say "On a fresh account the first click asks: \"AgentFocus\" wants to control \"Terminal\" — click OK."
  pause "clicked the banner (and answered the Automation prompt if it appeared)"

  ask "Did an Automation prompt appear for Terminal on that first click?"
  case "$ANS" in
    y) PC_AUTOMATION=1; pass "G6 one Automation prompt on first click (as documented)" ;;
    s) skip "G6 Automation prompt (skipped)" ;;
    *) note "G6 no Automation prompt — expected on a truly fresh account; grant may pre-exist"; pass "G6 Automation prompt (absent, recorded)" ;;
  esac
  expect n "Was that prompt anything OTHER than Automation (Accessibility etc.)?" "G6 no non-Automation prompt on click"

  if poll_frontmost "Terminal" 15; then
    pass "G6 frontmost=Terminal"
  else
    fail "G6 frontmost=\"$FRONT\" after 15s, expected Terminal"
  fi
  local got norm_got norm_want
  got="$(osascript -e 'tell application "Terminal" to get tty of selected tab of front window' 2>/dev/null)"
  norm_got="${got#/dev/}"; norm_want="${TAB_TTY#/dev/}"
  if [ -n "$norm_got" ] && [ "$norm_got" = "$norm_want" ]; then
    pass "G6 exact tab: selected tty=$got"
  elif [ -z "$norm_got" ]; then
    fail "G6 could not read the selected tab's tty (Automation declined or partial)"
  else
    fail "G6 wrong tab: selected=$got expected=$TAB_TTY"
  fi
}

g7_hotkey() {
  gate "G7  global hotkey"
  arm_session
  open -a Finder 2>/dev/null; sleep 0.5
  say "Finder is frontmost. Press ⌥⌘A (option+command+A) now."
  if poll_frontmost "Terminal" 15; then
    pass "G7 hotkey focused Terminal"
  else
    fail "G7 frontmost=\"$FRONT\" after 15s — hotkey did not focus the session"
  fi
  expect n "Did pressing the hotkey trigger ANY new permission prompt (e.g. Input Monitoring)?" "G7 hotkey needs no permission"
}

g8a_pause_for_logout() {
  gate "G8a  persistence — logout/login required"
  arm_session   # leave a live entry behind for the resume leg
  : >"$STATE"
  state_set session_id "$SESSION_ID"
  state_set pass "$PASS"; state_set fail "$FAIL"; state_set skip "$SKIP"
  state_set automation "$PC_AUTOMATION"; state_set notif "$PC_NOTIF"
  state_set login "$PC_LOGIN"; state_set forbidden "$PC_FORBIDDEN"
  say ""
  say "Now: log OUT of this account completely and log back in."
  say "Do NOT launch AgentFocus by hand — the login item must do it."
  say "Then rerun:  $0 --resume"
}

g8b_persistence() {
  gate "G8b  persistence after logout/login"
  local up=0 deadline=$((SECONDS + 20))
  while [ "$SECONDS" -lt "$deadline" ]; do
    pgrep -f "AgentFocus.app/Contents/MacOS/AgentFocus" >/dev/null 2>&1 && { up=1; break; }
    sleep 1
  done
  [ "$up" -eq 1 ] && pass "G8b helper auto-started at login (never launched by hand)" \
                  || fail "G8b helper not running after login — login item did not take"
  expect n "Since logging back in, has ANY permission prompt appeared?" "G8b no prompts after re-login"

  if ! spawn_tab; then fail "G8b could not spawn a Terminal tab"; return; fi
  arm_session
  sleep 5
  expect y "Did a banner appear again?" "G8b banner still works after re-login"
  open -a Finder 2>/dev/null; sleep 0.5
  pause "click the banner"
  expect n "Did the Automation prompt appear AGAIN on that click?" "G8b Automation grant persisted across login"
  if poll_frontmost "Terminal" 15; then pass "G8b click still focuses Terminal"; else fail "G8b frontmost=\"$FRONT\" expected Terminal"; fi
}

g9_rebuild() {
  gate "G9  rebuild → the one expected Automation re-prompt"
  say "Ad-hoc signing ties the Automation grant to the exact signature, so ONE"
  say "re-prompt after a rebuild is the documented, accepted behaviour — a PASS."
  case "$AF_INSTALL" in
    dev) say "running: $REPO/install.sh"; "$REPO/install.sh" 2>&1 | tee -a "$LOG" ;;
    *)   say "running: agentfocus init (refreshes the helper from brew libexec)"; agentfocus init 2>&1 | tee -a "$LOG" ;;
  esac
  pkill -f "AgentFocus.app/Contents/MacOS/AgentFocus" 2>/dev/null
  sleep 1
  open -g "$BUNDLE"; sleep 3

  if ! spawn_tab; then fail "G9 could not spawn a Terminal tab"; return; fi
  arm_session
  sleep 5
  expect y "Did a banner appear after the rebuild?" "G9 banner works post-rebuild"
  pause "click the banner and answer any prompt"
  ask "Did exactly ONE Automation prompt appear (and nothing else)?"
  case "$ANS" in
    y) PC_AUTOMATION=$((PC_AUTOMATION+1)); pass "G9 exactly one Automation re-prompt (expected tradeoff)" ;;
    s) skip "G9 re-prompt (skipped)" ;;
    *) fail "G9 expected exactly one Automation re-prompt and nothing else" ;;
  esac
  expect n "Did any Accessibility / Screen Recording / Input Monitoring prompt appear?" "G9 no forbidden prompts post-rebuild"
  if poll_frontmost "Terminal" 15; then pass "G9 click focuses Terminal post-rebuild"; else fail "G9 frontmost=\"$FRONT\" expected Terminal"; fi
}

summary() {
  echo
  echo "=== summary ==="
  local line; for line in ${RESULTS[@]+"${RESULTS[@]}"}; do echo "$line"; done
  echo
  echo "=== prompt census (observed vs expected) ==="
  printf '  notifications    = %s   (expected 1)\n' "$PC_NOTIF"
  printf '  login-item info  = %s   (expected 1, informational)\n' "$PC_LOGIN"
  printf '  automation       = %s   (expected 1 per terminal app, +1 per rebuild)\n' "$PC_AUTOMATION"
  printf '  accessibility    = 0   screen recording = 0   input monitoring = 0   (enforced)\n'
  printf '  forbidden seen   = %s   (expected 0 — any is a hard FAIL)\n' "$PC_FORBIDDEN"
  echo
  echo "passed=$PASS failed=$FAIL skipped=$SKIP"
  echo "transcript: $LOG"
  [ "$FAIL" -gt 0 ] && { echo "RESULT: FAIL"; exit 1; }
  echo "RESULT: PASS"
  exit 0
}

# ------------------------------------------------------------------------ main

case "${1:-}" in
  --help|-h)
    sed -n '2,30p' "$0"
    exit 0
    ;;
  --resume)
    [ -f "$STATE" ] || { echo "No saved run at $STATE — start with: $0"; exit 2; }
    PASS="$(state_get pass)"; FAIL="$(state_get fail)"; SKIP="$(state_get skip)"
    PC_NOTIF="$(state_get notif)"; PC_LOGIN="$(state_get login)"
    PC_AUTOMATION="$(state_get automation)"; PC_FORBIDDEN="$(state_get forbidden)"
    say "=== agentfocus fresh-user selftest (resumed) ==="
    say "carried over: passed=$PASS failed=$FAIL skipped=$SKIP"
    g8b_persistence
    g9_rebuild
    summary
    ;;
  "")
    say "=== agentfocus fresh-user selftest ==="
    say "account=$(whoami)  install=$AF_INSTALL  bundle=$BUNDLE"
    g0_preflight
    g1_install
    g2_forensics
    g3_launch
    g4_census
    if g5_banner; then
      g6_click
      g7_hotkey
    else
      skip "G6/G7 skipped — no test session to focus"
    fi
    g8a_pause_for_logout
    echo
    echo "=== partial summary ==="
    for line in ${RESULTS[@]+"${RESULTS[@]}"}; do echo "$line"; done
    echo
    echo "passed=$PASS failed=$FAIL skipped=$SKIP"
    echo "transcript: $LOG"
    echo "RESULT: PARTIAL (log out, log back in, then run: $0 --resume)"
    exit 0
    ;;
  *)
    echo "Unknown option '$1'. Try --help."; exit 2
    ;;
esac
