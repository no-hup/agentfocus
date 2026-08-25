#!/usr/bin/env bash
set -e

export AGENT_SENTINEL_VAR="alive-and-well"

# Use python to simulate double fork and setsid, printing env to a temp file
TMP_ENV=$(mktemp)

python3 -c '
import os, sys, time

def daemonize():
    try:
        pid = os.fork()
        if pid > 0:
            sys.exit(0)
    except OSError as e:
        sys.exit(1)

    os.setsid()

    try:
        pid = os.fork()
        if pid > 0:
            sys.exit(0)
    except OSError as e:
        sys.exit(1)

    # Detached process
    with open(sys.argv[1], "w") as f:
        for k, v in os.environ.items():
            f.write(f"{k}={v}\n")
    sys.exit(0)

daemonize()
' "$TMP_ENV"

# Wait a brief moment for the daemon to write the file
sleep 0.5

if grep -q "AGENT_SENTINEL_VAR=alive-and-well" "$TMP_ENV"; then
    echo "PASS: Sentinel variable survived detachment."
    rm -f "$TMP_ENV"
    exit 0
else
    echo "FAIL: Sentinel variable did not survive."
    rm -f "$TMP_ENV"
    exit 1
fi
