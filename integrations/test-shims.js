#!/usr/bin/env node
// Self-check for the integration shims. No framework, no deps.
//   node integrations/test-shims.js
// Runs against a throwaway HOME so the real registry is never touched.
const fs = require('fs');
const os = require('os');
const path = require('path');
const assert = require('assert');
const { execFileSync } = require('child_process');

const HOME = fs.mkdtempSync(path.join(os.tmpdir(), 'agentfocus-test-'));
process.env.HOME = HOME; // inherited by every child, and used by _emit directly
const REG = path.join(HOME, '.local/share/agentfocus/registry');
const SHIM = path.join(__dirname, 'shim.js');

const run = (tool, action, payload) =>
    execFileSync(process.execPath, [SHIM, tool, action], {
        input: JSON.stringify(payload), encoding: 'utf8', stdio: ['pipe', 'pipe', 'inherit'],
    });

const read = (sid) => JSON.parse(fs.readFileSync(path.join(REG, `${sid}.json`), 'utf8'));
const ok = (m) => console.log('PASS:', m);

// --- Codex: Stop + PermissionRequest + UserPromptSubmit ------------------
// Payload fields per https://learn.chatgpt.com/docs/hooks
{
    const stdout = run('codex', 'notify', {
        session_id: '0199a1f2-dead-beef-0000-000000000001', turn_id: 't1',
        hook_event_name: 'Stop', permission_mode: 'default', cwd: '/tmp/proj-codex',
        stop_hook_active: false, last_assistant_message: 'Done refactoring.',
    });
    assert.strictEqual(stdout, '', 'shim must print nothing (host parses hook stdout)');
    const sid = 'codex-0199a1f2-dead-beef-0000-000000000001';
    const d = read(sid);
    assert.strictEqual(d.session_id, sid);
    assert.strictEqual(d.cwd, '/tmp/proj-codex');
    assert.strictEqual(d.title, 'proj-codex');
    assert.strictEqual(d.waiting, true);
    assert(Date.now() - d.ts < 30000, 'ts must be fresh');
    ok('codex Stop → registry entry, waiting=true');

    run('codex', 'notify', {
        session_id: '0199a1f2-dead-beef-0000-000000000001', hook_event_name: 'PermissionRequest',
        cwd: '/tmp/proj-codex', tool_name: 'shell', tool_input: { command: 'rm -rf /' },
    });
    assert.strictEqual(read(sid).waiting, true);
    ok('codex PermissionRequest → same session id reused');

    run('codex', 'clear', { session_id: '0199a1f2-dead-beef-0000-000000000001', hook_event_name: 'UserPromptSubmit' });
    assert.strictEqual(read(sid).waiting, false, 'clear must flip waiting');
    ok('codex UserPromptSubmit → waiting=false');
}

// --- Copilot: agentStop + notification filtering + userPromptSubmitted ---
// Payload fields per https://docs.github.com/en/copilot/reference/hooks-reference
{
    const sid = 'copilot-abc123';
    run('copilot', 'notify', { sessionId: 'abc123', timestamp: Date.now(), cwd: '/tmp/proj-cop' });
    assert.strictEqual(read(sid).waiting, true);
    assert.strictEqual(read(sid).cwd, '/tmp/proj-cop');
    ok('copilot agentStop → registry entry');

    run('copilot', 'clear', { sessionId: 'abc123', cwd: '/tmp/proj-cop' });
    assert.strictEqual(read(sid).waiting, false);

    run('copilot', 'notify', {
        sessionId: 'abc123', cwd: '/tmp/proj-cop', title: 'Permission',
        message: 'Allow bash?', notification_type: 'permission_prompt',
    });
    assert.strictEqual(read(sid).waiting, true);
    ok('copilot notification(permission_prompt) → waiting=true');

    run('copilot', 'clear', { sessionId: 'abc123' });
    run('copilot', 'notify', {
        sessionId: 'abc123', cwd: '/tmp/proj-cop', message: 'ls finished',
        notification_type: 'shell_completed',
    });
    assert.strictEqual(read(sid).waiting, false, 'shell_completed must NOT raise a banner');
    ok('copilot notification(shell_completed) → ignored');
}

