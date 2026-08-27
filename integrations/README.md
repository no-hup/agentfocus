# AgentFocus integrations — other terminal coding agents

`hook/emit.js` is the frozen core: it takes a Claude-Code-shaped payload on stdin
(`{session_id, cwd, message}`) and does everything else from its own environment.
Everything here is a thin shim that translates another agent's native event into
that shape and pipes it in. Nothing in `hook/`, `bin/`, `adapters/` or `helper/`
is touched, and there are no dependencies.

| Tool | Fires on | What you get | Clears "waiting" on | Setup file |
|---|---|---|---|---|
| **Codex CLI** | `Stop`, `PermissionRequest` | banner / OSC + click-to-focus that exact tab | `UserPromptSubmit` | `~/.codex/hooks.json` |
| **Copilot CLI** | `agentStop`, `notification` (permission_prompt, elicitation_dialog, agent_idle) | same | `userPromptSubmitted` | `~/.copilot/hooks/agentfocus.json` |
| **Goose** | `Stop` | same (turn-complete only — no approval event exists) | `UserPromptSubmit` | `~/.agents/plugins/agentfocus/hooks/hooks.json` |
| **OpenCode** | `session.status` busy→idle, `permission.updated` | same | `chat.message` | `~/.config/opencode/plugins/agentfocus.js` |

Session ids are prefixed per tool (`codex-<id>`, `opencode-<id>`, …) and sanitized to
`[A-Za-z0-9_-]`, so they can never collide with Claude's own registry entries or escape
the registry directory. A tool that supplies no id falls back to a hash of the cwd.

---

## Codex CLI

Verified against <https://learn.chatgpt.com/docs/hooks> (codex-cli 0.149.0).
`Stop` and `PermissionRequest` both carry `session_id` and `cwd`, so the mapping is direct.
The `notify` key in `config.toml` is *not* used: its payload is undocumented in the current
config reference and it has no needs-input event.

Add to `~/.codex/hooks.json` — **merge with any hooks you already have, don't replace**:

```json
{
  "hooks": {
    "Stop": [{ "hooks": [{ "type": "command",
      "command": "node \"/Users/YOU/.local/share/agentfocus/integrations/shim.js\" codex notify",
      "timeout": 10 }] }],
    "PermissionRequest": [{ "hooks": [{ "type": "command",
      "command": "node \"/Users/YOU/.local/share/agentfocus/integrations/shim.js\" codex notify",
      "timeout": 10 }] }],
    "UserPromptSubmit": [{ "hooks": [{ "type": "command",
      "command": "node \"/Users/YOU/.local/share/agentfocus/integrations/shim.js\" codex clear",
      "timeout": 10 }] }]
  }
}
```

⚠ **Codex hooks are trust-gated and fail silently until approved.** Codex pins a
`trusted_hash` per hook in `~/.codex/config.toml`; a new or edited hook is *skipped* while
it prints `hook: Stop` / `hook: Stop Completed` as if it ran. After pasting the above, start
Codex and run **`/hooks`** to review and trust them. Editing the file later re-arms the gate.

## GitHub Copilot CLI

Verified against <https://docs.github.com/en/copilot/reference/hooks-reference>.
Note the payload is camelCase (`sessionId`, not `session_id`) and command entries use a
`"bash"` key rather than `"command"`.

New file `~/.copilot/hooks/agentfocus.json`:

```json
{
  "version": 1,
  "hooks": {
    "agentStop": [{ "type": "command",
      "bash": "node \"$HOME/.local/share/agentfocus/integrations/shim.js\" copilot notify",
      "timeoutSec": 10 }],
    "notification": [{ "type": "command",
      "bash": "node \"$HOME/.local/share/agentfocus/integrations/shim.js\" copilot notify",
      "timeoutSec": 10 }],
    "userPromptSubmitted": [{ "type": "command",
      "bash": "node \"$HOME/.local/share/agentfocus/integrations/shim.js\" copilot clear",
      "timeoutSec": 10 }]
  }
}
```

The `notification` event covers a lot more than "a human is blocked", so the shim only
reacts to `permission_prompt`, `elicitation_dialog` and `agent_idle`.

## Goose

Verified against <https://goose-docs.ai/blog/2026/05/14/goose-hooks/>. Goose uses the Open
Plugins spec: any `~/.agents/plugins/<name>/hooks/hooks.json` is auto-discovered at startup.
Payload uses `working_dir`, not `cwd`.

New file `~/.agents/plugins/agentfocus/hooks/hooks.json`:

```json
{
  "hooks": {
    "Stop": [{ "hooks": [{ "type": "command",
      "command": "node \"$HOME/.local/share/agentfocus/integrations/shim.js\" goose notify" }] }],
    "UserPromptSubmit": [{ "hooks": [{ "type": "command",
      "command": "node \"$HOME/.local/share/agentfocus/integrations/shim.js\" goose clear" }] }]
  }
}
```

## OpenCode

OpenCode has no shell hooks — plugins are JS modules auto-loaded from
`~/.config/opencode/plugins/`. Docs: <https://opencode.ai/docs/plugins/>.

New file `~/.config/opencode/plugins/agentfocus.js`:

```js
export { AgentFocus } from "/Users/YOU/.local/share/agentfocus/integrations/opencode-agentfocus.js"
```

---

## Limitations (measured, not guessed)

- **Codex** hooks are skipped until trusted via `/hooks` — see the warning above. This is the
  single most likely reason "nothing happens" after setup.
- **Goose** has no permission/approval event in its hook list, so you only get a
  turn-complete notification, never a "needs your approval" one. `BeforeShellExecution`
  exists but would fire on every shell command, which is noise, not a feature.
- **Copilot**'s `notification(permission_prompt)` is reported to fire even for tools already
  approved for the session (github/copilot-cli#2586), so expect some extra banners.
- **OpenCode** runs plugins inside its server process, so the terminal it focuses is the one
  OpenCode was *launched* from. `opencode serve` + `attach`, or the web UI, will resolve the
  wrong tty or none at all.
- OpenCode's documented `session.idle` event does **not** fire in 1.17.15 — the live signal is
  `session.status` with `status.type === "idle"`. Both are handled.
- A shim never fails the host: if it can't reach `node` or write the registry it gives up
  silently. A missed banner beats a blocked agent.

## Tests

```
node integrations/test-shims.js
```

Runs every shim against that tool's real doc-shaped payload under a throwaway `HOME`, and
asserts the registry entry, the `waiting` flag transitions, the field renames, the id
sanitizing and the noise filtering. See the top of this repo's report for what was
additionally verified live on real hardware.
