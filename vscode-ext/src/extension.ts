import * as vscode from 'vscode';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
import * as crypto from 'crypto';

/**
 * AgentFocus VS Code / Cursor / Windsurf / VSCodium companion.
 *
 * Identity model (env, not pid-guessing):
 *  - We assign each terminal a stable AGENTFOCUS_VSCODE_ID via
 *    EnvironmentVariableCollection (rotation pattern: value set before
 *    shell start is what that terminal inherits).
 *  - Detached agent hooks inherit that env (validated).
 *  - agy's vscode adapter writes ~/.cache/agentfocus/focus-request.json
 *    { session_id, identity_handle }; we focus the matching terminal only.
 *  - On no match: do NOTHING (never terminal[0]).
 */

const APP = 'agentfocus';
const ENV_KEY = 'AGENTFOCUS_VSCODE_ID';
const CACHE_DIR = path.join(os.homedir(), '.cache', APP);
const FOCUS_REQUEST = path.join(CACHE_DIR, 'focus-request.json');
const LAST_FOCUS = '/tmp/agentfocus-last-focus.json';

/** identity_handle → live terminal */
const terminalsById = new Map<string, vscode.Terminal>();
/** weak reverse map for cleanup */
const idByTerminal = new Map<vscode.Terminal, string>();

let nextId: string = newId();
let envCollection: vscode.GlobalEnvironmentVariableCollection | undefined;
let lastHandledMtime = 0;
let lastHandledPayload = '';

function newId(): string {
  return crypto.randomBytes(16).toString('hex');
}

function tsNow(): string {
  // Avoid Date.now-only paths that some sandboxes block; ISO is fine in extension host.
  return new Date().toISOString();
}

function ensureCacheDir(): void {
  try {
    fs.mkdirSync(CACHE_DIR, { recursive: true, mode: 0o700 });
  } catch {
    /* ignore */
  }
}

function primeEnvCollection(collection: vscode.GlobalEnvironmentVariableCollection): void {
  // Only touch OUR key — never collection.clear() (would drop our other mutators;
  // other extensions have separate collections and are not clobbered either way).
  collection.persistent = false;
  collection.replace(ENV_KEY, nextId);
  envCollection = collection;
}

function rememberTerminal(term: vscode.Terminal, id: string): void {
  terminalsById.set(id, term);
  idByTerminal.set(term, id);
}

function forgetTerminal(term: vscode.Terminal): void {
  const id = idByTerminal.get(term);
  if (id) {
    terminalsById.delete(id);
    idByTerminal.delete(term);
  }
}

/**
 * Rotate AGENTFOCUS_VSCODE_ID so the *next* terminal gets a fresh value.
 * The terminal that just opened should have inherited the previous nextId.
 */
function onTerminalOpened(term: vscode.Terminal): void {
  const idForThis = nextId;
  rememberTerminal(term, idForThis);
  nextId = newId();
  try {
    envCollection?.replace(ENV_KEY, nextId);
  } catch (e) {
    console.error('[agentfocus] env replace failed', e);
  }
}

function writeLastFocus(sessionId: string, terminalId: string): void {
  const payload = {
    session_id: sessionId,
    terminalId,
    ts: tsNow(),
    ok: true,
  };
  try {
    fs.writeFileSync(LAST_FOCUS, JSON.stringify(payload) + '\n', { encoding: 'utf8' });
  } catch (e) {
    console.error('[agentfocus] write last-focus failed', e);
  }
}

function focusTerminal(
  term: vscode.Terminal,
  sessionId: string,
  identityHandle: string,
  showToast: boolean
): void {
  term.show(true);
  writeLastFocus(sessionId, identityHandle);

  if (showToast) {
    const action = 'Focus Terminal';
    void vscode.window
      .showInformationMessage(`AgentFocus: session ${sessionId} needs attention`, action)
      .then((sel) => {
        if (sel === action) {
          term.show(true);
          writeLastFocus(sessionId, identityHandle);
        }
      });
  }
}

interface FocusRequest {
  session_id?: string;
  identity_handle?: string;
  title?: string;
  message?: string;
}

function readFocusRequest(): FocusRequest | null {
  try {
    const st = fs.statSync(FOCUS_REQUEST);
    const raw = fs.readFileSync(FOCUS_REQUEST, 'utf8');
    // Dedup: same mtime+content
    if (st.mtimeMs === lastHandledMtime && raw === lastHandledPayload) {
      return null;
    }
    let data: FocusRequest;
    try {
      data = JSON.parse(raw) as FocusRequest;
    } catch {
      // partial write — retry once shortly is handled by next watch event
      return null;
    }
    lastHandledMtime = st.mtimeMs;
    lastHandledPayload = raw;
    return data;
  } catch (e: unknown) {
    const err = e as NodeJS.ErrnoException;
    if (err.code === 'ENOENT') return null;
    return null;
  }
}

function handleFocusRequest(showToast: boolean): void {
  const data = readFocusRequest();
  if (!data) return;

  const handle = (data.identity_handle || '').trim();
  const sessionId = (data.session_id || '').trim() || handle;
  if (!handle) {
    // No identity — do nothing (never guess terminal[0])
    return;
  }

  const term = terminalsById.get(handle);
  if (!term) {
    // Stale / unknown handle — do NOTHING
    console.warn('[agentfocus] no terminal for identity_handle=', handle);
    return;
  }

  // Drop disposed terminals
  if (term.exitStatus !== undefined) {
    forgetTerminal(term);
    return;
  }

  focusTerminal(term, sessionId, handle, showToast);
}

export function activate(context: vscode.ExtensionContext): void {
  ensureCacheDir();

  const collection = context.environmentVariableCollection;
  primeEnvCollection(collection);

  // Terminals already open: map them for in-session focus, but they will NOT
  // have AGENTFOCUS_VSCODE_ID in env until recreated (env is fixed at shell start).
  for (const term of vscode.window.terminals) {
    const id = newId();
    rememberTerminal(term, id);
  }

  context.subscriptions.push(
    vscode.window.onDidOpenTerminal((term) => {
      onTerminalOpened(term);
    })
  );

  context.subscriptions.push(
    vscode.window.onDidCloseTerminal((term) => {
      forgetTerminal(term);
    })
  );

  // Watch focus-request.json (agy vscode adapter)
  let debounce: NodeJS.Timeout | undefined;
  const schedule = () => {
    if (debounce) clearTimeout(debounce);
    debounce = setTimeout(() => handleFocusRequest(true), 75);
  };

  try {
    const watcher = fs.watch(CACHE_DIR, (_event, filename) => {
      if (!filename) return;
      if (filename === 'focus-request.json' || String(filename).endsWith('focus-request.json')) {
        schedule();
      }
    });
    context.subscriptions.push({ dispose: () => watcher.close() });
  } catch (e) {
    console.error('[agentfocus] watch failed', e);
  }

  // Poll fallback (some FS events drop on macOS network/home dirs)
  const poll = setInterval(() => handleFocusRequest(true), 1000);
  context.subscriptions.push({ dispose: () => clearInterval(poll) });

  context.subscriptions.push(
    vscode.commands.registerCommand('agentfocus.focusTerminal', () => {
      handleFocusRequest(false);
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand('agentfocus.debugListTerminals', () => {
      const rows = [...terminalsById.entries()].map(([id, t]) => `${id.slice(0, 8)}… → ${t.name}`);
      void vscode.window.showInformationMessage(
        rows.length ? rows.join(' | ') : 'No mapped terminals'
      );
    })
  );
}

export function deactivate(): void {
  terminalsById.clear();
  idByTerminal.clear();
}
