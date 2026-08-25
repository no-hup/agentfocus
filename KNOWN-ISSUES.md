# Known Issues & Edge Cases

A few-percent error rate is acceptable by design — this file documents the known
edges so contributors can pick them off. Security/injection bugs are NOT on this
list: those are fixed in code (execFile everywhere, input validation), not tolerated.

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

## Surface coverage

- **Ghostty / WezTerm / kitty**: exact-tab focus comes from the terminal's own
  native OSC-notification click, not from a `focus-next` adapter — the Ghostty
  adapter only raises the app (best-effort) and `focus-next` won't pick the exact
  tab there. WezTerm/kitty have no focus adapter yet (identity is captured, unused).
- **iTerm2 exact-tab focus is unverified on hardware**: the adapter matches
  `id of session` against `ITERM_SESSION_ID`; this equivalence hasn't been proven
  on a real iTerm install. Terminal.app (tty) and Ghostty (OSC) are verified.
- **JetBrains / Neovim / Zed**: no adapters yet. Contributions welcome.
- **tmux / SSH-remote / devcontainers**: not bridged. Under tmux the outer app's
  tab tty may not match the pane pty; remote agents write the registry on the
  remote host while `osascript` runs locally. Treat as out of scope for now.
- **Cursor / Windsurf / VSCodium**: supported — emit.js captures the editor's
  `.app` name from the VS Code env and the adapter raises that fork (falls back to
  VS Code if it can't be determined).

## Other

- **Stale queue poison**: a session stuck `waiting` for up to `STALE_MS` (6h) can be
  picked by `focus-next` before newer ones. The `UserPromptSubmit` clear-waiting
  hook normally clears it on the next prompt.
- **Notification click needs the helper app**: banner clicks deep-link to
  `agentfocus focus <id>` only via the AgentFocus helper (helper/). Without it,
  the osascript fallback banner is dead-click (attributes to Script Editor).
- **`doctor` is install-health only**: checks binaries/adapters/hooks/PATH + waiting list.
  It does not exercise a live focus round-trip (use `selftest/smoke-real.sh` for that).
- **Automated failure-mode tests are minimal** beyond `selftest/smoke-real.sh`.
