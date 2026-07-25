#!/usr/bin/env node
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');
const assert = require('assert');

console.log("Running self-check for emit.js...");
const cacheDir = path.join(os.homedir(), '.cache', 'agentfocus');

// Test 1: Normal operation and OSC sanitization
const sessionId = 'test-session-' + Date.now();
const payload1 = JSON.stringify({
    session_id: sessionId,
    cwd: process.cwd(),
    hook_event_name: 'Notification',
    message: 'Testing fallback \x1b[31mwith control chars\x07\n\n'
});

try {
    const out1 = execSync(`node ./hook/emit.js`, { input: payload1, encoding: 'utf8' });
    
    // Check OSC sanitization
    const outJson = JSON.parse(out1);
    assert(outJson.terminalSequence, 'Must emit terminalSequence');
    assert(!outJson.terminalSequence.includes('\x1b[31m'), 'Control characters should be stripped from message');
    assert(!outJson.terminalSequence.includes('\n'), 'Newlines should be stripped');
    
    // Check signal file
    const stateFile = path.join(cacheDir, `${sessionId}.json`);
    assert(fs.existsSync(stateFile), 'Signal file should be created');
    
    const data = JSON.parse(fs.readFileSync(stateFile, 'utf8'));
    assert.strictEqual(data.session_id, sessionId, 'Session ID should match');
    assert(!data.message.includes('\n'), 'Message in signal file should be sanitized too');
    
    fs.unlinkSync(stateFile);
    console.log("PASS: Normal emit and OSC sanitization.");
} catch (e) {
    console.error("FAIL: Normal emit", e);
    process.exit(1);
}

// Test 2: Path traversal rejection
const maliciousSessionId = '../test-traversal-escape-' + Date.now();
const maliciousFile = path.join(cacheDir, '..', maliciousSessionId + '.json');
const payload2 = JSON.stringify({
    session_id: maliciousSessionId,
    cwd: process.cwd(),
    hook_event_name: 'Notification',
    message: 'Testing traversal'
});

try {
    execSync(`node ./hook/emit.js`, { input: payload2, encoding: 'utf8' });
    
    // It should have defaulted to 'default.json'
    const defaultFile = path.join(cacheDir, 'default.json');
    assert(fs.existsSync(defaultFile), 'Signal file should fallback to default.json');
    assert(!fs.existsSync(maliciousFile), 'Malicious path traversal must be rejected');
    
    fs.unlinkSync(defaultFile);
    console.log("PASS: Path traversal rejected.");
} catch (e) {
    console.error("FAIL: Path traversal check", e);
    process.exit(1);
}

console.log("All self-checks passed!");
