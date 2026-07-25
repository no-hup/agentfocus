#!/usr/bin/env bash
# Installer for AgentFocus
# Merges the hooks into ~/.claude/settings.json NON-DESTRUCTIVELY.
# Includes a doctor subcommand.

set -euo pipefail

APP_NAME="agentfocus"
LOCAL_SHARE="$HOME/.local/share/$APP_NAME"

if [ "${1:-}" = "doctor" ]; then
    echo "=== AgentFocus Doctor ==="
    echo "Checking host support..."
    echo "You must manually ensure your terminal has macOS Notification permissions."
    echo ""
    echo "Per-Terminal Setup:"
    echo "- iTerm2: Go to Settings -> Advanced -> Search 'OSC' -> Enable 'Terminal may set window title' and 'Accept OSC 9 notifications'"
    echo "- tmux: Ensure 'set -g allow-passthrough on' is in your ~/.tmux.conf"
    echo "- VS Code: Install the optional extension in vscode-ext/ or use wenbopan's OSC notifier."
    echo "- Terminal.app: Will prompt for AppleEvent Automation permission on first run."
    exit 0
fi

mkdir -p "$LOCAL_SHARE"
HOOK_SCRIPT="$LOCAL_SHARE/emit.js"
cp "$(pwd)/hook/emit.js" "$HOOK_SCRIPT"
chmod +x "$HOOK_SCRIPT"

SETTINGS_FILE="$HOME/.claude/settings.json"

if [ ! -f "$SETTINGS_FILE" ]; then
    echo "Creating new settings file at $SETTINGS_FILE"
    mkdir -p "$(dirname "$SETTINGS_FILE")"
    echo "{}" > "$SETTINGS_FILE"
fi

BAK_FILE="${SETTINGS_FILE}.bak.$(date +%s)"
cp "$SETTINGS_FILE" "$BAK_FILE"

TEMP_SCRIPT=$(mktemp)
cat << 'EOF' > "$TEMP_SCRIPT"
const fs = require('fs');
const file = process.argv[2];
const hookPath = process.argv[3];

let data;
try {
    data = JSON.parse(fs.readFileSync(file, 'utf8'));
} catch (e) {
    console.error("Failed to parse settings JSON. Ensure it is valid JSON (no comments).", e);
    process.exit(1);
}

if (!data.hooks) data.hooks = {};
const events = ['Notification', 'Stop'];

for (const ev of events) {
    if (!data.hooks[ev]) data.hooks[ev] = [];
    
    let found = false;
    for (const group of data.hooks[ev]) {
        if (group.hooks) {
            for (const hook of group.hooks) {
                if (hook.type === 'command' && hook.command === 'node' && hook.args && hook.args.includes(hookPath)) {
                    found = true;
                }
            }
        }
    }
    
    if (!found) {
        data.hooks[ev].push({
            hooks: [{
                type: 'command',
                command: 'node',
                args: [hookPath]
            }]
        });
    }
}
fs.writeFileSync(file, JSON.stringify(data, null, 2));
EOF

node "$TEMP_SCRIPT" "$SETTINGS_FILE" "$HOOK_SCRIPT"
rm -f "$TEMP_SCRIPT"

echo "Installed successfully! Backed up original to $BAK_FILE"
echo "Run './install.sh doctor' for terminal setup instructions."
