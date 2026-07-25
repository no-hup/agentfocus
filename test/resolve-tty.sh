#!/usr/bin/env bash
# Resolves the controlling tty of the current process via ancestor PID chain.
# Usage: ./resolve-tty.sh

set -euo pipefail

pid=$$

while [ "$pid" -gt 1 ]; do
    tty=$(ps -p "$pid" -o tty= | tr -d '[:space:]')
    
    if [ -n "$tty" ] && [ "$tty" != "??" ]; then
        echo "/dev/$tty"
        exit 0
    fi
    
    pid=$(ps -p "$pid" -o ppid= | tr -d '[:space:]')
done

echo "Could not resolve a TTY" >&2
exit 1
