# agentfocus selftest — control-plane harness

Headless-friendly checks for the **notification → focus → correct surface** loop.  
An AI agent with shell (no eyes) can run these and only escalate to a human for the true last mile.

Two tracks:

| Track | Entry | Against |
|---|---|---|
| **Stub** | `./smoke.sh` | `stub/agentfocus` (no agy core required) |
| **Real product** | `./smoke-real.sh` | agy CLI + registry under `~/.local/share/agentfocus/` |
| **Fresh account** | `./fresh-user.sh` | full install-day story on a brand-new macOS user — human-in-the-loop prompt census, banner/click/hotkey, logout-login persistence, rebuild re-prompt. `--resume` after re-login. |

### agy product contract (smoke-real)

| Contract | Path |
|---|---|
| Registry | `~/.local/share/agentfocus/registry/<session_id>.json` |
| CLI | `~/.local/share/agentfocus/bin/agentfocus` (`focus`, `focus-next`, `list`, `doctor`) |
| VS Code focus signal | `~/.cache/agentfocus/focus-request.json` |
| Last focus (harness) | `/tmp/agentfocus-last-focus.json` |

**Never** put hook/CLI runtime scripts on `~/Desktop` — Terminal spawned via Automation often cannot read Desktop (TCC). `smoke-real.sh` stages under `~/.local/share/agentfocus/selftest-run/`.

### Stub contracts (`smoke.sh`)

| Contract | Path |
|---|---|
| Event log | `~/Library/Logs/agentfocus/events.jsonl` |
| Session registry (stub) | `~/Library/Application Support/agentfocus/registry/<id>.json` |
| Last focus result | `/tmp/agentfocus-last-focus.json` |
| Click routing | `focus --id` (same path `sim-click.sh` uses) |

## Requirements

- macOS with **Aqua GUI login session** (the logged-in desktop)
- `bash`, `node`, `osascript`, `lsappinfo`, `uuidgen`
- Optional: `tmux`, iTerm2, Terminal.app Automation grants

### Must run under Aqua (not headless SSH)

Frontmost-app checks, `open -a`, and real notifications need the window server.  
If you are in SSH, either:

```bash
# run as the logged-in GUI user via launchctl (example pattern)
launchctl asuser "$(id -u)" "$PWD/smoke.sh"
```

…or run from Terminal/iTerm/VS Code **on the Mac’s desktop session**.

Do **not** expect smoke to pass in a pure headless CI agent without Aqua.

## Layout

```
selftest/
  stub/agentfocus     # stub CLI: register | notify | focus
  sim-click.sh        # simulated notification click → focus
  assert/
    check_notify.sh
    check_frontmost.sh
    check_tab.sh
  smoke.sh            # stub full loop
  smoke-real.sh       # REAL product: spawn Terminal.app + agentfocus focus/focus-next
  perms-doctor.sh     # TCC technique probe table
  fresh-user.sh       # fresh-macOS-account falsification run (human answers y/n)
  README.md
```

## Quick start

```bash
cd ~/Desktop/moonshot/agentfocus/selftest
chmod +x stub/agentfocus sim-click.sh smoke.sh smoke-real.sh perms-doctor.sh assert/*.sh

# permission / environment probe
./perms-doctor.sh

# stub control-plane smoke (no agy core)
./smoke.sh

# REAL product smoke (requires agy CLI installed under ~/.local/share)
./smoke-real.sh

# Fresh-account run — ONLY on a brand-new macOS user, before installing anything.
# Location-independent; copy it to ~/ on the test account and run from there.
AF_INSTALL=brew ./fresh-user.sh        # then, after a logout/login:
./fresh-user.sh --resume
```

### Manual step-through

```bash
ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
./stub/agentfocus register --id "$ID" --app terminal --hint "$(tty | sed 's|^/dev/||')"
./stub/agentfocus notify  --id "$ID" --title "demo" --body "needs input"
./assert/check_notify.sh "$ID"
./sim-click.sh "$ID"
sleep 0.7
./assert/check_frontmost.sh terminal
./assert/check_tab.sh "$ID"
```

