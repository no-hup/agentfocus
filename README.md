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

You need two things first: **macOS 13 (Ventura) or newer** and **Node 18+** (the hooks and
CLI are Node — you have it if you installed Claude Code with npm; the native installer
does not bring it). `agentfocus init` checks both before it touches anything and tells you
which one is missing.

The menu-bar helper ships **prebuilt** — universal (Apple Silicon and Intel), with a
macOS 13 floor — so there is no compiler step. The Xcode Command Line Tools are needed
only if you build from source.

Then, one command:

```sh
npx agentfocus init
```

To upgrade, run the same thing again with `npx agentfocus@latest init`. `agentfocus doctor`
warns you when the installed runtime is older than the CLI.

Homebrew is planned but not live yet — see [MUST-DO.md](MUST-DO.md).

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
signature yet). macOS ties an Automation grant to the exact signature, so **upgrading to a
new version asks once more.** Re-running `init` on the same version does not: every user
of a release gets the identical binary, so the signature does not move. (A build from
source re-signs on every rebuild, so it re-prompts every time.) That's an accepted v1
tradeoff, not a bug — `agentfocus doctor` prints a reminder about it.

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

The menu-bar bell badges itself and shows **how many** agents are waiting, so you can read
the queue without opening anything. Open it and the first line is `N waiting · oldest Nm`;
below that each waiting session shows as `<folder> (<terminal>, <age>m)` — click one to
jump straight to it. Then: **Focus Next**, **Focus on Return**, a **Start at Login**
toggle, and **Quit**.

There is no "running" count, deliberately: a session that is not waiting might be working
or might have exited hours ago, and the registry cannot tell those two apart. Counting
them would mean guessing.

### Focus on Return

Walk away, come back, and the agent that has been waiting longest is already in front of
you. It fires once per return — after five minutes away — and only when you are actually
back: not at the lock screen, and not when another user is on the console. On by default;
turn it off from the menu.

It reads the system idle timer straight from the IO registry (the same number
`ioreg -c IOHIDSystem` prints), which needs no permission of any kind.

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

```sh
agentfocus uninstall           # add --purge to delete the logs too
```

That stops the helper, unregisters the login item, removes our three hook entries from
`~/.claude/settings.json` (backing it up first, and leaving every other hook alone), and
deletes `~/Applications/AgentFocus.app`, `~/.local/share/agentfocus` and
`~/.cache/agentfocus`. Everything AgentFocus creates lives in your home directory, so
that is the whole removal — no sudo, nothing left behind.

Two things it deliberately does not touch, and tells you so: the Automation grant
(System Settings → Privacy & Security → Automation → AgentFocus), and any
`integrations/` hooks you added by hand to another agent's config — it lists the
file paths instead of editing another tool's settings.

## License

MIT
