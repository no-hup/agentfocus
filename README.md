# agentfocus

A local, permission-light, agent-agnostic tool to solve the "dead click" problem in AI coding agent sessions. When a backgrounded agent (like Claude Code) needs attention, clicking its notification instantly focuses the exact terminal tab/pane where it's running.

**NO network. NO telemetry. NO credentials. All routing is local IPC.**

## The Problem
Running multiple agents across VS Code integrated terminals, iTerm2 tabs, and Terminal.app windows leads to chaos. When a notification fires ("Agent needs input"), clicking it does nothing, leaving you hunting for the right window and tab.

## The Solution: Emit at the TTY, Route in the Host
Instead of fighting macOS window accessibility APIs (which requires heavy Screen Recording and Accessibility permissions and often focuses the wrong window), `agentfocus` uses an inverted architecture:

1. A lightweight hook runs inside the agent session.
2. It resolves its own controlling TTY (via ancestor PID chain).
3. It writes an OSC 9 / OSC 777 escape sequence directly to that TTY.
4. The terminal itself (iTerm2, Ghostty, kitty) or a host extension (VS Code) intercepts the sequence, posts a native OS notification, and focuses its own exact tab on click. Zero macOS permissions required!

## Features
- **Exact Tab Focus**: Opens the precise VS Code integrated terminal tab or iTerm2 pane.
- **Zero Heavy Permissions**: No Accessibility or Screen Recording permissions needed.
- **Agent-Agnostic**: Any CLI that can run a hook (Claude Code, Codex, Gemini) can use it.
- **Same-CWD Disambiguation**: Uses the unique TTY, not just the folder name.

## Installation & Usage

This is a brew-first structured CLI/hook install that works standalone with zero extensions for native terminals.

1. Clone this repository.
2. Run `./install.sh` to safely merge the hook into your `~/.claude/settings.json` non-destructively.
3. Run `./install.sh doctor` to check host support and see per-terminal setup instructions.

### Per-Terminal Requirements
- **iTerm2**: Enable escape sequence alerts in Advanced settings.
- **tmux**: Add `set -g allow-passthrough on` to your `.tmux.conf`.
- **VS Code**: Install the optional companion extension in `vscode-ext/` (or use the `wenbopan.vscode-terminal-osc-notifier` extension) for exact integrated-terminal tab focus.
- **Terminal.app**: Uses a built-in AppleScript fallback (requires a one-time Automation prompt).

## Architecture & Optional VS Code Extension
For terminals like Ghostty, WezTerm, and kitty, `agentfocus` relies entirely on native OSC support.
For VS Code, the optional companion extension (`vscode-ext/`) watches a lightweight signal file (`~/.cache/agentfocus/`) and uses the VS Code terminal API to focus the exact tab based on the TTY PID chain. 

## License
MIT
