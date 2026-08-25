#!/usr/bin/env bash
set -e

SETTINGS_FILE="$HOME/.claude/settings.json"
BACKUP_FILE="$HOME/.claude/settings.json.backup-$(date +%s)"
HOOK_PATH="$(pwd)/env-dump-hook.js"

mkdir -p "$HOME/.claude"

# Ensure the hook is executable
chmod +x "$HOOK_PATH"

if [ -f "$SETTINGS_FILE" ]; then
    cp "$SETTINGS_FILE" "$BACKUP_FILE"
    echo "Backed up settings to $BACKUP_FILE"
else
    echo "{}" > "$SETTINGS_FILE"
fi

# Use node to inject the hook non-destructively
node -e "
const fs = require('fs');
const file = '$SETTINGS_FILE';
const hookPath = '$HOOK_PATH';
let data = JSON.parse(fs.readFileSync(file, 'utf8'));

if (!data.hooks) data.hooks = [];

// Avoid duplicates
const exists = data.hooks.find(h => h.events.includes('Stop') && h.command === hookPath);
if (!exists) {
    data.hooks.push({
        events: ['Stop'],
        command: hookPath
    });
    fs.writeFileSync(file, JSON.stringify(data, null, 2));
    console.log('Hook installed successfully.');
} else {
    console.log('Hook already installed.');
}
"
