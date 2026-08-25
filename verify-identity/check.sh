#!/usr/bin/env bash
set -e

CACHE_DIR="$HOME/.cache/agentfocus"
NEWEST_JSON=$(ls -t "$CACHE_DIR"/env-probe-*.json 2>/dev/null | head -n 1 || true)

if [ -z "$NEWEST_JSON" ]; then
    echo "No probe JSON found in $CACHE_DIR. Run a Claude session first."
    exit 1
fi

echo "Reading newest probe data: $NEWEST_JSON"

node -e "
const fs = require('fs');
const data = JSON.parse(fs.readFileSync('$NEWEST_JSON', 'utf8'));
const env = data.env || {};

console.log('\n--- IDENTITY CHECK ---');
console.log('PID: ' + data.pid + ' | PPID: ' + data.ppid + ' | isTTY: ' + data.isTTY);

let found = false;

if (env.ITERM_SESSION_ID) {
    console.log('iTerm: ITERM_SESSION_ID=' + env.ITERM_SESSION_ID + ' ✓ (usable handle)');
    found = true;
} else if (env.TERM_PROGRAM === 'vscode' || Object.keys(env).some(k => k.startsWith('VSCODE_'))) {
    if (env.AGENT_VSCODE_IPC) {
        console.log('VS Code: AGENT_VSCODE_IPC=' + env.AGENT_VSCODE_IPC + ' ✓ (custom injected)');
        found = true;
    } else {
        console.log('VS Code: no native id found (needs extension injection) ✗');
        found = true; // Found terminal, just not ID
    }
} else if (env.TERM_PROGRAM === 'Ghostty' || Object.keys(env).some(k => k.startsWith('GHOSTTY_'))) {
    const gkeys = Object.keys(env).filter(k => k.startsWith('GHOSTTY_'));
    console.log('Ghostty: ' + gkeys.map(k => k + '=' + env[k]).join(', ') + ' ✓ (usable handle)');
    found = true;
} else if (env.TMUX && env.TMUX_PANE) {
    console.log('tmux: TMUX_PANE=' + env.TMUX_PANE + ' ✓ (usable handle)');
    found = true;
} else {
    console.log('Terminal: ' + (env.TERM_PROGRAM || 'Unknown') + ' ✗');
}

console.log('\nDumped Env subset:');
console.log(env);
"
