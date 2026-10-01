// Behavior tests for deepseek-peak/peak.js. Run with: node tests/test_logic.js
// Loaded and executed by tests/test_logic_node.py under pytest.
const fs = require("fs");
const path = require("path");
const assert = require("assert");

const src = fs.readFileSync(path.join(__dirname, "..", "deepseek-peak", "peak.js"), "utf8");
const Peak = new Function(
    src + "\nreturn { pad, formatHMS, isPeakAt, secondsUntilNext, isWeekendOffDay, isHoliday, fmtHM, windowLine, extractWindows, sameWindows, checkedInfo, scheduleWindows, scheduleText, providerName, providerProfiles, holidayDates, blockBounds, providerSnapshot, holidayRangeInfo };"
)();

// --- schedule.json <-> peak.js cross-check (single source of data) ---
const schedule = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "deepseek-peak", "schedule.json"), "utf8"));
assert.deepStrictEqual(
    Peak.scheduleWindows("deepseek").sort(),
    schedule.providers.deepseek.peakWindowsUtc.map(([a, b]) => a + "-" + b).sort()
);
assert.deepStrictEqual(
    Peak.scheduleWindows("ollama"),
    schedule.providers.ollama.peakWindowsUtc.map(([a, b]) => a + "-" + b)
);
assert.strictEqual(Peak.providerName("deepseek"), "DeepSeek");
assert.strictEqual(Peak.providerName("ollama"), "Ollama");
assert.strictEqual(Peak.providerProfiles().deepseek.weekendMode, "beijing-anchored");
assert.strictEqual(Peak.providerProfiles().ollama.weekendMode, "utc");
assert.deepStrictEqual(Peak.holidayDates(), schedule.holidays);

// --- formatHMS ---
assert.strictEqual(Peak.formatHMS(5025), "01:23:45");
assert.strictEqual(Peak.formatHMS(45), "00:00:45");
assert.strictEqual(Peak.formatHMS(0), "00:00:00");
assert.strictEqual(Peak.formatHMS(-5), "00:00:00");

// --- DeepSeek tier boundaries (2026-09-14 is a Monday) ---
const d = (s) => new Date(s);
assert.strictEqual(Peak.isPeakAt(d("2026-09-14T00:59:59Z"), "deepseek"), false);
assert.strictEqual(Peak.isPeakAt(d("2026-09-14T01:00:00Z"), "deepseek"), true);
assert.strictEqual(Peak.isPeakAt(d("2026-09-14T03:59:59Z"), "deepseek"), true);
assert.strictEqual(Peak.isPeakAt(d("2026-09-14T04:00:00Z"), "deepseek"), false);
assert.strictEqual(Peak.isPeakAt(d("2026-09-14T06:00:00Z"), "deepseek"), true);
assert.strictEqual(Peak.isPeakAt(d("2026-09-14T09:59:59Z"), "deepseek"), true);
assert.strictEqual(Peak.isPeakAt(d("2026-09-14T10:00:00Z"), "deepseek"), false);

// --- Ollama tier boundaries (single 12:00-18:00 UTC window) ---
assert.strictEqual(Peak.isPeakAt(d("2026-09-14T11:59:59Z"), "ollama"), false);
assert.strictEqual(Peak.isPeakAt(d("2026-09-14T12:00:00Z"), "ollama"), true);
assert.strictEqual(Peak.isPeakAt(d("2026-09-14T17:59:59Z"), "ollama"), true);
assert.strictEqual(Peak.isPeakAt(d("2026-09-14T18:00:00Z"), "ollama"), false);
// DeepSeek window and Ollama window must not bleed into each other
assert.strictEqual(Peak.isPeakAt(d("2026-09-14T13:00:00Z"), "deepseek"), false);
assert.strictEqual(Peak.isPeakAt(d("2026-09-14T02:00:00Z"), "ollama"), false);

// --- countdowns ---
assert.strictEqual(Peak.secondsUntilNext(d("2026-09-14T02:00:00Z"), "deepseek"), 7200);
assert.strictEqual(Peak.secondsUntilNext(d("2026-09-14T05:00:00Z"), "deepseek"), 3600);
assert.strictEqual(Peak.secondsUntilNext(d("2026-09-14T05:59:59Z"), "deepseek"), 1);
assert.strictEqual(Peak.secondsUntilNext(d("2026-09-14T11:00:00Z"), "ollama"), 3600);
assert.strictEqual(Peak.secondsUntilNext(d("2026-09-14T13:00:00Z"), "ollama"), 18000);

