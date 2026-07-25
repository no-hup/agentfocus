#!/usr/bin/env bash
# Emit OSC 9 and OSC 777 to a given tty
# Usage: ./osc-emit.sh <tty> [title] [message]

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <tty> [title] [message]"
    exit 1
fi

TTY="$1"
TITLE="${2:-agentfocus test}"
MSG="${3:-Test notification from OSC}"

if [ ! -w "$TTY" ]; then
    echo "Error: Cannot write to $TTY (or it doesn't exist)"
    exit 1
fi

# OSC 9 (iTerm2, standard)
printf "\e]9;%s\a" "$TITLE — $MSG" > "$TTY"

# OSC 777 (Ghostty/WezTerm/kitty may support it)
printf "\e]777;notify;%s;%s\a" "$TITLE" "$MSG" > "$TTY"

echo "Emitted OSC to $TTY. Did you see a notification?"
