#!/usr/bin/env bash
# Installer for AgentFocus.
# Merges hooks into ~/.claude/settings.json non-destructively.
# Usage:
#   ./install.sh          # install / reinstall
#   ./install.sh doctor   # host + install health checks (no changes)
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST_DIR="$HOME/.local/share/agentfocus"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"

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
    if [ -x "$DEST_DIR/bin/agentfocus" ]; then
        echo "--- installed CLI ---"
        "$DEST_DIR/bin/agentfocus" doctor || true
    else
        echo "CLI not installed yet at $DEST_DIR/bin/agentfocus"
        echo "Run: ./install.sh"
    fi
    exit 0
fi

BACKUP_FILE="$HOME/.claude/settings.json.agentfocus-backup-$(date +%s)"

echo "Installing AgentFocus to $DEST_DIR..."
# Copy contents into place (not the directory node) so re-runs do not nest
# DEST/hook/hook from BSD `cp -R src dest` when dest/hook already exists.
mkdir -p "$DEST_DIR/hook" "$DEST_DIR/bin" "$DEST_DIR/adapters"
cp -R "$SRC_DIR/hook/." "$DEST_DIR/hook/"
cp -R "$SRC_DIR/bin/." "$DEST_DIR/bin/"
cp -R "$SRC_DIR/adapters/." "$DEST_DIR/adapters/"

chmod +x "$DEST_DIR/bin/agentfocus"
chmod +x "$DEST_DIR/hook/emit.js"
chmod +x "$DEST_DIR/hook/clear-waiting.js"

echo "Updating Claude settings in $CLAUDE_SETTINGS..."
if [ -f "$CLAUDE_SETTINGS" ]; then
    cp "$CLAUDE_SETTINGS" "$BACKUP_FILE"
    echo "Backed up Claude settings to $BACKUP_FILE"
else
    mkdir -p "$HOME/.claude"
    echo "{}" > "$CLAUDE_SETTINGS"
fi

CLAUDE_SETTINGS="$CLAUDE_SETTINGS" \
EMIT_HOOK="$DEST_DIR/hook/emit.js" \
CLEAR_HOOK="$DEST_DIR/hook/clear-waiting.js" \
node -e '
const fs = require("fs");
const file = process.env.CLAUDE_SETTINGS;
const emitHookPath = process.env.EMIT_HOOK;
const clearHookPath = process.env.CLEAR_HOOK;

let data = JSON.parse(fs.readFileSync(file, "utf8"));
if (!data.hooks) data.hooks = {};

["Stop", "Notification", "UserPromptSubmit"].forEach(evt => {
    if (!data.hooks[evt]) data.hooks[evt] = [];
});

function removeOurHooks(arr) {
    for (let i = arr.length - 1; i >= 0; i--) {
        if (arr[i].hooks) {
            arr[i].hooks = arr[i].hooks.filter(h =>
                h.type !== "command" ||
                h.command !== "node" ||
                (h.args && h.args[0] && !String(h.args[0]).includes("agentfocus"))
            );
            if (arr[i].hooks.length === 0) arr.splice(i, 1);
        }
    }
}

removeOurHooks(data.hooks.Stop);
removeOurHooks(data.hooks.Notification);
removeOurHooks(data.hooks.UserPromptSubmit);

const emitDef = { hooks: [{ type: "command", command: "node", args: [emitHookPath] }] };
data.hooks.Stop.push(emitDef);
data.hooks.Notification.push(emitDef);

const clearDef = { hooks: [{ type: "command", command: "node", args: [clearHookPath] }] };
data.hooks.UserPromptSubmit.push(clearDef);

fs.writeFileSync(file, JSON.stringify(data, null, 2));
console.log("Installed hooks successfully!");
'

echo ""
echo "Done."
echo "  CLI:  $DEST_DIR/bin/agentfocus"
if ! command -v agentfocus >/dev/null 2>&1; then
    echo "  PATH: add this line to your shell rc if you want \`agentfocus\` on PATH:"
    echo "        export PATH=\"\$HOME/.local/share/agentfocus/bin:\$PATH\""
fi
echo "  Next: ./install.sh doctor"