// --- Goose: Stop + UserPromptSubmit (working_dir, not cwd) ---------------
// Payload fields per https://goose-docs.ai/blog/2026/05/14/goose-hooks/
{
    const sid = 'goose-sess_42';
    run('goose', 'notify', { event: 'Stop', session_id: 'sess_42', working_dir: '/tmp/proj-goose' });
    const d = read(sid);
    assert.strictEqual(d.cwd, '/tmp/proj-goose', 'must map working_dir → cwd');
    assert.strictEqual(d.waiting, true);
    ok('goose Stop → working_dir mapped to cwd');

    run('goose', 'clear', { event: 'UserPromptSubmit', session_id: 'sess_42', working_dir: '/tmp/proj-goose' });
    assert.strictEqual(read(sid).waiting, false);
    ok('goose UserPromptSubmit → waiting=false');
}

// --- Edge cases ---------------------------------------------------------
{
    const before = fs.readdirSync(REG).length;
    assert.strictEqual(run('codex', 'notify', {}), '');   // no session_id
    assert.strictEqual(run('goose', 'notify', ''), '');   // empty stdin
    execFileSync(process.execPath, [SHIM, 'codex', 'notify'], { input: 'not json', stdio: 'ignore' });
    const files = fs.readdirSync(REG);
    // Exactly two new files: one cwd-hash fallback per tool. Malformed JSON exits
    // before touching anything, and repeat calls reuse the same deterministic id.
    assert.strictEqual(files.length, before + 2, `unexpected registry contents: ${files}`);
    assert(files.some((f) => /^codex-[0-9a-f]{16}\.json$/.test(f)), 'missing id → cwd-hash fallback');
    assert(files.some((f) => /^goose-[0-9a-f]{16}\.json$/.test(f)), 'missing id → cwd-hash fallback');
    ok('missing id → stable hash fallback; malformed stdin → no-op');

    run('codex', 'notify', { session_id: '../../etc/passwd', cwd: '/tmp/x' });
    run('codex', 'notify', { session_id: 'has spaces/and:junk', cwd: '/tmp/x' });
    for (const f of fs.readdirSync(REG)) assert(!f.includes('/') && !f.includes('..'), `escaped: ${f}`);
    assert(fs.existsSync(path.join(REG, 'codex-------etc-passwd.json')), 'traversal sanitized in place');
    assert(fs.existsSync(path.join(REG, 'codex-has-spaces-and-junk.json')), 'junk chars sanitized');
    ok('unsafe session ids sanitized, stay inside the registry dir');
}

// --- OpenCode plugin (in-process; no shell hooks exist) -----------------
(async () => {
    const { AgentFocus } = await import('./opencode-agentfocus.js');
    const h = await AgentFocus({ directory: '/tmp/proj-oc' });
    const sid = 'opencode-ses_9x';

    const status = (s, t) => h.event({ event: { type: 'session.status', properties: { sessionID: s, status: { type: t } } } });

    // Idle with no preceding busy = a session that never worked. Must stay quiet.
    await status('ses_9x', 'idle');
    assert(!fs.existsSync(path.join(REG, `${sid}.json`)), 'idle without busy must not notify');
    ok('opencode idle-without-busy → ignored');

    await status('ses_9x', 'busy');
    await status('ses_9x', 'idle');
    assert.strictEqual(read(sid).cwd, '/tmp/proj-oc');
    assert.strictEqual(read(sid).waiting, true);
    ok('opencode session.status busy→idle → registry entry, waiting=true');

    await h['chat.message']({ sessionID: 'ses_9x' });
    assert.strictEqual(read(sid).waiting, false);
    ok('opencode chat.message → waiting=false');

    await h.event({ event: { type: 'permission.updated', properties: { sessionID: 'ses_9x', title: 'run bash' } } });
    assert.strictEqual(read(sid).waiting, true);
    ok('opencode permission.updated → waiting=true');

    // Legacy event, kept for compat with older/newer opencode builds.
    await status('ses_9x', 'busy');
    await h.event({ event: { type: 'session.idle', properties: { sessionID: 'ses_9x' } } });
    assert.strictEqual(read(sid).waiting, true);
    ok('opencode legacy session.idle → still handled');

    await h.event({ event: { type: 'file.edited', properties: { sessionID: 'ses_other' } } });
    assert(!fs.existsSync(path.join(REG, 'opencode-ses_other.json')), 'unrelated events ignored');
    ok('opencode unrelated events ignored');

    fs.rmSync(HOME, { recursive: true, force: true });
    console.log('\nAll integration self-checks passed.');
})().catch((e) => { console.error('FAIL:', e); process.exit(1); });
