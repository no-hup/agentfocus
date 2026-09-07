# Bug list — navigation / focus correctness

**All items below are now implemented and machine-verified except #4 (iTerm2, code-only —
no iTerm on the dev machine).** Each entry keeps its original analysis and carries a
STATUS line. Residual ceilings are in KNOWN-ISSUES.md.

Ordered by user impact. Each entry: symptom → root cause → recommended fix →
side-effect notes. Evidence base: code read of the full chain (emit.js →
registry → helper → bin/agentfocus → adapters), events.jsonl / registry
cross-referencing, VS Code storage.json window state, and an independent
adversarial review that traced VS Code 1.135's own open-file handler.

---

## 1. Banner click opens a NEW VS Code window (confirmed; rate not established)

**STATUS: FIXED** — `adapters/editor_window.js` verifies the folder is really open before `open -a`; `git rev-parse` dropped. Checked by `selftest/editor-window.sh` (8/8 against live window state + synthetic fixtures).

**Symptom:** click a banner, a brand-new VS Code window opens instead of raising
the existing one.

**Root cause (proven in VS Code's own source):** the window-level fallback at
[bin/agentfocus:58-71](bin/agentfocus#L58-L71) runs `open -a <editor> <root>`.
That reaches Electron's open-file handler → `open({preferNewWindow: true})`;
with `window.openFoldersInNewWindow` at its default, VS Code opens a NEW window
whenever the folder isn't already open. The "already open" lookup compares URIs
without realpath, so `/tmp/x` vs `/private/tmp/x` and symlinked paths genuinely
miss. `<root>` is `git rev-parse --show-toplevel` of the session cwd, or raw cwd
when git fails (silent `catch {}` at :63). Miss classes: non-git cwd, git
worktree / nested repo, path-form mismatch.

**Rate:** happens, but the measured "~1-in-8" is over-claimed — the method
compares old clicks against *today's* window list, and some folders were plausibly
open at click time (backupWorkspaces evidence). Treat the rate as unknown.

**Who takes this path:** every session whose `term_program` isn't in
KNOWN_ADAPTERS — on this machine that's ~690 of 708 registry rows (`unknown` +
`editor_app`, i.e. VS Code panel sessions). This path is the norm, not an edge.

**Recommended fix (new file `adapters/editor_window.js`):** verify the target is
actually open before `open -a`, by reading the editor's own window state:
`~/Library/Application Support/<dir>/User/globalStorage/storage.json` →
`windowsState`. On a verified hit → `open -a` (now a pure raise). On a miss →
walk UP from cwd and take the first ancestor that IS an open folder (covers
repo-root, worktree, and subfolder cases — and lets us DROP `git rev-parse`
entirely, one less subprocess and silent catch). Still nothing → degrade to
app-level activate only (never `open -a` with a folder — that's the only call
that can spawn windows).

**Implementation traps (each one silently breaks the verifier into always-miss):**
- Support-dir name ≠ app name: "Visual Studio Code" → `Code`, "Code - Insiders"
  for Insiders, `Cursor` for Cursor. Needs an explicit map.
- `openedWindows` is only populated when >1 window is open; single-window state
  lives ONLY in `lastActiveWindow` (verified: Cursor's file has 0 openedWindows).
  Reading both is mandatory.
- Folder URIs are percent-encoded (`Application%20Support`); decode, realpath,
  and compare case-insensitively.
- A false miss is a REGRESSION, not status quo: most window-level clicks land
  correctly today via bare `open -a`. The fix must ship with a self-check that
  parses this machine's real storage.json and asserts the live folder list
  comes out.

**Residual ceiling:** closing a window doesn't trigger a state save, so a
just-closed folder can still read as open → new window anyway. Rare, no worse
than today; the guarantee is "almost never", not "impossible".

**Fallback philosophy (agreed):** when unsure, do LESS — verified navigate >
app-level activate > nothing. Never guess with a folder argument.

---

## 2. Multi-window VS Code: integrated-terminal click raises the WRONG window

**STATUS: FIXED** — `adapters/vscode.js` makes one guarded call into the verifier after activate; deepest-ancestor only, `$HOME` and `/` refused.

**Symptom:** several VS Code windows open, agent in window A, you're in window C.
Click → VS Code activates but the last-frontmost window stays on top.

**Root cause:** [adapters/vscode.js](adapters/vscode.js) only does app-level
`activate`; the extension's `term.show()` can't raise an OS window from a
background window. Nothing in the chain is window-aware, despite cwd being in
the registry. The adapter then reports implicit success (see #3).

**Recommended fix:** after activate, use #1's verifier and, on a verified hit,
`open -a <fork> <matched-open-folder>` to raise that window.

**Regression guard (important):** a wrong ancestor match can raise the WRONG
window — worse than today's activate-only, which at least keeps your last-used
window. Accept only the DEEPEST ancestor match, and refuse matches at `$HOME` or
`/`. This edits a frozen, machine-tested adapter: keep the edit to one guarded
call into the new file.

---

## 3. False success: fallback and fire-and-forget adapters clear `waiting` on failure

**STATUS: FIXED** — adapters now print their outcome as a first token (`hit` / `miss` / `degraded`) and the CLI logs `ok` from it, so an activate-only click is no longer recorded as a hit. `waiting` still clears on a degraded click, deliberately, so the banner cannot outlive it. Checked by `selftest/adapter-status.sh` (5/5). Residual: the exact-only first pass of `focus-next` still does not consult the verdict for adapter-backed terminals — see KNOWN-ISSUES.

**Symptom:** the buggy clicks of #1/#2 are logged `ok`, the session is marked
focused, the banner clears, focus-next skips it — success reported on the exact
clicks that failed.

**Root cause:** `open` exits 0 whether it raised or spawned
([bin/agentfocus:65](bin/agentfocus#L65)); adapters that print neither hit nor
miss are auto-trusted ([bin/agentfocus:88-89](bin/agentfocus#L88-L89)). This
class includes vscode.js AND ghostty.js.

**Recommended fix:** with #1's verifier, the fallback can report honest hit/miss
(the fallback is in-process — it returns false, it doesn't "print miss").

**Side effect to design around (not deniable):** an honest miss on a session we
can NEVER reach means the banner never clears — click, nothing happens, click
again, forever. Pair honest logging with clearing the banner after a degraded
activate (or an explicit dismiss); don't just leave it waiting.

---

## 4. iTerm2 exact-session match likely never fires

**STATUS: FIXED IN CODE, STILL UNVERIFIED ON HARDWARE** — `id.split(':').pop()`. No iTerm2 on this machine; needs one run on a real install.

**Symptom (predicted from code; no iTerm on this machine):** iTerm users always
get app-level activate, never the exact tab.

**Root cause:** [adapters/iterm.js](adapters/iterm.js) compares AppleScript
`id of session` (bare UUID) against the full `ITERM_SESSION_ID` (`w0t0p0:UUID`) —
can never match → always `miss`.

**Recommended fix:** `id.split(':').pop()` before comparing — safe whether or not
the prefix is present (the existing regex already validated the string), one line
inside the adapter. Verify once on real iTerm.

---

## 5. osc_native sessions can get NO notification anywhere

**STATUS: FIXED** — (a) doctor advisory per osc_native terminal; (b) `emit.js` trusts the env var only when it agrees with `term_program`. Checked by `selftest/osc-native.sh` (8/8).

Two related holes, same silent failure (helper stays quiet per
[helper/main.swift:106](helper/main.swift#L106), terminal doesn't notify either):

**(a) Terminal's OSC notifications disabled:** iTerm reportedly ships with OSC 9
off (asserted, NOT machine-tested — verify before acting). Recommended fix: a
doctor advisory line per detected terminal; zero code risk.

**(b) Inherited env vars lie about the terminal:**
[hook/emit.js:113-114](hook/emit.js#L113-L114) ORs raw env vars into
`osc_native` — launch VS Code from a Ghostty shell and every session inherits
`GHOSTTY_*`, marks itself osc_native, and VS Code's terminal never renders
OSC 9/777. No banner, no error. Code-path finding (zero such rows on this
machine today). Recommended fix: trust the env var only when it AGREES with
`term_program`. Small emit.js edit — frozen-core exception, worth it.

---

## 6. Stale-window mismatch: helper banners for 6h, editor fallback honours 30min

**STATUS: FIXED** — the 30-minute gate is gone; the verifier replaced the guess it was protecting against. Helper `staleMs` stays 6h and no longer bites, since a stale row can only reach a folder the editor currently has open.

**Symptom:** click a 40-minute-old editor-session banner → dead click.

**Root cause:** helper `staleMs` = 6h ([helper/main.swift:32](helper/main.swift#L32))
vs fallback `FRESH_MS` = 30min ([bin/agentfocus:57](bin/agentfocus#L57)).

**Recommended fix:** once #1's verifier exists the 30-min gate can go (it only
existed to avoid opening closed projects). **Ordering constraint:** fix #7/#8
FIRST — `agentfocus focus <id>` checks neither `waiting` nor age
([bin/agentfocus:107-119](bin/agentfocus#L107-L119)), so dropping the gate while
stale banners from previous helper runs still linger lets an hours-old banner
raise an old folder. Alternatively share one constant between helper and CLI.

---

## 7. Helper restart re-alerts every still-waiting session

**STATUS: FIXED** — `getDeliveredNotifications` seeds `notified` at launch, first poll gated on it. That alone was NOT enough: measured on this machine, a restart still fired 20 re-alerts, because dismissed banners are not delivered banners. The helper now also treats every session already waiting at launch as already announced (rows younger than 60s exempt, so `emit.js`'s write-then-launch still banners). Verified live: `seeded 0 delivered banner(s), 19 already-waiting` and zero re-posts; a freshly written row still banners.

**Symptom:** helper restart (upgrade, crash, login) → a burst of re-alerts.
(UN replaces same-identifier requests, so it's re-alerting, not duplicate rows.)

**Root cause:** dedupe cache `notified`
([helper/main.swift:31](helper/main.swift#L31)) is in-memory only; `agentfocus
init`'s deliberate quit/relaunch triggers this on every upgrade.

**Recommended fix:** seed `notified` from `getDeliveredNotifications` at launch.
**Race to handle:** that call is async and `poll()` runs immediately — gate the
first poll on its completion handler or the burst fires anyway.

---

## 8. Stale banners from a previous helper run are never cleared — and still navigate

**STATUS: FIXED** — same seed. Verified live: flipping a row to `waiting:false` clears its banner on the next poll.

**Symptom:** banners posted by a previous helper run sit in Notification Center
indefinitely; clicking one focuses a session that may be days old and no longer
waiting. Another wrong-navigation path.

**Root cause:** `poll()` only removes banners whose ids are in the in-memory
`notified` map ([helper/main.swift:124](helper/main.swift#L124)); a restart
orphans everything delivered before it.

**Recommended fix:** the same `getDeliveredNotifications` seed as #7 fixes both —
seeded ids that are no longer waiting get cleared on the first poll. One helper-
internal change, no new state files.

---

## 9. Security: extension writes to a predictable path in shared /tmp

**STATUS: FIXED** — the write moved to `~/.cache/agentfocus/last-focus.json` (mode 0700).

[vscode-ext/src/extension.ts:24](vscode-ext/src/extension.ts#L24) writes
`/tmp/agentfocus-last-focus.json`. On a multi-user Mac another user can
pre-create it as a symlink and the write follows it. Repo policy
(KNOWN-ISSUES) is that security bugs get fixed, not tolerated. It's debug-only
output: delete the write, or move it under `~/.cache/agentfocus`.

---

## 10. Lower-severity, tracked

**STATUS: PARTLY FIXED** — registry pruning (7-day mtime sweep in `emit.js`) and `editor_app` validation in the fallback are done. The `emit.js` editor_app scan order, the doctor hook-shape detection, and the tracked races are untouched.

- **Registry never pruned** — 708 files back to July; every focus-next parses
  all of them. Add an age-based sweep somewhere cheap (init or the helper).
- **Fallback passes `editor_app` to `open -a` unvalidated** while vscode.js
  validates the same value. No injection (execFileSync), just inconsistent —
  apply the same regex.
- **focus-request.json last-writer-wins**, **extension env-rotation race**,
  **registry read-modify-write races**, **tmux pane ≠ tab** — already in
  KNOWN-ISSUES; unchanged.
- **emit.js editor_app scan** takes the first `VSCODE_*` env var containing an
  `.app` path in arbitrary order — fine today; pin to a specific var if a fork
  ever diverges.
- **doctor hook detection** only recognises the `{command:'node', args:[...]}`
  shape; a hand-written string-command hook would be double-installed by init.
  Doctor warns; acceptable.

---

## Fix order (when implementation is approved)

1. **#7 + #8 first** (one helper-only change: getDeliveredNotifications seed,
   first poll gated on it). Independent, and it defuses the trap that #6's
   gate-removal would otherwise spring.
2. **#1 verifier** (`adapters/editor_window.js`, new file) with the trap list
   honoured and the storage.json self-check shipping alongside; wire the
   fallback to it. #3's honest-miss bookkeeping and #6's gate removal ride along.
3. **#2** — vscode.js makes one guarded call into the verifier (deepest-ancestor
   rule, refuse $HOME and /).
4. **#9** — delete or relocate the /tmp write (tiny, independent).
5. **#4 + #5(a)** — iTerm id fix + doctor advisory, verified together on real
   iTerm. **#5(b)** — env-vs-term_program agreement check in emit.js.

Each step independently shippable; none touches the verified Terminal.app path.
