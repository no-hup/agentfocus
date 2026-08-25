#!/usr/bin/env bash
# Probe TCC-gated techniques by ATTEMPTING them. Best-effort granted? detection.
# Uses short timeouts so Automation permission sheets cannot hang an agent forever.
set -uo pipefail

printf "%-40s | %-28s | %-10s | %s\n" "technique" "needs" "granted?" "detail"
printf "%-40s-+-%-28s-+-%-10s-+-%s\n" \
  "----------------------------------------" \
  "----------------------------" \
  "----------" \
  "------"

row() {
  printf "%-40s | %-28s | %-10s | %s\n" "$1" "$2" "$3" "$4"
}

# run_timeout SECONDS COMMAND...  → sets RT_OUT, RT_ERR, RT_RC
run_timeout() {
  local secs="$1"
  shift
  local outf errf
  outf="$(mktemp)"
  errf="$(mktemp)"
  ( "$@" >"$outf" 2>"$errf" ) &
  local pid=$!
  ( sleep "$secs"; kill "$pid" 2>/dev/null ) &
  local watcher=$!
  wait "$pid" 2>/dev/null
  RT_RC=$?
  kill "$watcher" 2>/dev/null || true
  wait "$watcher" 2>/dev/null || true
  RT_OUT="$(cat "$outf" 2>/dev/null || true)"
  RT_ERR="$(cat "$errf" 2>/dev/null || true)"
  rm -f "$outf" "$errf"
  # If killed by signal, treat as timeout
  if [ "${RT_RC:-0}" -gt 128 ] 2>/dev/null; then
    RT_RC=124
    RT_ERR="${RT_ERR} timeout/killed after ${secs}s"
  fi
  return 0
}

