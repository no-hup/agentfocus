#!/usr/bin/env node
// Two window raises landing within the editor's open-file batch window do not
// raise two windows — the editor merges both into one untitled workspace and the
// user's layout is gone. Verified on VS Code 1.136.1: two back-to-back
// `open -a Code <folder>` calls produced Workspaces/<ts>/workspace.json holding
// both folders; the same two spaced 500ms apart produced none.
//
// The colliding raises come from SEPARATE `agentfocus focus` processes, so this
// exercises real processes, not an in-process flag that would never have seen it.
//
//   node test/raise-gap.js
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const EW = path.join(__dirname, '..', 'adapters', 'editor_window.js');
const HOME = fs.mkdtempSync(path.join(os.tmpdir(), 'af-raise-'));

// One child = one `agentfocus focus`. Prints "true" if it won the right to raise.
const child = `console.log(require(${JSON.stringify(EW)}).claimRaise())`;
function claimants(n) {
    const kids = Array.from({ length: n }, () =>
        require('child_process').spawn(process.execPath, ['-e', child],
            { env: { ...process.env, HOME }, stdio: ['ignore', 'pipe', 'ignore'] }));
    return Promise.all(kids.map(k => new Promise(res => {
        let out = ''; k.stdout.on('data', d => out += d);
        k.on('close', () => res(out.trim() === 'true'));
    })));
}

(async () => {
    const won = (await claimants(5)).filter(Boolean).length;
    assert.strictEqual(won, 1, `5 simultaneous raises: expected exactly 1 to proceed, got ${won}`);

    const { claimRaise, RAISE_GAP_MS } = require(EW);
    process.env.HOME = HOME;
    assert.strictEqual(claimRaise(), false, 'a raise inside the gap must be declined');
    assert.strictEqual(claimRaise(RAISE_GAP_MS, Date.now() + RAISE_GAP_MS + 1), true,
        'once the gap has passed the next raise must proceed');

    // The gap is only worth anything if every raise goes through it. `open -a <app>
    // <folder>` is the call that enters the editor's batch; editor_window.js must
    // stay its only caller. (`open -g <app>` opens no path and cannot batch.)
    const root = path.join(__dirname, '..');
    const hits = execFileSync('grep', ['-rn', "execFileSync('open', \\['-a'", 'bin', 'adapters', 'hook'],
        { cwd: root, encoding: 'utf8' }).trim().split('\n');
    assert.deepStrictEqual(hits.map(h => h.split(':')[0]), ['adapters/editor_window.js'],
        `window raises must all go through editor_window.js, found:\n${hits.join('\n')}`);

    fs.rmSync(HOME, { recursive: true, force: true });
    console.log('ok  raise-gap: 1 of 5 concurrent raises proceeds; single raise site');
})();
