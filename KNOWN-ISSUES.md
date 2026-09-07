# Known Issues & Edge Cases

A few-percent error rate is acceptable by design — this file documents the known
edges so contributors can pick them off. Security/injection bugs are NOT on this
list: those are fixed in code (execFile everywhere, input validation), not tolerated.

The helper app is ad-hoc signed, so macOS re-asks for Automation once after each
version upgrade (the grant is keyed to the signature). Re-running `init` on the same
version does not re-prompt — released builds are identical bytes for every user — but a
build from source re-signs every time and so re-prompts every time. Expected, documented
behaviour (see README), not a bug report — `agentfocus doctor` prints a reminder.

## Correctness tradeoffs (deliberately deferred)

- **VS Code parallel-open race**: `AGENTFOCUS_VSCODE_ID` is rotated per terminal in
  `onDidOpenTerminal`. If several terminals are spawned faster than the extension
  maps+rotates, two can inherit the same id → a later focus lands on the wrong tab
  (reported as success). Rare with human-paced terminal opening; not mitigated yet.
  Fix would need a per-terminal env scope or a first-line pid→id probe.
- **Pre-existing / post-reload VS Code terminals are unfocusable**: env is fixed at
  shell start, so terminals opened before the extension activated (or before a
  window reload) never carry a real id and can't be matched. Recreate the terminal
  to make it focusable. (`persistent=false` is intentional — see extension.ts.)
- **`focus-request.json` is a single mailbox (last-writer-wins)**: if two VS Code
  sessions request focus within ~75ms, only the last is honored; the other is
  dropped. `focus-next` (which walks the registry) is unaffected. Fine for
  one-hotkey-press; a burst of simultaneous finishes can drop one.
- **Registry read-modify-write races**: a `Stop`/`Notification` emit and a
  `focus-next` can interleave with no file lock; worst case a `waiting` flag is
  briefly wrong. Self-heals on the next event.
- **Banners are suppressed for sessions that were already waiting when the helper
  started.** A helper that has just launched (upgrade, crash, login) treats everything
  already in the registry as already announced, so a restart cannot fire a burst of
  re-alerts — measured at 20 on this machine before the fix. Rows written in the last
  60 seconds are exempt, because `emit.js` writes the registry and *then* launches the
  helper and that banner is the point. Cost: if the helper dies and restarts in the same
  minute a genuinely new event lands, that one banner is lost; the menu-bar count and
  ⌥⌘A still show it.
- **`focus-next` still accepts a degraded adapter in its first pass.** Adapters now
  report `hit`/`miss`/`degraded` honestly, but the exact-only first pass only consults
  that for the editor fallback path, not for adapter-backed terminals — the adapter has
  already activated its app by the time we read the verdict, so refusing afterwards would
  just add a second app switch. A VS Code integrated-terminal session whose folder is
  closed can therefore still swallow the hotkey ahead of an exactly-focusable one.

## Event coverage

- **Subagent stops are not covered**: agentfocus hooks `Stop`, `Notification` and
  `UserPromptSubmit` only. A subagent finishing inside a session fires no banner —
  the parent session is still working, so from the registry's point of view nothing
  is waiting. Users who want subagent-level pings keep `claude-notifier` (or a
  similar `SubagentStop` hook) installed alongside; see the duplicate-banner note
  below for the cost of doing that.
- **Duplicate banners when another notifier is on `Stop`**: claude-notifier and
  hand-rolled `Stop` hooks post their own notification, so one event produces two
  banners — and only ours is click-routable (theirs attributes to Script Editor or
  terminal-notifier and dead-clicks). `agentfocus doctor` warns when it sees any
  `Stop` hook whose command doesn't mention agentfocus. Fix: scope the other hook
  to `SubagentStop` only, or remove it.

## Surface coverage

