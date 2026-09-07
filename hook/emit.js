#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const { execSync, execFileSync } = require('child_process');

// The hook is detached (no controlling tty), but its parent (claude/shell)
// still holds the terminal's controlling tty. Walk the ancestor PID chain to
// recover it — a first-class, reliable disambiguation key for Terminal.app/iTerm.
function ancestorTty() {
    let pid = process.pid;
    for (let i = 0; i < 12 && pid > 1; i++) {
        let out;
        try { out = execSync(`ps -p ${pid} -o ppid=,tty=`, { encoding: 'utf8' }).trim(); }
        catch { break; }
        const p = out.split(/\s+/);
        const ppid = parseInt(p[0], 10);
        const tty = p[1];
        if (tty && tty !== '??' && tty !== '?') return '/dev/' + tty;
        if (!ppid) break;
        pid = ppid;
    }
    return null;
}

let input = '';
process.stdin.on('data', chunk => { input += chunk; });
process.stdin.on('end', () => {
    let payload = {};
    try {
        if (input.trim()) payload = JSON.parse(input);
    } catch(e) {}

    const sessionId = payload.session_id;
    if (!sessionId || !/^[a-zA-Z0-9_-]+$/.test(sessionId)) {
        return;
    }

    const termProgram = process.env.TERM_PROGRAM || process.env.LC_TERMINAL || 'unknown';
    const ghosttyKey = Object.keys(process.env).find(k => k.startsWith('GHOSTTY_'));
    const identityHandle = process.env.AGENTFOCUS_VSCODE_ID ||  // injected by our VS Code ext (must match extension's ENV_KEY)
                           process.env.ITERM_SESSION_ID ||
                           process.env.KITTY_WINDOW_ID ||
                           process.env.WEZTERM_PANE ||
                           process.env.TERM_SESSION_ID ||
                           process.env.TMUX_PANE ||
                           (ghosttyKey ? process.env[ghosttyKey] : null) ||
                           'unknown';

    const registryDir = path.join(process.env.HOME, '.local/share/agentfocus/registry');
    fs.mkdirSync(registryDir, { recursive: true });

    const registryPath = path.join(registryDir, `${sessionId}.json`);
    // Guard against traversal
    if (!registryPath.startsWith(registryDir)) {
        process.exit(1);
    }

    const cwd = payload.cwd || process.cwd();
    const title = path.basename(cwd) || 'agent';

    // Previous row, best-effort: a Stop woken by a finished background agent can
    // only NAME that agent by diffing against the last Stop's list. Missing or
    // corrupt is the normal first-event case, not an error.
    let prev = null;
    try { prev = JSON.parse(fs.readFileSync(registryPath, 'utf8')); } catch(e) {}

    // Banner text. A Stop with background work still in flight must not read as
    // a plain "done", and the Stop that a finishing background agent wakes must
    // say which one. Sanitised and length-capped once, here, for all consumers.
    // ponytail: `bg` is rewritten on EVERY emit, so one finish is announced at
    // most once; the freshness gate stops an abandoned row announcing stale news.
    const FRESH_BG_MS = 30 * 60 * 1000;
    const clean = (s) => String(s == null ? '' : s).replace(/[;\x00-\x1F]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 120);
    // Statuses are running|pending|completed|failed|killed; only the first two
    // are outstanding. Absent on older Claude Code → empty → plain "needs input".
    const bg = (payload.background_tasks || [])
        .filter(t => t.status === 'running' || t.status === 'pending')
        .map(t => ({ id: t.id, description: clean(t.description) || 'background task' }));

    function reasonFor() {
        if (payload.hook_event_name === 'Stop') {
            const live = new Set(bg.map(t => t.id));
            const fresh = prev && (Date.now() - (prev.ts || 0)) < FRESH_BG_MS;
            const done = (fresh && Array.isArray(prev.bg)) ? prev.bg.filter(t => !live.has(t.id)) : [];
            if (done.length) {
                return `Background agent finished: ${done[0].description}` +
                       (done.length > 1 ? ` (+${done.length - 1} more)` : '') +
                       (bg.length ? ` (+${bg.length} still running)` : '');
            }
            if (bg.length) {
                const names = bg.map(t => t.description);
                const inline = bg.length <= 2 && names.every(n => n.length <= 40);
                return `done — ${bg.length} background task${bg.length > 1 ? 's' : ''} running` +
                       (inline ? `: ${names.join(', ')}` : '');
            }
        }
        return payload.message || "needs input";
    }
    const message = clean(reasonFor());

    // Which editor app to raise (VS Code / Cursor / Windsurf / VSCodium). VS Code
    // family exports its bundle path in VSCODE_* vars; pull the .app name so the
    // adapter activates the RIGHT fork instead of always "Visual Studio Code".
    let editorApp = null;
    for (const [k, v] of Object.entries(process.env)) {
        if (k.startsWith('VSCODE_') && typeof v === 'string') {
            const m = v.match(/\/([^/]+)\.app\//);
            if (m) { editorApp = m[1]; break; }
        }
    }

    // Native OSC or osascript? A terminal that renders no OSC 9/777 must never be
    // marked osc_native on the strength of an env var alone: launch VS Code from a
    // Ghostty shell and every session inside it inherits GHOSTTY_*, which would
    // silence the helper while the editor renders nothing — no banner, no error
    // anywhere. Editor-hosted sessions with no TERM_PROGRAM (the VS Code panel)
    // are the same case: their output reaches no terminal emulator at all.
    const term = termProgram.toLowerCase();
    const noOsc = term === 'vscode' || term === 'apple_terminal' || (term === 'unknown' && !!editorApp);
    const isOscNative = !noOsc &&
        (['ghostty', 'iterm.app', 'wezterm', 'kitty'].includes(term) ||   // lower-cased: Ghostty reports "ghostty"
         !!(process.env.ITERM_SESSION_ID || ghosttyKey || process.env.KITTY_WINDOW_ID || process.env.WEZTERM_PANE));

    const data = {
        session_id: sessionId,
        term_program: termProgram,
        osc_native: !!isOscNative,
        identity_handle: identityHandle,
        editor_app: editorApp,
        tty: ancestorTty(), // recovered from parent claude/shell — see ancestorTty()
        cwd: cwd,
        title: title,
        reason: message,   // banner body — the helper posts this verbatim
        bg: bg,            // in-flight background tasks, diffed by the next Stop
        waiting: true,
        ts: Date.now()
    };

    // 0600 create/write
    const fd = fs.openSync(registryPath, 'w');
    fs.fchmodSync(fd, 0o600);
    fs.writeSync(fd, JSON.stringify(data, null, 2));
    fs.closeSync(fd);

    // Nothing ever deleted a row, so the registry only grew: the helper re-reads
    // every one of them every 2s and the CLI parses them on every focus-next.
    // Rows are already invisible to both at 6h; 7 days is a wide margin, and
    // mtime means nothing has to be parsed to decide. A live session that has
    // been silent that long simply rewrites its row on the next event.
    try {
        const cutoff = Date.now() - 7 * 24 * 60 * 60 * 1000;
        for (const f of fs.readdirSync(registryDir)) {
            if (!f.endsWith('.json')) continue;
            const p = path.join(registryDir, f);
            try { if (fs.statSync(p).mtimeMs < cutoff) fs.unlinkSync(p); } catch(e) {}
        }
    } catch(e) {}

    // Keep the helper alive (menu-bar queue + hotkey + UN banners). `open -g`
    // is idempotent and never steals focus; registry-write-then-launch means
    // the helper's startup scan catches this very session.
    const HELPER_APP = path.join(process.env.HOME, 'Applications/AgentFocus.app');
    let helperOk = false;
    try {
        execFileSync('open', ['-g', HELPER_APP], { stdio: 'ignore' });
        helperOk = true;
    } catch(e) {}

    if (isOscNative) {
        // Claude emits the returned terminalSequence
        // Sanitize body and title for OSC (remove controls and semicolons)
        const safeTitle = title.replace(/[;\x00-\x1F]/g, '');
        const safeBody = message.replace(/[;\x00-\x1F]/g, ' ');
        const osc9 = `\x1b]9;agentfocus: ${safeTitle}: ${safeBody}\x07`;
        const osc777 = `\x1b]777;notify;agentfocus: ${safeTitle};${safeBody}\x07`;
        // Also emit OSC 0 to set the terminal title as an extra anchor
        const osc0 = `\x1b]0;agentfocus-${sessionId}\x07`;
        console.log(JSON.stringify({ terminalSequence: osc777 + osc9 + osc0 }));
    } else {
        // Non-OSC terminals: the helper posts the UN banner (it watches the
        // registry). osascript is the dead-click fallback only when the helper
        // app is missing entirely.
        if (!helperOk) {
            const asLit = (s) => '"' + String(s).slice(0, 200).replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/[\x00-\x1F]/g, ' ') + '"';
            try {
                execFileSync('osascript', ['-e', `display notification ${asLit(message)} with title ${asLit('agentfocus: ' + title)}`], { stdio: 'ignore' });
            } catch(e) {}
        }
        // Title-anchor so the Terminal.app adapter can find THIS exact tab.
        // Terminal.app honors OSC 0 (title) even though it ignores OSC 9/777.
        console.log(JSON.stringify({ terminalSequence: `\x1b]0;agentfocus-${sessionId}\x07` }));
    }
});
