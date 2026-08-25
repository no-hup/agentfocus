#!/usr/bin/env bash
set -e

SETTINGS_FILE="$HOME/.claude/settings.json"
HOOK_PATH="$(pwd)/env-dump-hook.js"

if [ ! -f "$SETTINGS_FILE" ]; then
    echo "No settings.json found."
    exit 0
fi

node -e "
const fs = require('fs');
const file = '$SETTINGS_FILE';
const hookPath = '$HOOK_PATH';
let data = JSON.parse(fs.readFileSync(file, 'utf8'));

if (data.hooks) {
    const origLen = data.hooks.length;
    data.hooks = data.hooks.filter(h => !(h.events && h.events.includes('Stop') && h.command === hookPath));
    if (data.hooks.length < origLen) {
        fs.writeFileSync(file, JSON.stringify(data, null, 2));
        console.log('Hook uninstalled successfully.');
    } else {
        console.log('Hook not found in settings.');
    }
} else {
    console.log('No hooks defined in settings.');
}
"
