#!/usr/bin/env bash
# Exit 0 if events.jsonl contains a successful notify for <id>.
set -euo pipefail

EVENTS="${HOME}/Library/Logs/agentfocus/events.jsonl"

if [ $# -lt 1 ] || [ -z "${1:-}" ]; then
  echo "FAIL check_notify: usage: check_notify.sh <id>" >&2
  exit 2
fi
ID="$1"

if [ ! -f "$EVENTS" ]; then
  echo "FAIL check_notify: no events file at $EVENTS" >&2
  exit 1
fi

# Prefer node for correct JSON parsing (no jq required).
if node -e '
  const fs = require("fs");
  const id = process.argv[1];
  const path = process.argv[2];
  const lines = fs.readFileSync(path, "utf8").split("\n").filter(Boolean);
  let found = false;
  for (const line of lines) {
    let o;
    try { o = JSON.parse(line); } catch { continue; }
    if (o.event === "notify" && o.id === id && o.ok === true) {
      found = true;
      console.log("PASS check_notify: notify ok id=" + id + " ts=" + o.ts + " detail=" + (o.detail || ""));
      break;
    }
  }
  if (!found) {
    console.error("FAIL check_notify: no notify+ok event for id=" + id + " in " + path);
    process.exit(1);
  }
' "$ID" "$EVENTS"; then
  exit 0
else
  exit 1
fi
