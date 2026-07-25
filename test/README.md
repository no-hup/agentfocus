# Phase 0 Validation Harness

This harness contains the falsification cells to validate the "emit at the tty, route in the host" architecture before trusting it.

### Checklist

- [ ] `TODO(human)`: In an iTerm2 tab, run `printf '\e]9;test\a'` (or use `./osc-emit.sh $(tty)`). Does a clickable notification appear and does clicking focus that exact tab? (Enable iTerm's escape-sequence alerts if needed).
- [ ] `TODO(human)`: In a VS Code integrated terminal with the `wenbopan` extension, run the same emit. Does the notification click focus that exact terminal tab? Repeat with 3 windows × 2 tabs including two windows on the same folder.
- [ ] `TODO(human)`: **The decisive cell.** Under a live Claude TUI actively redrawing, have a hook run `./resolve-tty.sh` and write OSC 9/777 to it (or use `./osc-emit.sh $(./resolve-tty.sh)` from a subshell/background job). Verify: (A) host receives it, (B) notification fires without Accessibility permissions, (C) click focuses exact tab, (D) TUI never corrupts.
- [ ] `TODO(human)`: Repeat the above in tmux *without* `allow-passthrough`. Expect silence (documents the config requirement).
