// Shared plumbing for non-Claude agent shims.
//
// hook/emit.js is frozen: it reads a Claude-Code-shaped payload on stdin and
// PRINTS {"terminalSequence": "<OSC>"} on stdout, expecting Claude Code to write
// that sequence to the terminal. No other agent honours that contract, so we do
// it here: run emit.js, then write the sequence to the tty emit.js recorded in
// the registry file it just wrote.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { execFileSync } = require('child_process');

const HOOK = (f) => path.join(__dirname, '..', 'hook', f);

// Hosts differ: shell hooks run us under node, but the OpenCode plugin runs
// inside opencode's own bun binary, where process.execPath is `opencode` —
// spawning that with a script path would be nonsense. Reuse execPath only when
// it really is node, else fall back to PATH.
const NODE = /^node/.test(path.basename(process.execPath)) ? process.execPath : 'node';
const registryPath = (sid) =>
    path.join(process.env.HOME, '.local/share/agentfocus/registry', `${sid}.json`);

// Stable, emit.js-safe session id. Tool prefix keeps non-Claude sessions from
// colliding with Claude's own registry entries. notify() and clear() MUST agree.
function sid(tool, id) {
    const raw = id == null ? '' : String(id);
    if (raw) return `${tool}-${raw.replace(/[^A-Za-z0-9_-]/g, '-')}`;
    // No id from the tool: hash the cwd so the same terminal keeps one entry.
    return `${tool}-${crypto.createHash('sha256').update(tool + process.cwd()).digest('hex').slice(0, 16)}`;
}

// Never throws into the host: a shell hook that exits non-zero can block the
// agent, and an exception inside the OpenCode plugin lands in its event loop.
// A missed notification is the acceptable failure mode here.
function run(hook, payload) {
    try {
        return execFileSync(NODE, [HOOK(hook)], {
            input: JSON.stringify(payload),
            encoding: 'utf8',
            stdio: ['pipe', 'pipe', 'ignore'],
        });
    } catch (e) { return ''; }
}

function notify({ tool, id, cwd, message }) {
    const session_id = sid(tool, id);
    const out = run('emit.js', {
        session_id,
        cwd: cwd || process.cwd(),
        message: String(message || 'needs input').slice(0, 120),
    });
    // Flush the OSC ourselves. No tty / unwritable tty is not an error: the
    // helper app watches the registry and posts the banner either way.
    try {
        const seq = JSON.parse(out).terminalSequence;
        const tty = JSON.parse(fs.readFileSync(registryPath(session_id), 'utf8')).tty;
        if (seq && tty) fs.appendFileSync(tty, seq);
    } catch (e) {}
    return session_id;
}

function clear({ tool, id }) {
    const session_id = sid(tool, id);
    run('clear-waiting.js', { session_id });
    return session_id;
}

module.exports = { sid, notify, clear, registryPath };
