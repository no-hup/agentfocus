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

// activate is app-level: with several windows open macOS restores whichever was
// frontmost last, which is routinely NOT the window this agent runs in — and the
// extension's terminal.show() can't raise a window from the background. So raise
// the specific one, but only when the editor's own state confirms it has this
// session's folder open (deepest ancestor, never $HOME or / — editor_window.js).
// On any doubt we keep the activate-only behaviour: a wrong raise is worse.
let folder = null;
try {
    folder = require('./editor_window.js').openWindowFor(app, data.cwd);
    if (folder) execFileSync('open', ['-a', app, folder]);
} catch (e) { folder = null; }

// Say which of the two we actually did, as the FIRST token, so bin/agentfocus
// stops recording an activate-only click as a clean hit (BUGS #3). Never 'miss':
// the app IS frontmost now, and a miss would keep the session waiting behind a
// banner that no click can ever clear.
process.stdout.write(folder ? `hit window-level ${folder}` : 'degraded activate-only');
