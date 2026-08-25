# AgentFocus: Identity Verification

This kit proves whether a completely detached agent lifecycle hook inherits the original terminal environment variables, which is the load-bearing pillar of the "Env-Var + Helper" design.

## Instructions

1. **Test the Mechanism (Headless)**
   Run the test script to prove env vars survive a double-fork `setsid` on macOS:
   ```bash
   ./test-setsid-env.sh
   ```

2. **Install the Probe**
   Install the hook into your Claude Code settings:
   ```bash
   ./install-probe.sh
   ```

3. **Run Real-World Tests**
   Open a new `claude` session in your terminals of choice (iTerm2, Ghostty, VS Code Integrated Terminal).
   Run a trivial command:
   ```
   > say hi
   ```
   When the turn ends, the Stop hook fires and dumps the env.

4. **Check the Results**
   After each test, run:
   ```bash
   ./check.sh
   ```
   This will report whether the hook successfully inherited a usable identity marker (e.g., `ITERM_SESSION_ID`).

5. **Clean Up**
   When done, remove the probe hook:
   ```bash
   ./uninstall-probe.sh
   ```
