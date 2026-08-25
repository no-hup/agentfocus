#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

let input = '';
process.stdin.on('data', chunk => { input += chunk; });
process.stdin.on('end', () => {
    let payload = {};
    try {
        if (input.trim()) payload = JSON.parse(input);
    } catch(e) {}

    const sessionId = payload.session_id;
    if (!sessionId || !/^[a-zA-Z0-9_-]+$/.test(sessionId)) return;

    const registryDir = path.join(process.env.HOME, '.local/share/agentfocus/registry');
    const registryPath = path.join(registryDir, `${sessionId}.json`);
    
    if (fs.existsSync(registryPath) && registryPath.startsWith(registryDir)) {
        try {
            const data = JSON.parse(fs.readFileSync(registryPath, 'utf8'));
            data.waiting = false;
            data.ts = Date.now();
            const fd = fs.openSync(registryPath, 'w');
            fs.fchmodSync(fd, 0o600);
            fs.writeSync(fd, JSON.stringify(data, null, 2));
            fs.closeSync(fd);
        } catch(e) {}
    }
});
