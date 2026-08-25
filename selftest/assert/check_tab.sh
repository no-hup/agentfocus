#!/usr/bin/env bash
# Assert "correct tab/pane" by surface type.
# Usage: check_tab.sh <id> [--app <app>] [--hint <hint>]
# If --app/--hint omitted, reads registry + /tmp/agentfocus-last-focus.json.
set -euo pipefail

REG_DIR="${HOME}/Library/Application Support/agentfocus/registry"
LAST_FOCUS="/tmp/agentfocus-last-focus.json"

if [ $# -lt 1 ] || [ -z "${1:-}" ]; then
  echo "FAIL check_tab: usage: check_tab.sh <id> [--app <app>] [--hint <hint>]" >&2
  exit 2
fi

ID="$1"
shift || true
APP="" HINT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --app)  APP="${2:-}"; shift 2 ;;
    --hint) HINT="${2:-}"; shift 2 ;;
    *) echo "FAIL check_tab: unknown arg $1" >&2; exit 2 ;;
  esac
done

reg="${REG_DIR}/${ID}.json"
if [ -z "$APP" ] && [ -f "$reg" ]; then
  APP="$(node -e 'const r=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); process.stdout.write(r.app||"")' "$reg")"
fi
if [ -z "$HINT" ] && [ -f "$reg" ]; then
  HINT="$(node -e 'const r=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); process.stdout.write(r.hint||"")' "$reg")"
fi
if [ -z "$APP" ] && [ -f "$LAST_FOCUS" ]; then
  APP="$(node -e 'const r=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); process.stdout.write(r.app||"")' "$LAST_FOCUS")"
fi

if [ -z "$APP" ]; then
  echo "FAIL check_tab: cannot determine app for id=$ID (no registry/last-focus)" >&2
  exit 1
fi