// --- DeepSeek weekend edges (Beijing-anchored) ---
assert.strictEqual(Peak.isPeakAt(d("2026-08-28T16:30:00Z"), "deepseek"), false);
assert.strictEqual(Peak.isPeakAt(d("2026-08-30T16:30:00Z"), "deepseek"), false);
assert.strictEqual(Peak.isWeekendOffDay(d("2026-08-29T12:00:00Z"), "beijing-anchored"), true);
assert.strictEqual(Peak.isWeekendOffDay(d("2026-09-14T12:00:00Z"), "beijing-anchored"), false);

// --- Ollama weekend edges (UTC) differ from DeepSeek ---
assert.strictEqual(Peak.isWeekendOffDay(d("2026-08-28T20:00:00Z"), "utc"), false);
assert.strictEqual(Peak.isWeekendOffDay(d("2026-08-29T12:00:00Z"), "utc"), true);
// Saturday 13:00Z: off-peak for Ollama, and for DeepSeek too (Beijing Sat)
assert.strictEqual(Peak.isPeakAt(d("2026-08-29T13:00:00Z"), "ollama"), false);
assert.strictEqual(Peak.isPeakAt(d("2026-08-29T13:00:00Z"), "deepseek"), false);

// --- DeepSeek Chinese public holidays (Beijing calendar) ---
assert.strictEqual(Peak.isHoliday(d("2026-10-01T02:00:00Z"), "deepseek"), true); // Beijing 10:00
assert.strictEqual(Peak.isPeakAt(d("2026-10-01T02:00:00Z"), "deepseek"), false); // normally peak
assert.strictEqual(Peak.isPeakAt(d("2026-10-01T06:30:00Z"), "deepseek"), false); // normally peak
assert.strictEqual(Peak.isHoliday(d("2026-10-08T02:00:00Z"), "deepseek"), false); // holiday over
assert.strictEqual(Peak.isPeakAt(d("2026-10-08T02:00:00Z"), "deepseek"), true);
// Makeup workdays stay weekends -> already off-peak; no double counting
assert.strictEqual(Peak.isHoliday(d("2026-09-20T02:00:00Z"), "deepseek"), false); // makeup Sunday
// Ollama never uses holidays
assert.strictEqual(Peak.isHoliday(d("2026-10-01T02:00:00Z"), "ollama"), false);
assert.strictEqual(Peak.isPeakAt(d("2026-10-01T13:00:00Z"), "ollama"), true); // Thursday
// Unknown years have no holidays: 2027-01-01 (Friday) is peak for DeepSeek
assert.strictEqual(Peak.isHoliday(d("2027-01-01T02:00:00Z"), "deepseek"), false);
assert.strictEqual(Peak.isPeakAt(d("2027-01-01T02:00:00Z"), "deepseek"), true);

// --- timezone conversion (no Intl; Beijing fixed +8) ---
const now = d("2026-09-14T05:00:00Z");
assert.strictEqual(Peak.fmtHM(now, 1, 0, "utc"), "01:00");
assert.strictEqual(Peak.fmtHM(now, 6, 0, "utc"), "06:00");
assert.strictEqual(Peak.fmtHM(now, 1, 0, "beijing"), "09:00");
assert.strictEqual(Peak.fmtHM(now, 6, 0, "beijing"), "14:00");
assert.strictEqual(Peak.fmtHM(now, 10, 0, "beijing"), "18:00");
assert.strictEqual(Peak.windowLine(d("2026-09-15T05:00:00Z"), "ollama", "utc"), "12:00-18:00");
assert.strictEqual(Peak.windowLine(d("2026-09-15T05:00:00Z"), "ollama", "beijing"), "20:00-02:00");
assert.strictEqual(Peak.windowLine(d("2026-08-29T12:00:00Z"), "ollama", "utc"), null); // weekend

