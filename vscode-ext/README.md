# AgentFocus VS Code extension

Works on **VS Code, Cursor, Windsurf, VSCodium** (standard VS Code extension API).

## What it does

1. Injects **`AGENTFOCUS_VSCODE_ID`** into new integrated terminals via `EnvironmentVariableCollection` (unique id per terminal via rotation).
2. Detached agent hooks inherit that env (validated on this project).
3. Watches **`~/.cache/agentfocus/focus-request.json`** written by agy’s `vscode` adapter:
   ```json
   { "session_id": "…", "identity_handle": "<AGENTFOCUS_VSCODE_ID>" }
   ```
4. On match → `terminal.show()` + write `/tmp/agentfocus-last-focus.json`.  
   On **no match → do nothing** (never focuses `terminals[0]`).
5. In-editor toast with **Focus Terminal** as a fallback when a request is handled.

## Build / install

```bash
cd vscode-ext
npm install   # once
npm run compile
```

Install into a fork (pick one):

```bash
# VS Code
code --install-extension . --force   # if supported; else use vsix / Extensions UI

# Cursor — copy into extensions dir after compile:
EXT="$HOME/.cursor/extensions/moonshot.agentfocus-vscode-1.1.0"
mkdir -p "$EXT"
rsync -a --exclude node_modules package.json out src tsconfig.json "$EXT/" 2>/dev/null \
  || { mkdir -p "$EXT/out"; cp package.json "$EXT/"; cp -R out "$EXT/"; }
# Reload Window
```

Or: **Extensions: Install from Location…** and select this `vscode-ext` folder.

## Runtime paths (never Desktop)

| Path | Role |
|---|---|
| `~/.cache/agentfocus/focus-request.json` | Input from agy |
| `/tmp/agentfocus-last-focus.json` | Output for selftest |
