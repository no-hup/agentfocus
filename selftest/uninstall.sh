#!/usr/bin/env bash
# Checks `agentfocus uninstall` actually reverses `agentfocus init`: our hooks
# leave, FOREIGN hooks survive byte-identical, every directory we created is
# gone, and a second run is a clean no-op. Runs under a throwaway $HOME —
# touches nothing real.
set -uo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "PASS  $1"; }
bad()  { FAIL=$((FAIL+1)); echo "FAIL  $1"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got '$2', want '$3')"; fi; }

mkdir -p "$TMP/.claude"
# A rival notifier that must survive untouched, and a hook key we never manage.
cat > "$TMP/.claude/settings.json" <<'EOF'
{
  "hooks": {
    "Stop": [
      { "hooks": [ { "type": "command", "command": "node /somewhere/rival-notifier.js" } ] }
    ],
    "PreToolUse": [
      { "hooks": [ { "type": "command", "command": "node /somewhere/other.js" } ] }
    ]
  }
}
EOF
cp "$TMP/.claude/settings.json" "$TMP/original.json"

run() { HOME="$TMP" AGENTFOCUS_SKIP_LAUNCH=1 "$SRC/bin/agentfocus" "$@" >/dev/null 2>&1; }

run init
[ -d "$TMP/.local/share/agentfocus/hook" ] && ok "init staged the runtime" || bad "init staged the runtime"
check "init recorded its version" \
  "$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).version)' "$TMP/.local/share/agentfocus/config.json" 2>/dev/null)" \
  "$(node -e 'console.log(require(process.argv[1]).version)' "$SRC/package.json")"

# Fake the cache dir the VS Code adapter creates, so uninstall has one to remove.
mkdir -p "$TMP/.cache/agentfocus"

run uninstall
for d in ".local/share/agentfocus" "Applications/AgentFocus.app" ".cache/agentfocus"; do
  [ -e "$TMP/$d" ] && bad "removed $d" || ok "removed $d"
done
# Logs survive without --purge.
[ -d "$TMP/Library/Logs/agentfocus" ] && ok "kept logs (no --purge)" || bad "kept logs (no --purge)"

T="$TMP" node -e '
const fs = require("fs"), assert = require("assert"), T = process.env.T;
const s = JSON.parse(fs.readFileSync(T + "/.claude/settings.json", "utf8"));
const blob = JSON.stringify(s.hooks || {});
assert(!blob.includes("agentfocus"), "no agentfocus hook may remain");
assert(blob.includes("rival-notifier"), "foreign Stop hook must survive");
assert(blob.includes("other.js"), "unmanaged hook keys must survive");
assert(!("Notification" in s.hooks), "an empty key we created must be dropped");
assert.strictEqual(s.hooks.Stop.length, 1, "Stop keeps exactly the rival");
const b = fs.readdirSync(T + "/.claude").filter(f => f.includes("agentfocus-backup"));
assert.strictEqual(b.length, 2, "one backup from init, one from uninstall, got " + b.length);
' && ok "hooks: ours gone, foreign intact" || bad "hooks: ours gone, foreign intact"

# Second uninstall: no-op, exit 0, settings untouched.
cp "$TMP/.claude/settings.json" "$TMP/after1.json"
run uninstall; check "second uninstall exits 0" "$?" "0"
cmp -s "$TMP/.claude/settings.json" "$TMP/after1.json" && ok "second uninstall changed nothing" || bad "second uninstall changed nothing"

# --purge takes the logs too.
run init && run uninstall --purge
[ -e "$TMP/Library/Logs/agentfocus" ] && bad "--purge removed logs" || ok "--purge removed logs"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
