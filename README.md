# agentfocus

**When your terminal coding agent needs you, the notification takes you to the exact tab.**

macOS. Fully local — no network, no telemetry, no credentials, no account. Everything is
files on your disk.

## The problem

You background three agents across Terminal tabs and a couple of VS Code windows. One
finishes. A banner appears. You click it — and nothing happens, or the wrong window comes
forward. Now you're hunting for which tab was asking.

## What it does

1. Your agent finishes or asks a question. A hook (`Stop` / `Notification`) writes one
   small JSON file: `~/.local/share/agentfocus/registry/<session_id>.json`. It records the
   terminal program, the controlling `tty` (recovered by walking the ancestor PID chain,
   because the hook itself is detached), a per-terminal identity handle, the editor app if
   you're in one, the cwd, and `waiting: true`.
2. A menu-bar helper app (`~/Applications/AgentFocus.app`) polls that directory every two
   seconds and posts a clickable notification: **agentfocus: `<folder>`** / *waiting for
   input (`<terminal>`)*.
3. You click the banner. The helper runs `agentfocus focus <id>`, which picks the adapter
   for that terminal: Terminal.app gets an AppleScript that matches `tty of tab`, selects
   that exact tab and raises its window; the VS Code family gets its window raised for
   that project folder.
4. You type your next prompt. The `UserPromptSubmit` hook clears `waiting`, the banner is
   withdrawn, and the queue drains itself.

Terminals that post their own notifications (Ghostty, kitty, WezTerm, iTerm2's OSC path)
handle steps 2 and 3 themselves. The registry marks those sessions `osc_native` so the
helper stays quiet and you never get two banners for one event.

## Install

```sh
brew install --HEAD no-hup/agentfocus/agentfocus
agentfocus init
```

*Landing in this release.* Until the first tagged release, brew installs from HEAD
(`--HEAD` required; Homebrew no longer installs loose formula files).
Re-run `agentfocus init` after a `brew upgrade` — it refreshes the runtime copy and the
helper app.

**From source (dev):**

```sh
git clone https://github.com/no-hup/agentfocus
cd agentfocus
./install.sh
```

That's the whole thing. `install.sh` runs `init`, which stages the CLI, hooks and adapters
under `~/.local/share/agentfocus`, merges the hooks into `~/.claude/settings.json`
non-destructively (with a timestamped backup of your existing settings), builds the helper
into `~/Applications/AgentFocus.app` and launches it.

Optionally put the CLI on your `PATH`:

```sh
export PATH="$HOME/.local/share/agentfocus/bin:$PATH"
```

## Permissions — the honest version

Three things happen, total. Two of them on install day.

| When | What you see | Do you have to? |
|---|---|---|
| Install day | One **Notifications** permission prompt, from the helper app | Yes, or there are no banners |
| Install day | One informational **"Login Item Added"** banner — the helper registers itself to start at login (toggle it off in the menu any time) | No, it's not a prompt; nothing to click |
| First banner-click **per terminal app** | One **Automation** prompt: *"AgentFocus" wants to control "Terminal"* | Decline and it still works — you get app-level focus instead of exact-tab |

And that's it. agentfocus **never** asks for Accessibility, **never** for Screen Recording,
**never** for Input Monitoring. The global hotkey uses Carbon's `RegisterEventHotKey`,
which needs none of them. There is no helper daemon running as root, no login shell
hooking, nothing outside your home directory.

**One caveat, stated plainly:** the helper is ad-hoc signed (no paid Developer ID
signature yet). macOS ties an Automation grant to the exact signature, so **after a rebuild
or an upgrade you get the Automation prompt once more.** That's an accepted v1 tradeoff,
not a bug — `agentfocus doctor` prints a reminder about it.

## Supported agents

| Agent | Status |
|---|---|
| Claude Code | Wired today — `install.sh` / `agentfocus init` merges the hooks for you |
| Codex CLI, Copilot CLI, Goose, OpenCode | Shims under [`integrations/`](integrations/) — see its README for per-tool setup and verification status (Codex hooks need a one-time `/hooks` trust approval) |

The contract is small on purpose: anything that can run a command when it finishes or
blocks can write a registry entry. That's the whole integration.

## Where a click takes you

| Surface | What a click does | Confidence |
|---|---|---|
| **Terminal.app** | The exact tab, matched by `tty` | Verified on hardware |
| **iTerm2** | The exact session, matched against `ITERM_SESSION_ID` | **Unverified on real hardware** — treat as best-effort |
| **Ghostty / kitty / WezTerm** | The terminal's own native OSC notification focuses its own tab; agentfocus suppresses its banner so there's only one | Native path |
| **VS Code / Cursor / Windsurf / VSCodium** | Window level — raises the right fork's window for that project folder (the fork is detected from the editor's own env, so Cursor sessions raise Cursor). The optional extension in `vscode-ext/` adds best-effort tab-exact focus on top | Window-level; tab-exact is best-effort |
| **tmux, SSH-remote, devcontainers** | Not bridged | Out of scope — see [KNOWN-ISSUES.md](KNOWN-ISSUES.md) |

**Not supported, and why:** the agents built *into* the editors — Cursor Composer, Copilot
Chat, the VS Code Claude panel. They don't run in a shell, so there's no hook to fire, no
`Stop` event, and no tty to route to. agentfocus only sees agents you run in a terminal
(an integrated terminal counts).

## Hotkey and menu bar

**⌥⌘A** focuses the next waiting session from anywhere.

The menu-bar bell badges itself when something is waiting. Open it for the queue — each
waiting session shows as `<folder> (<terminal>, <age>m)`, click one to jump straight to it.
Below that: **Focus Next**, a **Start at Login** toggle, and **Quit**.

## Doctor

```sh
agentfocus doctor
```

Checks the install (CLI, hooks, adapters, `PATH`, helper app present and running) and the
host state that quietly breaks notifications: **Focus mode**, **Scheduled Summary**, a
quarantine flag on the helper bundle, and any *other* `Stop` hook that would post a
competing banner. It also always prints the note about Automation re-prompting after a
rebuild or upgrade.

It does not exercise a live focus round-trip. That's what `selftest/` is for:
`selftest/smoke-real.sh` for a scripted end-to-end, and `selftest/fresh-user.sh` for the
human-in-the-loop run on a brand-new macOS account.

## Uninstall

Brew:

```sh
brew uninstall agentfocus
```

Then clean up what lives in your home directory (either path):

```sh
rm -rf ~/Applications/AgentFocus.app          # quit it from the menu bar first
rm -rf ~/.local/share/agentfocus ~/.cache/agentfocus ~/Library/Logs/agentfocus
```

Finally remove the three `agentfocus` hook entries (`Stop`, `Notification`,
`UserPromptSubmit`) from `~/.claude/settings.json` — or just restore the
`settings.json.agentfocus-backup-*` that install day left next to it.

If you want the Automation grant gone too: System Settings → Privacy & Security →
Automation → AgentFocus.

## License

MIT
