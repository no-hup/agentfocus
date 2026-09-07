const { execSync } = require('child_process');
try {
    execSync(`osascript -e 'tell application "Ghostty" to activate'`);
} catch (e) {
    console.error(e.message);
    process.exit(1);
}

// App-level only: Ghostty exposes no scriptable per-tab identity, so the exact
// tab comes from its OWN OSC notification click, never from here. Report that
// honestly as the first token rather than letting bin/agentfocus auto-trust a
// silent adapter and log this as a clean hit (BUGS #3). Not "miss": the app is
// frontmost, and a miss would leave the session waiting forever.
process.stdout.write("degraded activate-only");
