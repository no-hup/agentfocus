#!/usr/bin/env node
// Self-check for emit.js's two trust-boundary behaviours: what it puts in the
// terminal escape sequence, and what it will accept as a filename.
// Runs under a throwaway $HOME so the real registry is never touched.
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');
const assert = require('assert');

const HOME = fs.mkdtempSync(path.join(os.tmpdir(), 'agentfocus-test-'));
const REGISTRY = path.join(HOME, '.local/share/agentfocus/registry');
// `open` and `osascript` are NOT scoped by $HOME: with no helper app under a
// throwaway home, emit.js falls back to `osascript display notification` and a
// real banner lands on the live desktop, from a test. Stub both on PATH — the
// same trick selftest/osc-native.sh already uses.
function stubPath(home) {
    const dir = path.join(home, 'stub');
    fs.mkdirSync(dir, { recursive: true });
    for (const cmd of ['open', 'osascript']) {
        fs.writeFileSync(path.join(dir, cmd), '#!/bin/sh\nexit 0\n', { mode: 0o755 });
    }
    return dir + path.delimiter + process.env.PATH;
}
const PATH = stubPath(HOME);

const emit = (payload) => execFileSync('node', [path.join(__dirname, '../hook/emit.js')], {
    input: JSON.stringify(payload),
    encoding: 'utf8',
    env: { ...process.env, HOME, PATH },
});

// 1. A message is sanitised before it reaches the terminal AND the registry.
const id = 'test-session-' + Date.now();
const out = JSON.parse(emit({
    session_id: id,
    cwd: process.cwd(),
    hook_event_name: 'Notification',
    message: 'Testing fallback \x1b[31mwith control chars\x07\n\n',
}));
assert(out.terminalSequence, 'must emit terminalSequence');
assert(!out.terminalSequence.includes('\x1b[31m'), 'control chars must be stripped');
assert(!out.terminalSequence.includes('\n'), 'newlines must be stripped');
const row = JSON.parse(fs.readFileSync(path.join(REGISTRY, `${id}.json`), 'utf8'));
assert.strictEqual(row.session_id, id, 'session id round-trips');
assert(!/[\n\x1b]/.test(row.reason), 'reason in the registry must be sanitised too');
console.log('PASS: emit and sanitisation.');

// 2. A traversing session_id is REJECTED — not rewritten to some default file.
//    (The old harness expected a default.json fallback; there is no such file.)
const evil = '../escape-' + Date.now();
emit({ session_id: evil, cwd: process.cwd(), hook_event_name: 'Notification', message: 'x' });
assert(!fs.existsSync(path.join(REGISTRY, '..', evil + '.json')), 'traversal must not write outside the registry');
assert.deepStrictEqual(fs.readdirSync(REGISTRY), [`${id}.json`], 'a rejected id writes nothing at all');
console.log('PASS: path traversal rejected.');

fs.rmSync(HOME, { recursive: true, force: true });
console.log('All self-checks passed!');
