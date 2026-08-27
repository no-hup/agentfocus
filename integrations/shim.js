#!/usr/bin/env node
// Usage: node shim.js <codex|copilot|goose> <notify|clear>
// Reads that tool's native hook payload on stdin, normalizes it, and drives the
// frozen hook/emit.js (or hook/clear-waiting.js). Prints nothing: Codex and
// Copilot parse hook stdout as their own response schema, and empty = "no opinion".
const { notify, clear } = require('./_emit');

const [tool, action] = process.argv.slice(2);

// Per-tool field names. Every one of these differs from Claude's shape.
const MAP = {
    // learn.chatgpt.com/docs/hooks — Claude-shaped already, plus PermissionRequest.
    codex: (p) => ({
        id: p.session_id,
        cwd: p.cwd,
        message: p.hook_event_name === 'PermissionRequest'
            ? `needs approval: ${p.tool_name || 'tool'}`
            : (p.last_assistant_message || 'turn complete'),
    }),
    // docs.github.com/en/copilot/reference/hooks-reference — camelCase payload.
    copilot: (p) => {
        // The `notification` event covers far more than "user is blocked".
        // Only these three mean a human is actually waiting.
        const WAITING = ['permission_prompt', 'elicitation_dialog', 'agent_idle'];
        if (p.notification_type && !WAITING.includes(p.notification_type)) return null;
        return { id: p.sessionId, cwd: p.cwd, message: p.message || 'turn complete' };
    },
    // goose-docs.ai/blog/2026/05/14/goose-hooks — note working_dir, not cwd.
    goose: (p) => ({ id: p.session_id, cwd: p.working_dir, message: 'turn complete' }),
};

if (!MAP[tool] || !['notify', 'clear'].includes(action)) process.exit(0);

let input = '';
process.stdin.on('data', (c) => { input += c; });
process.stdin.on('end', () => {
    let p = {};
    try { if (input.trim()) p = JSON.parse(input); } catch (e) { process.exit(0); }

    const m = MAP[tool](p);
    if (!m) process.exit(0);
    try {
        if (action === 'notify') notify({ tool, ...m });
        else clear({ tool, id: m.id });
    } catch (e) {}
    process.exit(0);
});
