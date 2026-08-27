#!/usr/bin/env bash
# Dev installer for AgentFocus. Thin wrapper: `agentfocus init` does the work
# (builds the helper into ~/Applications, copies the runtime into
# ~/.local/share/agentfocus, merges hooks into ~/.claude/settings.json
# non-destructively). Brew users get the same path via `agentfocus init`.
# Usage:
#   ./install.sh          # install / reinstall
#   ./install.sh doctor   # host + install health checks (no changes)
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ "${1:-}" = "doctor" ]; then
    echo "=== AgentFocus Doctor (setup guide) ==="
    echo ""
    echo "Per-terminal setup:"
    echo "  - iTerm2: Settings → Advanced → search 'OSC' → enable OSC 9 notifications"
    echo "  - tmux: add  set -g allow-passthrough on  to ~/.tmux.conf"
    echo "  - VS Code / Cursor / Windsurf: install vscode-ext/ (or wenbopan OSC notifier)"
    echo "  - Terminal.app: Automation prompt on first focus (AppleScript)"
    echo "  - Ghostty / WezTerm / kitty: native OSC notify; click focuses that terminal's tab"
    echo ""
    echo "Hotkey: opt+cmd+A (built into the AgentFocus helper app — see helper/)"
    echo ""
    exec "$SRC_DIR/bin/agentfocus" doctor
fi

exec "$SRC_DIR/bin/agentfocus" init
