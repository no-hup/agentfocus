#!/usr/bin/env node
// Checks the one piece of non-trivial logic added to hook/emit.js: the banner
// `reason` a session shows, and the `bg` list the next Stop diffs against.
// Runs under a throwaway $HOME — touches no real registry entry, launches
// nothing. Payload shapes are copied from real Claude Code 2.1.247 hook dumps.
const fs = require('fs');
const os = require('os');
const path = require('path');
const assert = require('assert');
const { execFileSync } = require('child_process');

const EMIT = path.join(__dirname, '..', 'hook', 'emit.js');
const HOME = fs.mkdtempSync(path.join(os.tmpdir(), 'af-emit-'));
const REG = path.join(HOME, '.local/share/agentfocus/registry');
// Independent cases get their own session id; only the (c) sequence shares one,
// because that is exactly what it is testing.
let n = 0;
const fresh = () => `reason-test-${++n}`;

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
function emit(payload, sid) {
    sid = sid || fresh();
    execFileSync(process.execPath, [EMIT], {
        input: JSON.stringify(Object.assign({ session_id: sid, cwd: HOME }, payload)),
        encoding: 'utf8',
        env: Object.assign({}, process.env, { HOME, PATH }),
        stdio: ['pipe', 'pipe', 'ignore'],
    });
    return JSON.parse(fs.readFileSync(path.join(REG, `${sid}.json`), 'utf8'));
}
const task = (id, status, description) =>
    ({ id, type: 'subagent', status, description, agent_type: 'general-purpose' });

let row;

// (a) plain done — no background work.
row = emit({ hook_event_name: 'Stop', background_tasks: [] });
assert.strictEqual(row.reason, 'needs input', 'plain Stop');
assert.deepStrictEqual(row.bg, [], 'plain Stop leaves no bg');

// (b) done, background work still running. One task inlines its description.
row = emit({ hook_event_name: 'Stop', background_tasks: [task('a1', 'running', 'Run echo probe command')] });
assert.strictEqual(row.reason, 'done — 1 background task running: Run echo probe command', 'one running');
assert.deepStrictEqual(row.bg.map(t => t.id), ['a1'], 'bg recorded for the next diff');

// (b') three tasks — too many to inline, count only.
row = emit({ hook_event_name: 'Stop', background_tasks: ['a1', 'a2', 'a3'].map(i => task(i, 'running', 'x')) });
assert.strictEqual(row.reason, 'done — 3 background tasks running', 'three running');

// (b'') a long description must not be inlined, and reason stays banner-sized.
row = emit({ hook_event_name: 'Stop', background_tasks: [task('a1', 'running', 'y'.repeat(300))] });
assert.strictEqual(row.reason, 'done — 1 background task running', 'long description not inlined');
assert(row.reason.length <= 120, 'reason capped');

// (c) the background-wake Stop names what finished. Real Claude Code delivers
// the wake as a synthetic UserPromptSubmit first, so replay that too — it must
// not disturb the pending bg list.
const SEQ = fresh();
emit({ hook_event_name: 'Stop', background_tasks: [task('a1', 'running', 'Run echo probe command'), task('a2', 'running', 'Other job')] }, SEQ);
execFileSync(process.execPath, [path.join(__dirname, '..', 'hook', 'clear-waiting.js')],
    { input: JSON.stringify({ session_id: SEQ }), env: Object.assign({}, process.env, { HOME, PATH }), stdio: 'ignore' });
row = emit({ hook_event_name: 'Stop', background_tasks: [task('a2', 'running', 'Other job')] }, SEQ);
assert.strictEqual(row.reason, 'Background agent finished: Run echo probe command (+1 still running)', 'wake names the finisher');

// ...and the SAME finish is never announced twice: every emit rewrites bg.
row = emit({ hook_event_name: 'Stop', background_tasks: [task('a2', 'running', 'Other job')] }, SEQ);
assert.strictEqual(row.reason, 'done — 1 background task running: Other job', 'no double announce');

// Statuses other than running/pending are terminal, so they read as finished.
row = emit({ hook_event_name: 'Stop', background_tasks: [task('a2', 'killed', 'Other job')] }, SEQ);
assert.strictEqual(row.reason, 'Background agent finished: Other job', 'killed counts as finished');

// (d) permission prompt. Claude Code 2.1.247 does NOT put agent_id on the
// Notification even when a subagent asked, so this is the parent's own message,
// verbatim — never suppressed, never delayed.
row = emit({ hook_event_name: 'Notification', notification_type: 'permission_prompt', message: 'Claude needs your permission' });
assert.strictEqual(row.reason, 'Claude needs your permission', 'permission prompt passes through');
assert.deepStrictEqual(row.bg, [], 'a Notification clears no bg it did not own');

// Legacy Claude Code: no background_tasks field at all.
row = emit({ hook_event_name: 'Stop' });
assert.strictEqual(row.reason, 'needs input', 'missing background_tasks degrades cleanly');

// integrations/_emit.js shims send no hook_event_name, just a message.
row = emit({ message: 'opencode needs input' });
assert.strictEqual(row.reason, 'opencode needs input', 'shim payload unchanged');

// Control characters and semicolons would corrupt the OSC sequence.
row = emit({ hook_event_name: 'Stop', background_tasks: [task('a9', 'running', 'we;ird\n\x1b[31mthing')] });
assert(!/[;\x00-\x1F]/.test(row.reason), 'reason is OSC-safe');

fs.rmSync(HOME, { recursive: true, force: true });
console.log('emit-reason: ok');
