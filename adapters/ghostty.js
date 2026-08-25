const { execSync } = require('child_process');
try {
    execSync(`osascript -e 'tell application "Ghostty" to activate'`);
} catch (e) {
    console.error(e.message);
    process.exit(1);
}
