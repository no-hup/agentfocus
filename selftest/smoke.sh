#!/usr/bin/env bash
# Full control-plane smoke: register → notify → assert → sim-click → frontmost → tab
# Must run under the real Aqua GUI login session (not headless SSH).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
CLI="${ROOT}/stub/agentfocus"
SIM="${ROOT}/sim-click.sh"
ASSERT="${ROOT}/assert"

export PATH="$ASSERT:$PATH"

PASS=0
FAIL=0
RESULTS=()

record() {
  local status="$1" msg="$2"
  RESULTS+=("$status  $msg")
  if [ "$status" = "PASS" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
  fi
}

run_check() {
  local name="$1"
  shift
  local out rc
  set +e
  out="$("$@" 2>&1)"
  rc=$?
  set -e
  if [ $rc -eq 0 ]; then
    record "PASS" "$name — $out"
  else
    record "FAIL" "$name — $out"
  fi
  return 0
}

# --- detect surface for a realistic register ---
detect_app() {
  case "${TERM_PROGRAM:-}" in
    vscode) echo "vscode" ;;
    iTerm.app) echo "iterm" ;;
    Apple_Terminal) echo "terminal" ;;
    ghostty|Ghostty) echo "ghostty" ;;
    WarpTerminal) echo "terminal" ;;
    *)
      # Fall back: if inside tmux, label tmux; else guess from frontmost
      if [ -n "${TMUX:-}" ]; then
        echo "tmux"
        return
      fi
      local front
      front="$(lsappinfo info -only name "$(lsappinfo front)" 2>/dev/null | sed -E 's/.*="([^"]*)".*/\1/' || true)"
      case "$front" in
        Code|Code\ -\ Insiders) echo "vscode" ;;
        Cursor) echo "cursor" ;;
        iTerm2|iTerm) echo "iterm" ;;
        Ghostty) echo "ghostty" ;;
        Terminal) echo "terminal" ;;
        *) echo "terminal" ;;
      esac
      ;;
  esac
}

detect_hint() {
  local app="$1"
  case "$app" in
    tmux)
      if command -v tmux >/dev/null 2>&1 && [ -n "${TMUX:-}" ]; then
        tmux display-message -p '#{pane_id}' 2>/dev/null || echo "pane-unknown"
      else
        echo "pane-unknown"
      fi
      ;;
    *)
      # Prefer controlling tty when available
      if tty >/dev/null 2>&1; then
        tty 2>/dev/null | sed 's|^/dev/||' || echo "notty"
      else
        echo "notty"
      fi
      ;;
  esac
}

echo "=== agentfocus selftest smoke ==="
echo "root: $ROOT"
echo "aqua: $( [[ -n "${VIEW:-}" || -n "${DISPLAY:-}" || "$(uname)" = Darwin ]] && echo "darwin-assumed" )"
if [ -z "${SSH_CONNECTION:-}" ]; then
  echo "session: local (good — need GUI login session)"
else
  echo "WARN: SSH_CONNECTION set — frontmost/notification may fail without Aqua forwarding"
fi
echo

if [ ! -x "$CLI" ]; then
  chmod +x "$CLI" "$SIM" "$ASSERT"/*.sh 2>/dev/null || true
fi
chmod +x "$CLI" "$SIM" "$ASSERT"/*.sh

ID="smoke-$(uuidgen | tr '[:upper:]' '[:lower:]')"
APP="$(detect_app)"
HINT="$(detect_hint "$APP")"

echo "fixture: id=$ID app=$APP hint=$HINT"
echo

# 1. register
if "$CLI" register --id "$ID" --app "$APP" --hint "$HINT"; then
  record "PASS" "register"
else
  record "FAIL" "register"
fi

# 2. notify (real osascript banner)
if "$CLI" notify --id "$ID" --title "agentfocus-smoke" --body "selftest needs input ($ID)"; then
  record "PASS" "notify"
else
  record "FAIL" "notify"
fi

# 3. assert notify in JSONL
run_check "check_notify" "$ASSERT/check_notify.sh" "$ID"

# 4. sim-click (same path as future agentfocus:// handler)
if "$SIM" "$ID"; then
  record "PASS" "sim-click/focus"
else
  record "FAIL" "sim-click/focus"
fi

# 5. give macOS a beat to activate
sleep 0.7

# 6. frontmost app
run_check "check_frontmost" "$ASSERT/check_frontmost.sh" "$APP"

# 7. tab/pane / last-focus contract
run_check "check_tab" "$ASSERT/check_tab.sh" "$ID" --app "$APP" --hint "$HINT"

echo
echo "=== summary ==="
for line in "${RESULTS[@]}"; do
  echo "$line"
done
echo
echo "passed=$PASS failed=$FAIL id=$ID"
echo "events: $HOME/Library/Logs/agentfocus/events.jsonl"
echo "last-focus: /tmp/agentfocus-last-focus.json"
echo "registry: $HOME/Library/Application Support/agentfocus/registry/${ID}.json"

if [ "$FAIL" -gt 0 ]; then
  echo "RESULT: FAIL"
  exit 1
fi
echo "RESULT: PASS"
exit 0
