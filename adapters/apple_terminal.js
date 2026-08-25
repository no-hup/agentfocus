const { execSync } = require('child_process');
const data = JSON.parse(process.argv[2]);
const tty = String(data.tty || '');

// Match the tab by its tty (a first-class Terminal.app property). The emit hook
// recovers the tty from the ancestor PID chain, so this is reliable even though
// Terminal.app can't be matched by TERM_SESSION_ID and doesn't expose OSC titles.
if (!/^\/dev\/tty[a-z0-9]+$/.test(tty)) {
    // No usable tty — best-effort activate.
    try { execSync(`osascript -e 'tell application "Terminal" to activate'`); } catch {}
    process.stdout.write('miss(no-tty)');
    process.exit(0);
}

const script = `
tell application "Terminal"
  set targetId to missing value
  repeat with w in windows
    repeat with t in tabs of w
      try
        if tty of t is "${tty}" then
          set selected of t to true
          set targetId to id of w
        end if
      end try
    end repeat
  end repeat
  if targetId is missing value then
    activate
    return "miss"
  end if
  -- Raise AFTER activate: activate alone restores the app's previous front
  -- window ordering, leaving the target window buried (seen on macOS 26).
  activate
  set frontmost of window id targetId to true
  return "hit"
end tell`;

try {
    const out = execSync('osascript -', { input: script, encoding: 'utf8' }).trim();
    process.stdout.write(out);
} catch (e) {
    console.error(e.message);
    process.exit(1);
}
