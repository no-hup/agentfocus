#!/usr/bin/env node
// Stop-hook probe: records which terminal-identity env vars a DETACHED Claude
// hook actually inherited. Writes both a per-session file and a stable "latest".
const fs = require('fs');
const path = require('path');
const os = require('os');

let input = '';
process.stdin.on('data', c => { input += c; });
process.stdin.on('end', () => write(input));
// Fallback: if stdin never closes, still write after a beat.
setTimeout(() => write(input), 1500);

let done = false;
function write(raw) {
  if (done) return; done = true;
  let hook = {};
  try { if (raw.trim()) hook = JSON.parse(raw); } catch {}
  const sessionId = hook.session_id || 'nosession';

  const cacheDir = path.join(os.homedir(), '.cache', 'agentfocus');
  fs.mkdirSync(cacheDir, { recursive: true });

  const env = {};
  const exact = ['TERM_PROGRAM','TERM','TERM_SESSION_ID','ITERM_SESSION_ID','WEZTERM_PANE','TMUX','TMUX_PANE'];
  for (const k of exact) if (process.env[k] !== undefined) env[k] = process.env[k];
  for (const k of Object.keys(process.env))
    if (/^(GHOSTTY_|KITTY_|AGENTFOCUS_|VSCODE_)/.test(k)) env[k] = process.env[k];

  // pick a usable identity handle, if any
  const handle = env.ITERM_SESSION_ID || env.GHOSTTY_RESOURCES_DIR || env.KITTY_WINDOW_ID
    || env.WEZTERM_PANE || env.TERM_SESSION_ID || env.TMUX_PANE || null;

  const out = {
    session_id: sessionId,
    term_program: env.TERM_PROGRAM || null,
    inherited_identity_handle: handle,
    has_usable_handle: !!handle,
    isTTY: !!process.stdout.isTTY,
    pid: process.pid, ppid: process.ppid,
    env
  };
  const json = JSON.stringify(out, null, 2);
  try { fs.writeFileSync(path.join(cacheDir, `env-probe-${sessionId}.json`), json); } catch {}
  try { fs.writeFileSync(path.join(cacheDir, `env-probe-latest.json`), json); } catch {}
  process.exit(0);
}