## Stub CLI

```text
agentfocus register --id <id> --app <app> [--hint <hint>]
agentfocus notify  --id <id> [--title <t>] [--body <b>]
agentfocus focus   --id <id>
```

- **register** — writes registry JSON; appends `event=register` to JSONL  
- **notify** — posts a real notification via `osascript display notification` (works on this Mac / Tahoe path we validated); appends `event=notify`  
- **focus** — `open -a <App>` (fallback AppleScript `activate`); writes `/tmp/agentfocus-last-focus.json`; appends `event=focus`

Timestamps use shell `date -u +%Y-%m-%dT%H:%M:%SZ` (no `Date.now()`). IDs use `uuidgen`.

### App aliases

| `--app` | `open -a` target | frontmost accept list |
|---|---|---|
| `vscode` / `code` | Visual Studio Code | Code, Visual Studio Code, Code - Insiders |
| `cursor` | Cursor | Cursor |
| `iterm` / `iterm2` | iTerm | iTerm2, iTerm |
| `ghostty` | Ghostty | Ghostty |
| `terminal` | Terminal | Terminal |
| `tmux` | Terminal (host) | Terminal / iTerm2 / Ghostty / Code / Cursor |

## Simulated click / URL scheme

`sim-click.sh <id>` calls `agentfocus focus --id <id>` — the **same routing code path** a real banner click should invoke.

Registering a real `agentfocus://` handler requires an `.app` bundle with `CFBundleURLTypes` in `Info.plist` (LaunchServices). That is **not** part of this stub (cheap bundle can be added later). When it exists:

```bash
open "agentfocus://s/<id>"
# must resolve to the same focus path as:
./sim-click.sh <id>
```

Until then, `sim-click.sh` is the valid routing e2e.

## What is agent-verifiable vs human last-mile

| Check | Agent-verifiable? | How |
|---|---|---|
| Notify intent logged (`notify`+`ok` in JSONL) | **Yes** | `assert/check_notify.sh` |
| Notification API call succeeded (`osascript`) | **Yes** (command exit) | stub `notify` |
| Banner *visible* / chrome / sound / grouping | **No** | human glance |
| Simulated click routing (`focus`) | **Yes** | `sim-click.sh` |
| Frontmost application | **Yes** | `lsappinfo` + `check_frontmost.sh` |
| Correct tab (VS Code / Cursor / Ghostty stub) | **Yes** (control plane) | `/tmp/agentfocus-last-focus.json` |
| Correct tty (iTerm / Terminal) | **Yes if Automation granted** | AppleScript; else last-focus fallback |
| Correct tmux pane | **Yes if inside tmux** | `tmux display-message` |
| First-run TCC prompts | **No** | human click Allow |
| One real banner **click** (LaunchServices URL) | **No** until `.app` URL handler | human; then same asserts |
| Focus mode suppressing banners | Soft | human / Settings |

### Human last-mile protocol (≤2 minutes)

1. Run `./perms-doctor.sh` — grant any **no** rows you care about (Automation / Accessibility / Notifications).  
2. Run `./smoke.sh` — agent-owned path must be **PASS**.  
3. When a real notify banner appears: click it **only after** a URL-handler `.app` exists; until then, treat step 2’s sim-click as routing proof and optionally confirm banner text looks sane by eye once.

## perms-doctor

```bash
./perms-doctor.sh
```

Prints a table: `technique | needs | granted? | detail` by **attempting** each call (not by reading TCC.db).

## Exit codes

| Script | 0 | 1 | 2 |
|---|---|---|---|
| `smoke.sh` | all checks passed | one or more failed | — |
| `assert/*` | assertion held | assertion failed | bad usage |

## Relation to real product

Replace `stub/agentfocus` with the real helper CLI **without changing** the assert scripts if you keep:

1. JSONL event shape: `{ts, event, id, app, ok, detail}`  
2. `focus` writes `/tmp/agentfocus-last-focus.json` `{id, app, terminalId, ts, ok?}`  
3. Click → same `focus --id` path (directly or via `agentfocus://`)
