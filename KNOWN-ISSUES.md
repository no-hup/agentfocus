# Known Issues & Edge Cases

The framework relies on terminal OSC support and proper signal file ownership matching.

- **Terminal.app exact-tab focus not yet supported**: Terminal.app has no OSC 9/777 support. An adapter may be required in the future; PRs welcome.
- **JetBrains / Neovim / Zed**: Adapters for these environments are not yet built. Contributions welcome.
- **Warp / Stage-Manager / SSH-remote tmux / iTerm-restore**: Edge cases in these environments might interfere with correct routing.
- **Missing cleanup**: Stale signal files are currently not automatically cleaned up.
- **VS Code Extension OSC Parsing**: Currently relies on the signal file rather than native terminal OSC parsing.
- **Testing coverage**: Automated failure-mode tests are minimal.
