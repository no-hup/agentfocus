#!/usr/bin/env bash
# Simulate notification click by invoking the SAME focus path the real
# agentfocus:// URL handler would call. Valid e2e for routing (not banner chrome).
#
# Real URL-scheme registration needs an app bundle + CFBundleURLTypes; that is
# intentionally NOT done here (see README). When the helper .app exists:
#   open "agentfocus://s/<id>"
# should resolve to the same `agentfocus focus --id <id>` call.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
CLI="${ROOT}/stub/agentfocus"

if [ $# -lt 1 ] || [ -z "${1:-}" ]; then
  echo "usage: sim-click.sh <id>" >&2
  exit 2
fi

ID="$1"
if [ ! -x "$CLI" ]; then
  echo "missing executable stub: $CLI" >&2
  exit 1
fi

exec "$CLI" focus --id "$ID"
