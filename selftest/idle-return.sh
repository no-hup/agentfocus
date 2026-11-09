#!/usr/bin/env bash
# Focus-on-return: does walking back to the Mac surface the oldest waiting agent?
#
# Human-in-the-loop by necessity: "the user came back" means real keyboard/mouse
# input, and synthesising that would need Input Monitoring — a permission this
# product refuses to ask for. So you step away; the script reads the helper's log.
#
# Uses returnAfter=10 (seconds) instead of the 300 default so a run takes half a
# minute. Restores your setting on exit.
set -uo pipefail

LOG="$HOME/Library/Logs/agentfocus/helper.log"
REG="$HOME/.local/share/agentfocus/registry"
ID="agentfocus-selftest-idle-$$"
PASS=0; FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "PASS  $1"; else FAIL=$((FAIL+1)); echo "FAIL  $1"; echo "        expected: '$2'  actual: '$3'"; fi; }

restore() {
  rm -f "$REG/$ID.json"
  defaults delete com.agentfocus.helper returnAfter 2>/dev/null
  [ -n "${HAD_TOGGLE:-}" ] && defaults write com.agentfocus.helper focusOnReturn -bool "$HAD_TOGGLE"
  pkill -f 'AgentFocus.app/Contents/MacOS/AgentFocus' 2>/dev/null
  open -g "$HOME/Applications/AgentFocus.app"
  echo "restored your settings; helper relaunched"
}
trap restore EXIT

HAD_TOGGLE="$(defaults read com.agentfocus.helper focusOnReturn 2>/dev/null || echo "")"

arm() {  # a waiting session the helper can see; harmless target (no real tty)
  cat > "$REG/$ID.json" <<EOF
{"session_id":"$ID","term_program":"apple_terminal","osc_native":false,"identity_handle":"unknown",
 "tty":"/dev/ttys999","cwd":"$HOME","title":"idle-selftest","reason":"needs input","waiting":true,
 "ts":$(node -p 'Date.now()')}
EOF
}
fires() { grep -c "return from idle -> focus $ID" "$LOG" 2>/dev/null || echo 0; }

run_case() { # run_case <label> <toggle-on?> <expected-fires>
  defaults write com.agentfocus.helper returnAfter -float 10
  defaults write com.agentfocus.helper focusOnReturn -bool "$2"
  pkill -f 'AgentFocus.app/Contents/MacOS/AgentFocus' 2>/dev/null
  open -g "$HOME/Applications/AgentFocus.app"; sleep 3
  arm; local before; before="$(fires)"
  echo ""
  echo "  >>> HANDS OFF the keyboard and trackpad for 15 seconds. Starting now..."
  sleep 15
  echo "  >>> Now MOVE THE MOUSE, then wait 5 seconds."
  sleep 8
  check "$1" "$3" "$(( $(fires) - before ))"
}

returns() { grep -c "return from idle -> focus" "$LOG" 2>/dev/null || echo 0; }
clicks()  { grep -c "click $ID" "$LOG" 2>/dev/null || echo 0; }

# Returning to the Mac BY CLICKING A BANNER is one act, not two. The click is
# itself the input that ends the idle period, so before userFocus() consumed the
# idle edge the next poll fired a second, automatic focus at a DIFFERENT session
# ~instantly — and two window raises inside VS Code's 100ms open-file batch are
# merged into one untitled workspace, destroying both windows. Not a rare race:
# the guaranteed outcome of step away → agent finishes → come back and click.
run_click_case() {
  defaults write com.agentfocus.helper returnAfter -float 10
  defaults write com.agentfocus.helper focusOnReturn -bool true
  pkill -f 'AgentFocus.app/Contents/MacOS/AgentFocus' 2>/dev/null
  open -g "$HOME/Applications/AgentFocus.app"; sleep 3
  arm; local r0 c0; r0="$(returns)"; c0="$(clicks)"
  echo ""
  echo "  >>> A banner titled 'idle-selftest' should appear."
  echo "  >>> HANDS OFF for 15 seconds — do NOT dismiss it. Starting now..."
  sleep 15
  echo "  >>> Now CLICK THE BANNER (your first input must be that click), then wait."
  sleep 10
  check "banner click focuses once"                1 "$(( $(clicks)  - c0 ))"
  check "banner click fires NO auto focus-on-return" 0 "$(( $(returns) - r0 ))"
}

echo "=== focus-on-return ==="
run_case "toggle ON  → fires exactly once per return" true 1
run_case "toggle OFF → never fires"                   false 0
run_click_case

echo "---"; echo "$PASS passed, $FAIL failed"
echo "Not covered here (needs a second pair of eyes): locking the screen, waiting"
echo "past the threshold and unlocking must produce ONE line timestamped AFTER the"
echo "unlock and none while locked — sessionUsable() is what enforces that."
[ "$FAIL" -eq 0 ]