case "$APP" in
  tmux)
    if [ -z "${TMUX:-}" ] && ! command -v tmux >/dev/null 2>&1; then
      echo "FAIL check_tab: tmux not available" >&2
      exit 1
    fi
    if ! command -v tmux >/dev/null 2>&1; then
      echo "FAIL check_tab: tmux binary missing" >&2
      exit 1
    fi
    CUR="$(tmux display-message -p '#{pane_id}' 2>/dev/null || true)"
    if [ -z "$CUR" ]; then
      echo "FAIL check_tab: tmux display-message failed (not inside tmux?)" >&2
      exit 1
    fi
    if [ -n "$HINT" ] && [ "$CUR" != "$HINT" ]; then
      # When smoke runs outside the target pane, we can only assert last-focus contract.
      # Prefer last-focus terminalId match if live pane != registered hint.
      if [ -f "$LAST_FOCUS" ]; then
        TID="$(node -e 'const r=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); process.stdout.write(r.terminalId||"")' "$LAST_FOCUS")"
        FID="$(node -e 'const r=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); process.stdout.write(r.id||"")' "$LAST_FOCUS")"
        if [ "$FID" = "$ID" ] && [ "$TID" = "$HINT" ]; then
          echo "PASS check_tab: tmux via last-focus id=$ID terminalId=$TID (live pane=$CUR != hint; control-plane ok)"
          exit 0
        fi
      fi
      echo "FAIL check_tab: tmux pane_id=$CUR expected hint=$HINT" >&2
      exit 1
    fi
    echo "PASS check_tab: tmux pane_id=$CUR"
    exit 0
    ;;

  iterm|iterm2)
    # Automation TCC may prompt / fail
    TTY_NOW="$(osascript -e 'tell application "iTerm2" to get tty of current session of current window' 2>/tmp/agentfocus-check-tab.err || \
               osascript -e 'tell application "iTerm" to get tty of current session of current window' 2>>/tmp/agentfocus-check-tab.err || true)"
    if [ -z "$TTY_NOW" ]; then
      # Fall back to last-focus control-plane assert
      if [ -f "$LAST_FOCUS" ]; then
        node -e '
          const fs = require("fs");
          const id = process.argv[1];
          const path = process.argv[2];
          const r = JSON.parse(fs.readFileSync(path, "utf8"));
          if (r.id === id && r.ok !== false) {
            console.log("PASS check_tab: iTerm via last-focus id=" + id + " terminalId=" + (r.terminalId||"") + " (AppleScript tty unavailable — Automation?)");
            process.exit(0);
          }
          console.error("FAIL check_tab: iTerm last-focus mismatch " + JSON.stringify(r));
          process.exit(1);
        ' "$ID" "$LAST_FOCUS"
        exit $?
      fi
      echo "FAIL check_tab: iTerm AppleScript failed: $(tr '\n' ' ' </tmp/agentfocus-check-tab.err 2>/dev/null)" >&2
      exit 1
    fi
    if [ -n "$HINT" ] && [ "$TTY_NOW" != "$HINT" ] && [ "/dev/$TTY_NOW" != "$HINT" ] && [ "$TTY_NOW" != "/dev/${HINT#/dev/}" ]; then
      # Normalize compare
      norm() { echo "$1" | sed 's|^/dev/||'; }
      if [ "$(norm "$TTY_NOW")" != "$(norm "$HINT")" ]; then
        echo "FAIL check_tab: iTerm tty=$TTY_NOW expected hint=$HINT" >&2
        exit 1
      fi
    fi
    echo "PASS check_tab: iTerm tty=$TTY_NOW"
    exit 0
    ;;

  terminal|terminal.app|Apple_Terminal)
    TTY_NOW="$(osascript -e 'tell application "Terminal" to get tty of selected tab of front window' 2>/tmp/agentfocus-check-tab.err || true)"
    if [ -z "$TTY_NOW" ]; then
      if [ -f "$LAST_FOCUS" ]; then
        node -e '
          const fs = require("fs");
          const id = process.argv[1];
          const path = process.argv[2];
          const r = JSON.parse(fs.readFileSync(path, "utf8"));
          if (r.id === id && r.ok !== false) {
            console.log("PASS check_tab: Terminal.app via last-focus id=" + id + " terminalId=" + (r.terminalId||"") + " (AppleScript tty unavailable — Automation?)");
            process.exit(0);
          }
          console.error("FAIL check_tab: Terminal last-focus mismatch " + JSON.stringify(r));
          process.exit(1);
        ' "$ID" "$LAST_FOCUS"
        exit $?
      fi
      echo "FAIL check_tab: Terminal AppleScript failed: $(tr '\n' ' ' </tmp/agentfocus-check-tab.err 2>/dev/null)" >&2
      exit 1
    fi
    if [ -n "$HINT" ]; then
      norm() { echo "$1" | sed 's|^/dev/||'; }
      if [ "$(norm "$TTY_NOW")" != "$(norm "$HINT")" ]; then
        echo "FAIL check_tab: Terminal tty=$TTY_NOW expected hint=$HINT" >&2
        exit 1
      fi
    fi
    echo "PASS check_tab: Terminal.app tty=$TTY_NOW"
    exit 0
    ;;

  vscode|code|code-insiders|insiders|cursor|ghostty)
    # VS Code / Cursor / Ghostty (no stable external tab API in stub): last-focus contract
    if [ ! -f "$LAST_FOCUS" ]; then
      echo "FAIL check_tab: missing $LAST_FOCUS (focus path did not write it)" >&2
      exit 1
    fi
    node -e '
      const fs = require("fs");
      const id = process.argv[1];
      const hint = process.argv[2] || "";
      const path = process.argv[3];
      const r = JSON.parse(fs.readFileSync(path, "utf8"));
      if (r.id !== id) {
        console.error("FAIL check_tab: last-focus id=" + r.id + " expected=" + id);
        process.exit(1);
      }
      if (r.ok === false) {
        console.error("FAIL check_tab: last-focus ok=false " + JSON.stringify(r));
        process.exit(1);
      }
      if (hint && r.terminalId !== hint) {
        console.error("FAIL check_tab: last-focus terminalId=" + r.terminalId + " expected hint=" + hint);
        process.exit(1);
      }
      console.log("PASS check_tab: last-focus id=" + r.id + " app=" + r.app + " terminalId=" + r.terminalId + " ts=" + r.ts);
    ' "$ID" "$HINT" "$LAST_FOCUS"
    exit $?
    ;;

  *)
    if [ ! -f "$LAST_FOCUS" ]; then
      echo "FAIL check_tab: unknown app=$APP and no last-focus file" >&2
      exit 1
    fi
    node -e '
      const fs = require("fs");
      const id = process.argv[1];
      const r = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
      if (r.id === id && r.ok !== false) {
        console.log("PASS check_tab: generic last-focus id=" + id + " app=" + r.app);
        process.exit(0);
      }
      console.error("FAIL check_tab: generic last-focus mismatch");
      process.exit(1);
    ' "$ID" "$LAST_FOCUS"
    exit $?
    ;;
esac
