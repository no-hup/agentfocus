# Known Issues & Edge Cases

A few-percent error rate is acceptable by design — this file documents the known
edges so contributors can pick them off. Security/injection bugs are NOT on this
list: those are fixed in code (execFile everywhere, input validation), not tolerated.

The helper app is ad-hoc signed, so macOS re-asks for Automation once after every
rebuild or upgrade. That is expected, documented behaviour (see README), not a bug
report — `agentfocus doctor` prints a reminder about it.

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
  `id of session` against `ITERM_SESSION_ID`; this equivalence hasn't been proven
  on a real iTerm install. Terminal.app (tty) and Ghostty (OSC) are verified.
- **JetBrains / Neovim / Zed**: no adapters yet. Contributions welcome.
- **Cursor / Windsurf / VSCodium**: supported at **window level only** — emit.js
  captures the editor's `.app` name from the VS Code env and the adapter raises that
  fork's window for the project folder (falls back to VS Code if it can't be
  determined). The `vscode-ext/` extension adds best-effort tab-exact focus on top,
  with the races listed above.
- **Editor-native agent panels are out of scope**: Cursor Composer, Copilot Chat,
  the VS Code Claude panel. They run no shell, so there is no hook to fire, no
  `Stop` event and no tty — nothing ever reaches the registry. Only agents run in a
  terminal (integrated terminals included) are visible to agentfocus.
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
