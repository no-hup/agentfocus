#!/usr/bin/env bash
# Exit 0 if frontmost app matches expected logical app (or raw name).
# Usage: check_frontmost.sh <expected-app>
#   expected-app: vscode|code|cursor|iterm|ghostty|terminal|tmux|<raw lsappinfo name>
set -euo pipefail

if [ $# -lt 1 ] || [ -z "${1:-}" ]; then
  echo "FAIL check_frontmost: usage: check_frontmost.sh <expected-app>" >&2
  exit 2
fi
EXPECTED_RAW="$1"

front_name() {
  # lsappinfo prints: name="Code"  or similar
  local raw
  raw="$(lsappinfo info -only name "$(lsappinfo front)" 2>/dev/null || true)"
  if [ -z "$raw" ]; then
    echo ""
    return
  fi
  # Extract value between quotes
  echo "$raw" | sed -E 's/.*="([^"]*)".*/\1/' | tr -d '\r'
}

# Map logical app -> space-separated acceptable frontmost names
accept_list() {
  case "$1" in
    vscode|code)
      echo "Code Visual Studio Code Code - Insiders"
      ;;
    code-insiders|insiders)
      echo "Code - Insiders Code"
      ;;
    cursor)
      echo "Cursor"
      ;;
    iterm|iterm2)
      echo "iTerm2 iTerm"
      ;;
    ghostty)
      echo "Ghostty"
      ;;
    terminal|terminal.app|Apple_Terminal)
      echo "Terminal"
      ;;
    tmux)
      # tmux lives inside a host terminal
      echo "Terminal iTerm2 iTerm Ghostty Code Cursor"
      ;;
    *)
      # Treat as literal frontmost name
      echo "$1"
      ;;
  esac
}

FRONT="$(front_name)"
if [ -z "$FRONT" ]; then
  echo "FAIL check_frontmost: could not read frontmost app via lsappinfo (no Aqua session?)" >&2
  exit 1
fi

OK=0
for cand in $(accept_list "$EXPECTED_RAW"); do
  if [ "$FRONT" = "$cand" ]; then
    OK=1
    break
  fi
done

# Also accept case-insensitive exact match to raw expected
if [ "$OK" -eq 0 ]; then
  fl="$(echo "$FRONT" | tr '[:upper:]' '[:lower:]')"
  el="$(echo "$EXPECTED_RAW" | tr '[:upper:]' '[:lower:]')"
  if [ "$fl" = "$el" ]; then
    OK=1
  fi
fi

if [ "$OK" -eq 1 ]; then
  echo "PASS check_frontmost: frontmost=\"$FRONT\" matches expected=\"$EXPECTED_RAW\""
  exit 0
fi

echo "FAIL check_frontmost: frontmost=\"$FRONT\" does not match expected=\"$EXPECTED_RAW\" (accept: $(accept_list "$EXPECTED_RAW"))" >&2
exit 1
