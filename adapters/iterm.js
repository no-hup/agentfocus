const { execSync } = require('child_process');
const data = JSON.parse(process.argv[2]);
const id = String(data.identity_handle || '');

// ITERM_SESSION_ID looks like "w0t0p0:UUID". Validate before interpolating so a
// hostile env value can't break out of the AppleScript string / inject a command.
if (!id || id === 'unknown' || !/^[A-Za-z0-9_.:-]+$/.test(id)) {
    try { execSync('osascript -', { input: 'tell application "iTerm" to activate' }); } catch {}
    process.stdout.write('miss(no-id)');
    process.exit(0);
}

// Feed the script on stdin (osascript -), never embed it in a shell string.
const script = `
tell application "iTerm"
  activate
  repeat with w in windows
    repeat with t in tabs of w
      repeat with s in sessions of t
        if id of s is "${id}" then
          select s
          select t
          set index of w to 1
          return "hit"
        end if
      end repeat
    end repeat
  end repeat
  return "miss"
end tell`;

try {
    const out = execSync('osascript -', { input: script, encoding: 'utf8' }).trim();
    process.stdout.write(out);
} catch (e) {
    console.error(e.message);
    process.exit(1);
}
