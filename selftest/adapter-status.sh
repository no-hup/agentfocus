#!/usr/bin/env bash
# Does bin/agentfocus read an adapter's outcome correctly?
#
# Why this exists: BUGS #3 — an adapter that only activated the app was logged as
# a clean hit, so the buggy clicks reported success. Adapters now print their
# outcome as the FIRST token (hit | miss | degraded) and the CLI logs `ok`
# accordingly. That is a branch, so it gets a check.
#
# Runs entirely under a throwaway $HOME with stub adapters: no app is activated,
# no real registry is touched, no Aqua session needed.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CLI="$REPO/bin/agentfocus"
PASS=0; FAIL=0
check() { # check <name> <expected> <actual>
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "PASS  $1";
  else FAIL=$((FAIL+1)); echo "FAIL  $1"; echo "        expected: '$2'"; echo "        actual:   '$3'"; fi
}

H="$(mktemp -d)"; trap 'rm -rf "$H"' EXIT
REG="$H/.local/share/agentfocus/registry"
ADP="$H/.local/share/agentfocus/adapters"
mkdir -p "$REG" "$ADP"

# One stub adapter per case, named for a term_program the CLI already routes
# (ghostty.js), so no KNOWN_ADAPTERS edit is needed to exercise this.
say() { printf '#!/usr/bin/env node\nprocess.stdout.write(%s);\n' "$1" > "$ADP/ghostty.js"; }

row() { # row <id>
  cat > "$REG/$1.json" <<EOF
{"session_id":"$1","term_program":"ghostty","identity_handle":"x","cwd":"$H","title":"t","waiting":true,"ts":$(node -p 'Date.now()')}
EOF
}

# result <id> → "<exit>|<ok>|<detail>|<waiting>" from the CLI's own event log
result() {
  HOME="$H" node "$CLI" focus "$1" >/dev/null 2>&1; local rc=$?
  HOME="$H" node -e '
    const fs=require("fs"),p=process.env.HOME;
    const l=fs.readFileSync(p+"/Library/Logs/agentfocus/events.jsonl","utf8").trim().split("\n");
    const e=JSON.parse(l[l.length-1]);
    const w=JSON.parse(fs.readFileSync(p+"/.local/share/agentfocus/registry/"+process.argv[1]+".json","utf8")).waiting;
    process.stdout.write(`'"$rc"'|${e.ok}|${e.detail}|${w}`);
  ' "$1"
}

say "'hit window-level /Users/x/proj'";  row a; check "hit → ok:true, waiting cleared"        "0|true|hit window-level /Users/x/proj|false" "$(result a)"
say "'degraded activate-only'";          row b; check "degraded → ok:FALSE, waiting cleared"  "0|false|degraded activate-only|false"        "$(result b)"
say "'miss(no-tty)'";                    row c; check "miss → ok:false, STAYS waiting"        "1|false|miss(no-tty)|true"                   "$(result c)"
say "''";                                row d; check "silent adapter → old benefit of doubt" "0|true|ok|false"                             "$(result d)"
# A folder whose name contains a status word must not change the verdict — this is
# why the CLI reads the first token instead of matching anywhere in the output.
say "'hit window-level /Users/x/degraded-proj'"; row e
check "path containing 'degraded' still ok:true" "0|true|hit window-level /Users/x/degraded-proj|false" "$(result e)"

echo "---"; echo "$PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
