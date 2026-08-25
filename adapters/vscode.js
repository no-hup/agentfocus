const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const data = JSON.parse(process.argv[2]);

const cacheDir = path.join(process.env.HOME, '.cache/agentfocus');
fs.mkdirSync(cacheDir, { recursive: true });
const sigFile = path.join(cacheDir, 'focus-request.json');

// The companion extension watches this file and focuses the matching terminal.
fs.writeFileSync(sigFile, JSON.stringify({
    session_id: data.session_id,
    identity_handle: data.identity_handle,
    ts: Date.now()
}));

// Raise the right editor fork (Cursor/Windsurf/VSCodium/VS Code). editor_app is
// captured by emit.js from the VS Code env; validate it's a plain app name before
// use, else fall back to VS Code. execFileSync (no shell) so it can't be abused.
let app = data.editor_app;
if (!app || !/^[A-Za-z0-9 ._-]+$/.test(app)) app = 'Visual Studio Code';

try {
    execFileSync('osascript', ['-e', `tell application ${JSON.stringify(app)} to activate`]);
} catch (e) {
    console.error(e.message);
    process.exit(1);
}