- **Ghostty / WezTerm / kitty**: exact-tab focus comes from the terminal's own
  native OSC-notification click, not from a `focus-next` adapter. The registry marks
  those sessions `osc_native: true`, which is what stops the helper from posting a
  second banner over the terminal's own. The Ghostty adapter only raises the app
  (best-effort), so `focus-next` and the hotkey won't pick the exact tab there.
  WezTerm/kitty have no focus adapter yet (identity is captured, unused).
- **iTerm2 exact-tab focus is unverified on hardware**: the adapter matches
  `id of session` against the UUID *suffix* of `ITERM_SESSION_ID` (the full
  `wNtMpK:UUID` form can never equal iTerm's bare-UUID id, so it always missed).
  The suffix equivalence still hasn't been proven on a real iTerm install.
  Terminal.app (tty) and Ghostty (OSC) are verified.
- **JetBrains / Neovim / Zed**: no adapters yet. Contributions welcome.
- **Cursor / Windsurf / VSCodium**: supported at **window level only** — emit.js
  captures the editor's `.app` name from the VS Code env and the adapter raises that
  fork's window for the project folder (falls back to VS Code if it can't be
  determined). It only ever passes `open` a folder the editor's own window state
  confirms is open (`adapters/editor_window.js`), because `open -a <editor> <folder>`
  SPAWNS a window for anything else; unconfirmed → app-level activate. Residual
  ceiling: closing a window doesn't rewrite that state, so a just-closed folder can
  still read as open. The `vscode-ext/` extension adds best-effort tab-exact focus
  on top, with the races listed above.
- **Editor panels are window-level only, and third-party panels not at all.**
  Claude Code's own VS Code panel *does* register (it runs the agent as a
  subprocess, so the hook fires) — it is in fact the most common kind of row. But
  it has no shell, so no tty and no terminal identity: the best any adapter can do
  is raise the right editor window for that folder, never a specific tab or panel.
  Panels belonging to other tools — Cursor Composer, Copilot Chat — fire no hook of
  ours at all and stay invisible.
- **tmux: pane ≠ tab**: inside tmux the tty we recover from the ancestor PID chain
  is the *pane* pty, which no Terminal.app tab has. The adapter reports `miss` and
  degrades to app-level activate, so you land in the right terminal app but not the
  right tab or pane. `TMUX_PANE` is captured in the registry but no adapter consumes
  it yet; a fix would route through `tmux select-window`/`select-pane` after the
  host tab is focused.
- **SSH-remote agents are not bridged**: the hook writes the registry on the *remote*
  host, while the helper and `osascript` run on your Mac — the local registry never
  sees the session and there is no local window to raise. Devcontainers have the same
  split. Out of scope for v1; would need a registry relay over the SSH connection.
- **Spaces / Stage Manager**: focus raises the target window, but whether you *see*
  it depends on macOS. If the window lives on another Space, the system honors
  "When switching to an application, switch to a Space with open windows"
  (System Settings → Desktop & Dock) — with that off you get the app activated but
  the window left on its own Space. Stage Manager can likewise keep the raised window
  off-stage. The click routes correctly either way; only the visual outcome varies.

## Other

- **Stale queue poison**: a session stuck `waiting` for up to `STALE_MS` (6h) can be
  picked by `focus-next` before newer ones. The `UserPromptSubmit` clear-waiting
  hook normally clears it on the next prompt.
- **Notification clicks come from the helper app**: the helper (`helper/`, installed
  to `~/Applications/AgentFocus.app`) is the normal notification path, not an
  optional extra. `emit.js` falls back to an `osascript` banner only when launching
  the helper fails outright — and that fallback banner is dead-click (it attributes
  to Script Editor).
- **`doctor` does not exercise a live round-trip**: it checks install health (CLI,
  hooks, adapters, PATH, helper present/running) plus host-state advisories (Focus
  mode, Scheduled Summary, quarantine xattr, competing `Stop` hooks). It never posts
  a banner or focuses anything — use `selftest/smoke-real.sh` for a scripted
  end-to-end, or `selftest/fresh-user.sh` on a clean macOS account.
- **Automated failure-mode tests are minimal** beyond `selftest/smoke-real.sh`.
