#!/usr/bin/env node
/**
 * Hook Emitter for agentfocus
 * Reads hook JSON from stdin and emits an OSC notification via stdout terminalSequence.
 */

const fs = require('fs');
const path = require('path');
const os = require('os');

const APP_NAME = 'agentfocus';
const CACHE_DIR = path.join(os.homedir(), '.cache', APP_NAME);

// Enforce CACHE_DIR 0700
fs.mkdirSync(CACHE_DIR, { recursive: true, mode: 0o700 });

let inputData = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => { inputData += chunk; });
process.stdin.on('end', () => {
    let payload;
    try { payload = JSON.parse(inputData); } catch (e) { payload = {}; }

    let sessionId = payload.session_id;
    if (typeof sessionId !== 'string' || !/^[A-Za-z0-9._-]{1,128}$/.test(sessionId)) {
        sessionId = 'default';
    }

    const stateFile = path.join(CACHE_DIR, `${sessionId}.json`);
    const resolvedStateFile = path.resolve(stateFile);
    const resolvedCacheDir = path.resolve(CACHE_DIR);
    if (!resolvedStateFile.startsWith(resolvedCacheDir + path.sep) && resolvedStateFile !== resolvedCacheDir) {
        process.exit(0);
    }

    const cwd = payload.cwd || process.cwd();
    const projectName = path.basename(cwd);
    
    const eventName = payload.hook_event_name || 'unknown';
    const messageRaw = payload.message || `Agent event: ${eventName}`;
    const titleRaw = projectName;

    const sanitize = (str, isOsc777) => {
        if (!str) return '';
        let s = str.replace(/[\x00-\x1f\n]/g, '');
        if (isOsc777) s = s.replace(/;/g, ':');
        return s.substring(0, 200);
    };

    const title9 = sanitize(titleRaw, false);
    const msg9 = sanitize(messageRaw, false);
    const title777 = sanitize(titleRaw, true);
    const msg777 = sanitize(messageRaw, true);

    const osc9 = `\x1b]9;${title9} — ${msg9}\x07`;
    const osc777 = `\x1b]777;notify;${title777};${msg777}\x07`;

    process.stdout.write(JSON.stringify({
        terminalSequence: osc9 + osc777
    }) + '\n');

    const timestamp = Date.now();
    const signalData = {
        session_id: sessionId,
        cwd: cwd,
        pid: process.pid,
        title: title9,
        message: msg9,
        timestamp: timestamp
    };
    
    try {
        const fd = fs.openSync(resolvedStateFile, 'w', 0o600);
        fs.fchmodSync(fd, 0o600);
        fs.writeSync(fd, JSON.stringify(signalData));
        fs.closeSync(fd);
    } catch (e) {}
});
