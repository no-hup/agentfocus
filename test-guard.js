#!/usr/bin/env node
const assert = require('assert');
const path = require('path');
const REGISTRY_DIR = path.join(process.env.HOME, '.local/share/agentfocus/registry');

// Simulate the sanitizer in emit.js
function testSanitizeAndTraverseGuard(sessionId) {
    if (!/^[a-zA-Z0-9_-]+$/.test(sessionId)) {
        return "rejected: invalid regex";
    }
    const registryPath = path.join(REGISTRY_DIR, `${sessionId}.json`);
    if (!registryPath.startsWith(REGISTRY_DIR)) {
        return "rejected: traversal";
    }
    return "ok";
}

assert.strictEqual(testSanitizeAndTraverseGuard("valid-id-123"), "ok", "valid id should pass");
assert.strictEqual(testSanitizeAndTraverseGuard("../../../etc/passwd"), "rejected: invalid regex", "traversal characters should be caught by regex");
assert.strictEqual(testSanitizeAndTraverseGuard("id; rm -rf /"), "rejected: invalid regex", "shell injection should be caught by regex");

console.log("PASS: Sanitizer and traversal guard self-check");
