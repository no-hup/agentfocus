#!/usr/bin/env bash
# Checks the ONE piece of non-trivial logic in `agentfocus init`: the
# ~/.claude/settings.json merge must add our hooks exactly once, never
# duplicate on re-run, never touch a foreign hook, and be a byte-identical
# no-op the second time. Runs under a throwaway $HOME — touches nothing real.
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/.claude"
# Pre-existing foreign hooks, incl. a rival notifier on Stop, must survive.
cat > "$TMP/.claude/settings.json" <<'EOF'
{
  "hooks": {
    "Stop": [
      { "hooks": [ { "type": "command", "command": "node /somewhere/rival-notifier.js" } ] }
    ]
  }
}
EOF

run() { HOME="$TMP" AGENTFOCUS_SKIP_LAUNCH=1 "$SRC/bin/agentfocus" init >/dev/null; }

run
cp "$TMP/.claude/settings.json" "$TMP/after1.json"
run
cp "$TMP/.claude/settings.json" "$TMP/after2.json"

T="$TMP" node -e '
const fs = require("fs");
const assert = require("assert");
const T = process.env.T;
const a1 = fs.readFileSync(T + "/after1.json", "utf8");
const a2 = fs.readFileSync(T + "/after2.json", "utf8");
const s = JSON.parse(a1);
const count = (evt, needle) => JSON.stringify(s.hooks[evt]).split(needle).length - 1;

assert.strictEqual(count("Stop", "emit.js"), 1, "Stop should hold exactly one emit hook");
assert.strictEqual(count("Notification", "emit.js"), 1, "Notification should hold exactly one emit hook");
assert.strictEqual(count("UserPromptSubmit", "clear-waiting.js"), 1, "UserPromptSubmit should hold exactly one clear hook");
assert.strictEqual(count("Stop", "rival-notifier"), 1, "foreign Stop hook must survive untouched");
assert.strictEqual(a1, a2, "re-running init must leave settings.json byte-identical");
const backups = fs.readdirSync(T + "/.claude").filter(f => f.includes("agentfocus-backup"));
assert.strictEqual(backups.length, 1, "only the changing run may back up, got " + backups.length);
console.log("init-merge: ok");
'
