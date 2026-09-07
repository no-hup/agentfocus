#!/usr/bin/env bash
# Self-check for emit.js's osc_native decision.
#
# Getting this wrong is silent: mark a terminal osc_native and the helper posts
# nothing, on the promise that the terminal itself will — so a wrong `true` means
# no notification anywhere, with no error to notice. Runs the REAL hook under a
# throwaway $HOME with stub `open`/`osascript` on PATH, so nothing launches and
# no banner is posted.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/stub"
printf '#!/bin/sh\nexit 0\n' > "$TMP/stub/open"
printf '#!/bin/sh\nexit 0\n' > "$TMP/stub/osascript"
chmod +x "$TMP/stub/open" "$TMP/stub/osascript"
PASS=0; FAIL=0
NODE="$(command -v node)"   # $PATH is stubbed down to the stubs + system dirs

# emit <expected> <name> [VAR=VAL ...]
emit() {
  local want="$1" name="$2"; shift 2
  local id="oscselftest"
  rm -f "$TMP/.local/share/agentfocus/registry/$id.json"
  env -i HOME="$TMP" PATH="$TMP/stub:/usr/bin:/bin" "$@" \
    "$NODE" "$ROOT/hook/emit.js" <<< "{\"session_id\":\"$id\",\"cwd\":\"$TMP\"}" > /dev/null
  local got
  got="$("$NODE" -e "try{console.log(JSON.parse(require('fs').readFileSync('$TMP/.local/share/agentfocus/registry/$id.json','utf8')).osc_native)}catch(e){console.log('NO ROW')}")"
  if [ "$got" = "$want" ]; then PASS=$((PASS+1)); echo "PASS  $name → osc_native=$got";
  else FAIL=$((FAIL+1)); echo "FAIL  $name → osc_native=$got (expected $want)"; fi
}

emit true  "Ghostty"                      TERM_PROGRAM=ghostty GHOSTTY_RESOURCES_DIR=/x
emit true  "iTerm"                        TERM_PROGRAM=iTerm.app ITERM_SESSION_ID=w0t0p0:UUID
emit true  "kitty"                        TERM_PROGRAM=kitty KITTY_WINDOW_ID=1
emit false "Apple Terminal"               TERM_PROGRAM=Apple_Terminal
emit false "VS Code integrated terminal"  TERM_PROGRAM=vscode
# The regression this rule exists for: env inherited from the shell that launched
# the editor. The terminal renders no OSC, so the helper must stay the notifier.
emit false "VS Code launched from Ghostty" TERM_PROGRAM=vscode GHOSTTY_RESOURCES_DIR=/x
emit false "editor panel (no TERM_PROGRAM) with Ghostty env" \
      GHOSTTY_RESOURCES_DIR=/x VSCODE_GIT_ASKPASS_MAIN=/Applications/Visual\ Studio\ Code.app/x
# No editor_app and no terminal we know: env var is the only signal, so trust it.
emit true  "bare shell carrying Ghostty env" GHOSTTY_RESOURCES_DIR=/x

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
