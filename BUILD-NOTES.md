# Build Notes

- Updated `emit.js` to rely on the official Claude Code hooks schema and emit `terminalSequence` directly to stdout, eliminating raw TTY writes.
- Fixed path traversal in `session_id` to prevent arbitrary file writes.
- Hardened OSC output by stripping control characters and restricting string lengths.
- Fixed installer to correctly append hooks into the `Notification` and `Stop` lists non-destructively, supporting timestamped backups.
- Updated VS Code extension to implement pid-chain tracking, gating notifications by terminal ownership to fix multi-window fan-out issues, and resolving fs.watch raciness.
- Removed outdated `dispatch.sh`.

### TODO(human): Validation Steps
The owner must run the following manual tests on a real Mac before trusting the framework:
1. Run `test/README.md` Checklist item 1: `test/osc-emit.sh $(tty)` in iTerm2.
2. Run `test/README.md` Checklist item 2: Emit in VS Code integrated terminal.
4. Run `test/README.md` Checklist item 4: The tmux `allow-passthrough` test.
5. Publish the VS Code extension (`cd vscode-ext && npm install && vsce publish` / or test locally with F5).
