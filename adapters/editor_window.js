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
const { execFileSync } = require('child_process');

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

// Raising a window is the one destructive thing this tool does, so it lives here
// — the one module every caller already goes through — rather than in each of the
// two places that used to run `open` themselves.
//
// VS Code's main process buffers macOS open-file events on a 100ms SLIDING
// debounce (each new path clears and re-arms the timer), then hands the whole
// batch to windowsMainService.open(). That call merges a batch containing more
// than one folder into an untitled multi-root workspace:
//
//     if (!addMode && !removeMode && explicit) {
//         const folders = paths.filter(isFolder);
//         if (folders.length > 1) createUntitledWorkspace(folders)   // <-- here
//     }
//
// So two window raises landing within ~100ms of each other do not raise two
// windows: they DESTROY both, replacing them with one "Untitled (Workspace)".
// Verified on VS Code 1.136.1: two back-to-back `open -a` calls merged, the same
// two spaced 500ms apart did not. Nothing about this is VS Code-specific enough
// to be a bug in VS Code — an app is entitled to batch its open events — so the
// gap has to be enforced on our side.
//
// ponytail: 500ms is a 5x margin over the observed 100ms debounce, to cover
// Apple Event delivery jitter. Widen it if a future VS Code lengthens the
// debounce; the failure mode of too-small is a destroyed window layout.
const RAISE_GAP_MS = 500;

// Claim the right to raise, atomically and across PROCESSES — the colliding
// raises come from separate `agentfocus focus` invocations, so an in-process
// flag would never have seen them. mkdir is the atomic test-and-set, and its
// own mtime is the timestamp, so this is one syscall and no lockfile parsing.
// The claim is never released: it EXPIRES, which is what "no two raises within
// 500ms" actually means.
function claimRaise(gapMs = RAISE_GAP_MS, now = Date.now()) {
    const lock = path.join(process.env.HOME || '/tmp', '.cache/agentfocus/raise.lock');
    try { fs.mkdirSync(path.dirname(lock), { recursive: true }); } catch (e) { return true; }
    for (let attempt = 0; attempt < 2; attempt++) {
        try { fs.mkdirSync(lock); return true; }                  // won the claim
        catch (e) {
            if (e.code !== 'EEXIST') return true;                 // fail OPEN: a broken
            let age;                                              // lock must never cost
            try { age = now - fs.statSync(lock).mtimeMs; }        // you a focus
            catch (e2) { continue; }                              // vanished under us
            if (age < gapMs) return false;                        // someone just raised
            try { fs.rmdirSync(lock); } catch (e2) {}             // expired -> retake it
        }
    }
    return true;
}

// Raise `folder`'s window, unless another raise is still inside the merge window.
// Returns false when it declined, and the caller must then fall back to a plain
// app activate — which is safe at any rate, because `activate` opens no paths and
// so can never enter VS Code's batch.
function raiseWindow(editorApp, folder) {
    if (!claimRaise()) return false;
    execFileSync('open', ['-a', editorApp, folder]);
    return true;
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

module.exports = { openWindowFor, openFolders, raiseWindow, claimRaise, RAISE_GAP_MS };
