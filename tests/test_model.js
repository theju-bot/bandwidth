const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const code = fs.readFileSync(path.join(__dirname, "../Model.js"), "utf8");
const ctx = {};
vm.createContext(ctx);
vm.runInContext(code, ctx);

const { formatBytes, formatSpeed, formatDate } = ctx;

// formatBytes tests
assert.strictEqual(formatBytes(0), "0 B");
assert.strictEqual(formatBytes(-10), "0 B");
assert.strictEqual(formatBytes(500), "500 B");
assert.strictEqual(formatBytes(1024), "1.0 KB");
assert.strictEqual(formatBytes(1536), "1.5 KB");
assert.strictEqual(formatBytes(10240), "10 KB");
assert.strictEqual(formatBytes(1048576), "1.0 MB");
assert.strictEqual(formatBytes(1073741824), "1.0 GB");
assert.strictEqual(formatBytes(1073741824 * 2.5, 2), "2.50 GB");

// formatSpeed tests
assert.strictEqual(formatSpeed(0), "0 B/s");
assert.strictEqual(formatSpeed(500), "500 B/s");
assert.strictEqual(formatSpeed(1024), "1.0 KB/s");
assert.strictEqual(formatSpeed(1048576), "1.0 MB/s");

// formatDate tests
assert.strictEqual(formatDate("2026-11-15", true), "Today");
assert.strictEqual(formatDate("2026-11-14", false), "Nov 14");
assert.strictEqual(formatDate("2026-01-01", false), "Jan 1");
assert.strictEqual(formatDate("", false), "");

console.log("All Model.js tests passed successfully.");