// --- relative checked info (semantic, host translates) ---
const checkNow = 1758000000000;
assert.strictEqual(Peak.checkedInfo(checkNow, 0).key, "");
assert.strictEqual(Peak.checkedInfo(checkNow, checkNow - 30 * 1000).key, "checked.just-now");
const fiveMin = Peak.checkedInfo(checkNow, checkNow - 300 * 1000);
assert.strictEqual(fiveMin.key, "checked.minutes-ago");
assert.strictEqual(fiveMin.n, 5);
const threeHours = Peak.checkedInfo(checkNow, checkNow - 3 * 3600 * 1000);
assert.strictEqual(threeHours.key, "checked.hours-ago");
assert.strictEqual(threeHours.n, 3);
const old = Peak.checkedInfo(checkNow, checkNow - 30 * 3600 * 1000);
assert.strictEqual(old.key, "checked.date");
assert.match(old.text, /^\d{2}-\d{2} \d{2}:\d{2}$/);

// --- drift compare: wording changes must not flag, window changes must ---
const dsLive = "01:00 - 04:00 and 06:00 - 10:00 UTC, Monday through Friday (all other hours are off-peak).";
const dsBundled = "01:00-04:00, 06:00-10:00 UTC";
assert.strictEqual(Peak.sameWindows(Peak.extractWindows(dsLive), Peak.extractWindows(dsBundled)), true);
const changed = "02:00 - 05:00 and 06:00 - 10:00 UTC, Monday through Friday.";
assert.strictEqual(Peak.sameWindows(Peak.extractWindows(changed), Peak.extractWindows(dsBundled)), false);

// --- block bounds / progress / snapshots ---
const dsPeak = d("2026-09-14T02:00:00Z"); // 1h into the 01:00-04:00 window
const b = Peak.blockBounds(dsPeak, "deepseek");
assert.strictEqual(new Date(b.startMs).toISOString(), "2026-09-14T01:00:00.000Z");
assert.strictEqual(new Date(b.endMs).toISOString(), "2026-09-14T04:00:00.000Z");
const snap = Peak.providerSnapshot(dsPeak, "deepseek", null);
assert.strictEqual(snap.isPeak, true);
assert.strictEqual(snap.secondsToNext, 7200);
assert.strictEqual(Math.round(snap.progress * 3), 1); // 1 of 3 hours elapsed
// Cached block avoids a rescan and still ticks correctly
const snap2 = Peak.providerSnapshot(d("2026-09-14T03:30:00Z"), "deepseek", b);
assert.strictEqual(snap2.secondsToNext, 1800);
assert.strictEqual(Math.round(snap2.progress * 6), 5); // 2.5 of 3 hours
// Holiday block spans days: snapshot derives the countdown from the block end
const hol = Peak.blockBounds(d("2026-10-02T02:00:00Z"), "deepseek");
assert.strictEqual(Peak.isHoliday(d("2026-10-02T02:00:00Z"), "deepseek"), true);
assert.ok(hol.endMs > hol.startMs);
assert.ok(Peak.providerSnapshot(d("2026-10-02T02:00:00Z"), "deepseek", hol).secondsToNext > 0);
// Block bounds agree with the tier for both providers on a weekday
for (const provider of ["deepseek", "ollama"]) {
    for (const iso of ["2026-09-14T02:00:00Z", "2026-09-14T13:00:00Z", "2026-09-14T23:00:00Z"]) {
        const bb = Peak.blockBounds(d(iso), provider);
        assert.strictEqual(bb.isPeak, Peak.isPeakAt(d(iso), provider), provider + " " + iso);
        assert.ok(bb.startMs < d(iso).getTime() && bb.endMs > d(iso).getTime(), provider + " " + iso);
    }
}

// --- holiday range info (only current or within 7 days) ---
const duringHoliday = Peak.holidayRangeInfo(d("2026-10-02T02:00:00Z"), "deepseek");
assert.strictEqual(duringHoliday.active, true);
assert.strictEqual(new Date(duringHoliday.endMs).toISOString().substring(0, 10), "2026-10-07");
const beforeHoliday = Peak.holidayRangeInfo(d("2026-09-26T02:00:00Z"), "deepseek"); // 1 day before 09-27 holiday start
assert.ok(beforeHoliday && beforeHoliday.inDays <= 7);
const farFromHoliday = Peak.holidayRangeInfo(d("2026-06-01T02:00:00Z"), "deepseek"); // next: 06-19..21 (18 days) then 09-25
assert.strictEqual(farFromHoliday, null);
assert.strictEqual(Peak.holidayRangeInfo(d("2026-10-02T02:00:00Z"), "ollama"), null);

console.log("test_logic.js: all assertions passed");