# --- none: lsappinfo front ---
if FRONT="$(lsappinfo info -only name "$(lsappinfo front)" 2>/tmp/pd-lsapp.err)"; then
  NAME="$(echo "$FRONT" | sed -E 's/.*="([^"]*)".*/\1/')"
  row "lsappinfo front" "none" "yes" "frontmost=$NAME"
else
  row "lsappinfo front" "none" "no" "$(tr '\n' ' ' </tmp/pd-lsapp.err 2>/dev/null || echo fail)"
fi

# --- none: events.jsonl write ---
LOG_DIR="${HOME}/Library/Logs/agentfocus"
mkdir -p "$LOG_DIR" 2>/tmp/pd-log.err || true
if touch "${LOG_DIR}/.doctor-write" 2>/tmp/pd-log.err; then
  rm -f "${LOG_DIR}/.doctor-write"
  row "write ~/Library/Logs/agentfocus" "none" "yes" "ok"
else
  row "write ~/Library/Logs/agentfocus" "none" "no" "$(tr '\n' ' ' </tmp/pd-log.err)"
fi

# --- none: open -a ---
if open -a "Finder" 2>/tmp/pd-open.err; then
  row "open -a Finder" "none" "yes" "activated Finder"
else
  row "open -a Finder" "none" "no" "$(tr '\n' ' ' </tmp/pd-open.err)"
fi

# --- Notifications ---
run_timeout 5 osascript -e 'display notification "agentfocus perms-doctor" with title "agentfocus-doctor"'
if [ "${RT_RC:-1}" -eq 0 ]; then
  row "osascript display notification" "Notifications (per app)" "yes*" "posted; if no banner, check Notifications settings for osascript host"
elif [ "${RT_RC:-1}" -eq 124 ]; then
  row "osascript display notification" "Notifications (per app)" "no?" "timed out (permission sheet?)"
else
  row "osascript display notification" "Notifications (per app)" "no" "$(echo "$RT_ERR" | tr '\n' ' ')"
fi

# --- Automation: Terminal ---
run_timeout 4 osascript -e 'tell application "Terminal" to get name'
if [ "${RT_RC:-1}" -eq 0 ]; then
  row "AppleScript -> Terminal" "Automation (Terminal)" "yes" "name=$(echo "$RT_OUT" | tr '\n' ' ')"
elif [ "${RT_RC:-1}" -eq 124 ]; then
  row "AppleScript -> Terminal" "Automation (Terminal)" "no?" "timed out (likely Automation prompt)"
else
  ERR="$(echo "$RT_ERR" | tr '\n' ' ')"
  if echo "$ERR" | grep -Eqi 'not authorized|not allowed|1743|privilege'; then
    row "AppleScript -> Terminal" "Automation (Terminal)" "no" "$ERR"
  else
    row "AppleScript -> Terminal" "Automation (Terminal)" "no?" "$ERR"
  fi
fi

# --- Automation: iTerm ---
if [ -d /Applications/iTerm.app ] || [ -d /Applications/iTerm2.app ]; then
  run_timeout 4 osascript -e 'tell application "iTerm2" to get name'
  if [ "${RT_RC:-1}" -ne 0 ]; then
    run_timeout 4 osascript -e 'tell application "iTerm" to get name'
  fi
  if [ "${RT_RC:-1}" -eq 0 ]; then
    row "AppleScript -> iTerm(2)" "Automation (iTerm)" "yes" "ok"
  elif [ "${RT_RC:-1}" -eq 124 ]; then
    row "AppleScript -> iTerm(2)" "Automation (iTerm)" "no?" "timed out (likely Automation prompt)"
  else
    row "AppleScript -> iTerm(2)" "Automation (iTerm)" "no?" "$(echo "$RT_ERR" | tr '\n' ' ')"
  fi
else
  row "AppleScript -> iTerm(2)" "Automation (iTerm)" "n/a" "iTerm not installed"
fi

# --- Accessibility: System Events ---
run_timeout 4 osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true'
if [ "${RT_RC:-1}" -eq 0 ]; then
  row "System Events frontmost process" "Accessibility" "yes" "name=$(echo "$RT_OUT" | tr '\n' ' ')"
elif [ "${RT_RC:-1}" -eq 124 ]; then
  row "System Events frontmost process" "Accessibility" "no?" "timed out (likely Accessibility prompt)"
else
  ERR="$(echo "$RT_ERR" | tr '\n' ' ')"
  if echo "$ERR" | grep -Eqi 'not allowed|assistive|1002|25211|Accessibility'; then
    row "System Events frontmost process" "Accessibility" "no" "$ERR"
  else
    row "System Events frontmost process" "Accessibility" "no?" "$ERR"
  fi
fi

# --- Full Disk Access: NC db (bounded find) ---
DARWIN_USER_DIR="$(getconf DARWIN_USER_DIR 2>/dev/null || true)"
NC_HIT=""
if [ -n "$DARWIN_USER_DIR" ] && [ -d "$DARWIN_USER_DIR" ]; then
  NC_HIT="$(find "$DARWIN_USER_DIR" -path '*notificationcenter*' -name 'db' 2>/dev/null | head -n 1 || true)"
fi
if [ -z "$NC_HIT" ]; then
  # shallow only — avoid full Library walk
  for cand in \
    "${HOME}/Library/Application Support/NotificationCenter/db2/db" \
    "${HOME}/Library/Group Containers/group.com.apple.usernoted/db2/db"; do
    if [ -f "$cand" ]; then NC_HIT="$cand"; break; fi
  done
fi
if [ -n "$NC_HIT" ]; then
  run_timeout 3 sqlite3 "$NC_HIT" ".tables"
  if [ "${RT_RC:-1}" -eq 0 ]; then
    row "NC sqlite read" "Full Disk Access (often)" "yes*" "db=$NC_HIT"
  else
    row "NC sqlite read" "Full Disk Access (often)" "no" "$(echo "$RT_ERR" | tr '\n' ' ')"
  fi
else
  row "NC sqlite read" "Full Disk Access (often)" "n/a" "no NC db found at known paths"
fi

# --- tmux ---
if command -v tmux >/dev/null 2>&1; then
  if [ -n "${TMUX:-}" ]; then
    P="$(tmux display-message -p '#{pane_id}' 2>/tmp/pd-tmux.err || true)"
    if [ -n "$P" ]; then
      row "tmux display-message pane_id" "none" "yes" "pane_id=$P"
    else
      row "tmux display-message pane_id" "none" "no" "$(tr '\n' ' ' </tmp/pd-tmux.err 2>/dev/null)"
    fi
  else
    row "tmux display-message pane_id" "none" "n/a" "tmux installed but not inside a session"
  fi
else
  row "tmux display-message pane_id" "none" "n/a" "tmux not installed"
fi

# --- log show (can be slow; timeout) ---
run_timeout 8 log show --last 30s --style compact --predicate 'eventMessage CONTAINS "agentfocus"'
if [ "${RT_RC:-1}" -eq 0 ]; then
  LINES="$(echo "$RT_OUT" | wc -l | tr -d ' ')"
  row "log show (predicate)" "none / limited" "yes" "lines=$LINES"
elif [ "${RT_RC:-1}" -eq 124 ]; then
  row "log show (predicate)" "none / limited" "no?" "timed out"
else
  row "log show (predicate)" "none / limited" "no?" "$(echo "$RT_ERR" | tr '\n' ' ' | head -c 120)"
fi

echo
echo "Notes:"
echo "  yes*  = command succeeded; OS may still suppress UI (Focus mode / notification settings)."
echo "  no?   = failed for unclear reason (app missing, timeout, or TCC)."
echo "  n/a   = dependency not present; not a permission failure."
echo "  Run this in the GUI login session. Headless SSH will false-negative several rows."
echo "  AppleScript probes time out in ~4s if a TCC sheet is waiting for a human."
