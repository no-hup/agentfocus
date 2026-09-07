// Which already-open editor window (if any) a session belongs to.
//
// `open -a <editor> <folder>` raises an existing window ONLY when <folder> is a
// folder that editor already has open. For anything else it SPAWNS a new window:
// macOS delivers an open-file event, VS Code's handler passes preferNewWindow,
// and its "is this already open?" lookup is a plain URI compare with no realpath.
// So a caller must never hand `open` a folder it hasn't confirmed — and the only
// honest source of that confirmation is the editor itself.
//
// The fork rewrites this file on every window blur, so it is freshest exactly
// when a banner click arrives (editor in the background). Read-only file read:
// no permissions, no AppleScript, no dependencies.

const fs = require('fs');
const path = require('path');

// Application Support dir ≠ .app name for VS Code itself. The forks (Cursor,
// Windsurf, VSCodium) do use their app name, so this map holds only exceptions.
const SUPPORT_DIR = {
    'Visual Studio Code': 'Code',
    'Visual Studio Code - Insiders': 'Code - Insiders',
};

const real = (p) => { try { return fs.realpathSync.native(p); } catch (e) { return p; } };
// Compare on resolved + lower-cased paths (macOS is case-insensitive, and the
// registry cwd can be /tmp where the editor recorded /private/tmp).
const key = (p) => real(p).toLowerCase();

// Folders the editor has open right now, keyed for comparison but VALUED with the
// editor's own path string — that string is what we hand back to `open`, so the
// editor's URI compare is guaranteed to match and cannot spawn a second window.
function openFolders(editorApp) {
    const dir = SUPPORT_DIR[editorApp] || editorApp;
    const file = path.join(process.env.HOME, 'Library/Application Support', dir,
                           'User/globalStorage/storage.json');
    const state = JSON.parse(fs.readFileSync(file, 'utf8')).windowsState || {};
    // openedWindows is only written when more than one window is open; a lone
    // window lives ONLY in lastActiveWindow. Read both, always. (A window holding
    // a .code-workspace has no `folder` — unverifiable, so it stays a miss.)
    const folders = new Map();
    for (const w of [...(state.openedWindows || []), state.lastActiveWindow]) {
        if (!w || typeof w.folder !== 'string' || !w.folder.startsWith('file://')) continue;
        const p = decodeURIComponent(w.folder.slice('file://'.length));
        folders.set(key(p), p);
    }
    return folders;
}

// Deepest open folder that is cwd or an ancestor of it, else null. Walking up
// covers the repo-root, git-worktree and open-a-subfolder cases in one rule, so
// callers need no `git rev-parse`.
function openWindowFor(editorApp, cwd) {
    if (!editorApp || !cwd) return null;
    let folders;
    try { folders = openFolders(editorApp); } catch (e) { return null; } // unknown fork / no state yet
    const stop = new Set([key(process.env.HOME || '/'), '/']);
    let p = real(cwd);
    for (let exact = true; ; exact = false) {
        // $HOME and / are ancestors of everything, so matching one is a guess at a
        // window rather than a location. An exact cwd match still counts.
        if (!exact && stop.has(p.toLowerCase())) return null;
        const hit = folders.get(p.toLowerCase());
        if (hit) return hit;
        const up = path.dirname(p);
        if (up === p) return null;
        p = up;
    }
}

// Self-check / debugging: `node editor_window.js "<App Name>" [cwd]` prints the
// folders that editor really has open, and what a session in cwd resolves to.
// selftest/editor-window.sh asserts against this against the live machine — a
// silently always-missing verifier would be a regression, not a safe default.
if (require.main === module) {
    const app = process.argv[2] || 'Visual Studio Code';
    let folders = new Map();
    try { folders = openFolders(app); }
    catch (e) { console.error(`no window state for "${app}": ${e.message}`); }
    for (const p of folders.values()) console.log(`open\t${p}`);
    if (process.argv[3]) console.log(`match\t${openWindowFor(app, process.argv[3]) || ''}`);
}

module.exports = { openWindowFor, openFolders };
