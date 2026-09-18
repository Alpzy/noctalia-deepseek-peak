// Behavior tests for deepseek-peak/peak.js. Run with: node tests/test_logic.js
// Loaded and executed by tests/test_logic_node.py under pytest.
const fs = require("fs");
const path = require("path");
const assert = require("assert");

const src = fs.readFileSync(path.join(__dirname, "..", "deepseek-peak", "peak.js"), "utf8");
const Peak = new Function(
    src + "\nreturn { pad, formatHMS, isPeakAt, secondsUntilNext, isWeekendOffDay, fmtHM, windowLine, extractWindows, sameWindows, checkedInfo, scheduleWindows, scheduleText };"
)();

// --- schedule.json <-> peak.js cross-check (single source of data) ---
const schedule = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "deepseek-peak", "schedule.json"), "utf8"));
const jsonWindows = schedule.peakWindows.map(([a, b]) => a + "-" + b).sort();
assert.deepStrictEqual(Peak.scheduleWindows().map(([a, b]) => a + "-" + b).sort(), jsonWindows);
assert.deepStrictEqual(Peak.extractWindows(Peak.scheduleText()), jsonWindows);
assert.strictEqual(schedule.weekendOffPeak.timezone, "Asia/Shanghai");

// --- formatHMS ---
assert.strictEqual(Peak.formatHMS(5025), "01:23:45");
assert.strictEqual(Peak.formatHMS(45), "00:00:45");
assert.strictEqual(Peak.formatHMS(0), "00:00:00");
assert.strictEqual(Peak.formatHMS(-5), "00:00:00");

// --- tier boundaries (weekday, 2026-09-14 is a Monday) ---
const monotonic = (s) => new Date(s);
assert.strictEqual(Peak.isPeakAt(monotonic("2026-09-14T00:59:59Z"), "beijing-anchored"), false);
assert.strictEqual(Peak.isPeakAt(monotonic("2026-09-14T01:00:00Z"), "beijing-anchored"), true);
assert.strictEqual(Peak.isPeakAt(monotonic("2026-09-14T03:59:59Z"), "beijing-anchored"), true);
assert.strictEqual(Peak.isPeakAt(monotonic("2026-09-14T04:00:00Z"), "beijing-anchored"), false);
assert.strictEqual(Peak.isPeakAt(monotonic("2026-09-14T06:00:00Z"), "beijing-anchored"), true);
assert.strictEqual(Peak.isPeakAt(monotonic("2026-09-14T09:59:59Z"), "beijing-anchored"), true);
assert.strictEqual(Peak.isPeakAt(monotonic("2026-09-14T10:00:00Z"), "beijing-anchored"), false);

// --- countdowns ---
assert.strictEqual(Peak.secondsUntilNext(monotonic("2026-09-14T02:00:00Z"), "beijing-anchored"), 7200);
assert.strictEqual(Peak.secondsUntilNext(monotonic("2026-09-14T05:00:00Z"), "beijing-anchored"), 3600);
assert.strictEqual(Peak.secondsUntilNext(monotonic("2026-09-14T05:59:59Z"), "beijing-anchored"), 1);

// --- Beijing-anchored weekend edges ---
assert.strictEqual(Peak.isPeakAt(monotonic("2026-08-28T16:30:00Z"), "beijing-anchored"), false); // Fri 16:00Z -> weekend
assert.strictEqual(Peak.isPeakAt(monotonic("2026-08-30T16:30:00Z"), "beijing-anchored"), false); // Sun after 16:00Z -> Monday Beijing
assert.strictEqual(Peak.isWeekendOffDay(monotonic("2026-08-29T12:00:00Z"), "beijing-anchored"), true);
assert.strictEqual(Peak.isWeekendOffDay(monotonic("2026-09-14T12:00:00Z"), "beijing-anchored"), false);

// --- utc weekend mode differs at the edges ---
assert.strictEqual(Peak.isWeekendOffDay(monotonic("2026-08-28T20:00:00Z"), "utc"), false); // Friday UTC is a weekday
assert.strictEqual(Peak.isPeakAt(monotonic("2026-09-14T02:00:00Z"), "utc"), true);

// --- timezone conversion (no Intl; Beijing fixed +8) ---
const now = monotonic("2026-09-14T05:00:00Z");
assert.strictEqual(Peak.fmtHM(now, 1, 0, "utc"), "01:00");
assert.strictEqual(Peak.fmtHM(now, 6, 0, "utc"), "06:00");
assert.strictEqual(Peak.fmtHM(now, 1, 0, "beijing"), "09:00");
assert.strictEqual(Peak.fmtHM(now, 6, 0, "beijing"), "14:00");
assert.strictEqual(Peak.fmtHM(now, 10, 0, "beijing"), "18:00");

// --- drift compare: wording changes must not flag, window changes must ---
const live = "01:00 - 04:00 and 06:00 - 10:00 UTC, Monday through Friday (all other hours are off-peak).";
const bundled = "01:00-04:00, 06:00-10:00 UTC";
assert.strictEqual(Peak.sameWindows(Peak.extractWindows(live), Peak.extractWindows(bundled)), true);
const changed = "02:00 - 05:00 and 06:00 - 10:00 UTC, Monday through Friday.";
assert.strictEqual(Peak.sameWindows(Peak.extractWindows(changed), Peak.extractWindows(bundled)), false);

// --- relative checked info (semantic, host translates) ---
const checkNow = 1758000000000;
assert.strictEqual(Peak.checkedInfo(checkNow, 0).key, "");
assert.strictEqual(Peak.checkedInfo(checkNow, checkNow - 30 * 1000).key, "checked.justNow");
const fiveMin = Peak.checkedInfo(checkNow, checkNow - 300 * 1000);
assert.strictEqual(fiveMin.key, "checked.minutesAgo");
assert.strictEqual(fiveMin.n, 5);
const threeHours = Peak.checkedInfo(checkNow, checkNow - 3 * 3600 * 1000);
assert.strictEqual(threeHours.key, "checked.hoursAgo");
assert.strictEqual(threeHours.n, 3);
const old = Peak.checkedInfo(checkNow, checkNow - 30 * 3600 * 1000);
assert.strictEqual(old.key, "checked.date");
assert.match(old.text, /^\d{2}-\d{2} \d{2}:\d{2}$/);

console.log("test_logic.js: all assertions passed");
