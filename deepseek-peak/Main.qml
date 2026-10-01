import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

// Shared state owner: schedule math, the policy-drift checker, and the
// translated display strings rendered by BarWidget.qml and Panel.qml.
// Both components read this instance through pluginApi.mainInstance.
Item {
    id: root
    property var pluginApi: null

    readonly property var cfg: pluginApi?.pluginSettings || ({})
    readonly property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})

    // Active tariff provider. DeepSeek is the historical default; Ollama
    // applies the peak window for the DeepSeek models on its cloud.
    readonly property string provider: (cfg.provider ?? defaults.provider ?? "deepseek") === "ollama" ? "ollama" : "deepseek"
    readonly property string providerLabel: providerName(provider)
    readonly property bool autoCheck: cfg.autoCheck ?? defaults.autoCheck ?? true
    readonly property bool offlineOnly: cfg.offlineOnly ?? defaults.offlineOnly ?? false
    readonly property int checkIntervalH: cfg.checkIntervalH ?? defaults.checkIntervalH ?? 6
    readonly property string customSourceUrl: cfg.customSourceUrl ?? defaults.customSourceUrl ?? ""
    readonly property string profileSourceUrl: getProfile(provider).sourceUrl
    readonly property string sourceUrl: customSourceUrl !== "" ? customSourceUrl : profileSourceUrl
    readonly property var fallbackUrls: getProfile(provider).fallbackUrls
    property int checkTimeoutMs: 10000

    property bool isPeak: false
    property int secondsToNext: 0
    property bool onHoliday: false
    property bool drift: false
    property double checkedAtMs: 0
    property var nowDate: new Date()
    property int _ticks: 999

    // Display strings rebuilt every tick so late-arriving translations are used.
    property string countdownHMS: formatHMS(0)
    property string panelStateText: ""
    property string countdownLabel: ""
    property string localLine: ""
    property string utcLine: ""
    property string beijingLine: ""
    property string costText: ""
    property string checkedText: ""
    property string driftText: ""

    // BEGIN peak.js (generated - edit peak.js and run tools/sync_peak.py)
// Shared pure logic for the AI peak/off-peak widget.
//
// Data source of truth: deepseek-peak/schedule.json (provider profiles and
// the bundled Chinese public holidays). tools/sync_peak.py regenerates the
// marked block below from that file and inlines the whole body into
// Main.qml, BarWidget.qml and Panel.qml. Never hand-edit generated blocks.
//
// Providers:
//  - deepseek: peaks 01:00-04:00 + 06:00-10:00 UTC Mon-Fri; weekends and
//    Chinese public holidays are off-peak all day (Beijing calendar).
//  - ollama:   peak 12:00-18:00 UTC Mon-Fri; weekends (UTC) off-peak all day
//    (DeepSeek models on Ollama Cloud).
//
// JS day convention: Date.getUTCDay() Sun=0..Sat=6 (differs from Python
// datetime.weekday() Mon=0..Sun=6 used in tests/test_schedule.py).

    // BEGIN schedule.json (generated - edit schedule.json and run tools/sync_peak.py)
function providerProfiles() { return ({"deepseek": {"name": "DeepSeek", "peakWindowsUtc": [["01:00", "04:00"], ["06:00", "10:00"]], "weekendMode": "beijing-anchored", "holidayOffPeak": true, "sourceUrl": "https://api-docs.deepseek.com/quick_start/pricing/", "fallbackUrls": ["https://api-docs.deepseek.com/quick_start/pricing/", "https://www.deepseek.com/en/pricing"]}, "ollama": {"name": "Ollama", "peakWindowsUtc": [["12:00", "18:00"]], "weekendMode": "utc", "holidayOffPeak": false, "sourceUrl": "https://ollama.com/pricing", "fallbackUrls": ["https://ollama.com/pricing", "https://docs.ollama.com/cloud"]}}); }
function holidayDates() { return ({"2025": ["2025-01-01", "2025-01-28", "2025-01-29", "2025-01-30", "2025-01-31", "2025-02-01", "2025-02-02", "2025-02-03", "2025-02-04", "2025-04-04", "2025-04-05", "2025-04-06", "2025-05-01", "2025-05-02", "2025-05-03", "2025-05-04", "2025-05-05", "2025-05-31", "2025-06-01", "2025-06-02", "2025-10-01", "2025-10-02", "2025-10-03", "2025-10-04", "2025-10-05", "2025-10-06", "2025-10-07", "2025-10-08"], "2026": ["2026-01-01", "2026-01-02", "2026-01-03", "2026-02-15", "2026-02-16", "2026-02-17", "2026-02-18", "2026-02-19", "2026-02-20", "2026-02-21", "2026-02-22", "2026-02-23", "2026-04-04", "2026-04-05", "2026-04-06", "2026-05-01", "2026-05-02", "2026-05-03", "2026-05-04", "2026-05-05", "2026-06-19", "2026-06-20", "2026-06-21", "2026-09-25", "2026-09-26", "2026-09-27", "2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04", "2026-10-05", "2026-10-06", "2026-10-07"]}); }
    // END schedule.json (generated)

function pad(n) {
    return (n < 10 ? "0" : "") + n;
}

function providerName(provider) {
    return getProfile(provider).name;
}

function getProfile(provider) {
    var profiles = providerProfiles();
    return profiles[provider] || profiles.deepseek;
}

function toMinutes(hhmm) {
    var parts = hhmm.split(":");
    return parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10);
}

// Canonical peak windows as "HH:MM-HH:MM" strings, for drift comparison.
function scheduleWindows(provider) {
    var wins = getProfile(provider).peakWindowsUtc;
    var out = [];
    for (var i = 0; i < wins.length; i++)
        out.push(wins[i][0] + "-" + wins[i][1]);
    return out;
}

function scheduleText(provider) {
    return scheduleWindows(provider).join(", ") + " UTC";
}

function formatHMS(s) {
    s = Math.max(0, Math.floor(s));
    return pad(Math.floor(s / 3600)) + ":" + pad(Math.floor((s % 3600) / 60)) + ":" + pad(s % 60);
}

// Chinese public holidays are dates on the Beijing calendar (DeepSeek bills
// off-peak all day on those dates). Providers without holidayOffPeak never
// match. Unknown years simply have no holidays.
function isHoliday(date, provider) {
    if (!getProfile(provider).holidayOffPeak)
        return false;
    var bj = new Date(date.getTime() + 8 * 3600 * 1000);
    var year = String(bj.getUTCFullYear());
    var key = year + "-" + pad(bj.getUTCMonth() + 1) + "-" + pad(bj.getUTCDate());
    var days = holidayDates()[year];
    return !!days && days.indexOf(key) !== -1;
}

function isWeekendOffDay(date, weekendMode) {
    if (weekendMode === "utc") {
        var uDay = date.getUTCDay();
        return uDay === 0 || uDay === 6;
    }
    var bjDay = new Date(date.getTime() + 8 * 3600 * 1000).getUTCDay();
    return bjDay === 0 || bjDay === 6;
}

function isPeakAt(date, provider) {
    var profile = getProfile(provider);
    if (isWeekendOffDay(date, profile.weekendMode))
        return false;
    if (isHoliday(date, provider))
        return false;
    var minutes = date.getUTCHours() * 60 + date.getUTCMinutes();
    var wins = profile.peakWindowsUtc;
    for (var i = 0; i < wins.length; i++) {
        if (minutes >= toMinutes(wins[i][0]) && minutes < toMinutes(wins[i][1]))
            return true;
    }
    return false;
}

// Two-phase scan: coarse 60s steps to find the flip minute, then 1s refine
// inside that minute. Second-exact, ~228 iterations max instead of up to 10080.
function secondsUntilNext(date, provider) {
    var peak = isPeakAt(date, provider);
    var coarse = 0;
    for (var s = 60; s <= 7 * 86400; s += 60) {
        var d = new Date(date.getTime() + s * 1000);
        if (isPeakAt(d, provider) !== peak) {
            coarse = s;
            break;
        }
    }
    if (coarse === 0)
        return 0;
    for (var t = coarse - 59; t <= coarse; t++) {
        var e = new Date(date.getTime() + t * 1000);
        if (isPeakAt(e, provider) !== peak)
            return t;
    }
    return coarse;
}

// tz: "utc" | "beijing" | "local". Local uses the engine's local timezone at
// the given date (DST-correct); no Intl needed (Qt QML lacks Intl options).
function fmtHM(now, hour, minute, tz) {
    if (tz === "utc")
        return pad(hour) + ":" + pad(minute);
    if (tz === "beijing")
        return pad((hour + 8) % 24) + ":" + pad(minute);
    var d = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate(), hour, minute, 0));
    return pad(d.getHours()) + ":" + pad(d.getMinutes());
}

// null = weekend: the host shows its localized "off-peak all day".
function windowLine(now, provider, tz) {
    var profile = getProfile(provider);
    if (isWeekendOffDay(now, profile.weekendMode))
        return null;
    var wins = profile.peakWindowsUtc;
    var parts = [];
    for (var i = 0; i < wins.length; i++) {
        var a = wins[i][0].split(":");
        var b = wins[i][1].split(":");
        parts.push(fmtHM(now, parseInt(a[0], 10), parseInt(a[1], 10), tz) + "-" + fmtHM(now, parseInt(b[0], 10), parseInt(b[1], 10), tz));
    }
    return parts.join(" · ");
}

// Semantic relative "last checked" info: the host translates `key` with
// `{n}`. Keys live in deepseek-peak/i18n/*.json under "checked".
function checkedInfo(nowMs, checkedMs) {
    if (!checkedMs)
        return {key: "", n: 0, text: ""};
    var diff = Math.max(0, Math.floor((nowMs - checkedMs) / 1000));
    if (diff < 60)
        return {key: "checked.justNow", n: 0, text: ""};
    if (diff < 3600)
        return {key: "checked.minutesAgo", n: Math.floor(diff / 60), text: ""};
    if (diff < 86400)
        return {key: "checked.hoursAgo", n: Math.floor(diff / 3600), text: ""};
    var d = new Date(checkedMs);
    return {
        key: "checked.date",
        n: 0,
        text: pad(d.getMonth() + 1) + "-" + pad(d.getDate()) + " " + pad(d.getHours()) + ":" + pad(d.getMinutes())
    };
}

// Window-set compare for policy drift: wording/spacing changes on the official
// page must not flag; only a real change of the HH:MM windows does.
function extractWindows(text) {
    var out = [];
    var re = /(\d{2}:\d{2})\s*-\s*(\d{2}:\d{2})/g;
    var m;
    while ((m = re.exec(text)) !== null)
        out.push(m[1] + "-" + m[2]);
    return out.sort();
}

function sameWindows(a, b) {
    if (a.length !== b.length)
        return false;
    for (var i = 0; i < a.length; i++)
        if (a[i] !== b[i])
            return false;
    return true;
}
// END peak.js (generated)

    function t(key, params) {
        return pluginApi?.tr(key, params);
    }

    function lineFor(tz) {
        var w = windowLine(root.nowDate, root.provider, tz);
        return w === null ? t("panel.weekendAllDay") : w;
    }
    function refreshTexts() {
        countdownHMS = formatHMS(secondsToNext);
        panelStateText = isPeak ? t("panel.peak") : t("panel.offPeak");
        countdownLabel = isPeak ? t("panel.offPeakIn") : t("panel.peakIn");
        localLine = t("panel.local") + "    " + lineFor("local");
        utcLine = t("panel.utc") + "      " + lineFor("utc");
        beijingLine = t("panel.beijing") + "  " + lineFor("beijing");
        costText = t("panel.cost");
        var ci = checkedInfo(root.nowDate.getTime(), root.checkedAtMs);
        var relative = (ci.key !== "" && ci.key !== "checked.date") ? t(ci.key, {n: ci.n}) : ci.text;
        checkedText = t("panel.checked") + "   " + relative;
        driftText = t("panel.drift");
    }
    function update() {
        var now = new Date();
        nowDate = now;
        isPeak = isPeakAt(now, provider);
        onHoliday = isHoliday(now, provider);
        if (_ticks >= 30 || secondsToNext <= 1) {
            secondsToNext = secondsUntilNext(now, provider);
            _ticks = 0;
        } else {
            secondsToNext = Math.max(0, secondsToNext - 1);
            _ticks += 1;
        }
        refreshTexts();
    }

    // --- Policy-drift checker -------------------------------------------------
    // Window extraction: DeepSeek states "Peak hours are 01:00 - 04:00 ..." and
    // Ollama states "Off-peak pricing apply outside 12:00 and 18:00 UTC on
    // weekdays". Both reduce to the same HH:MM set we compare against.
    function windowsFromPage(text) {
        var m = text.match(/Peak hours are ([^<]+)/);
        if (m)
            return extractWindows(m[1]);
        var o = text.match(/outside\s+([0-9]{2}:[0-9]{2})\s+and\s+([0-9]{2}:[0-9]{2})\s+UTC/i);
        if (o)
            return [o[1] + "-" + o[2]];
        return null;
    }
    function tryUrl(idx, urls) {
        if (idx >= urls.length)
            return;
        var xhr = new XMLHttpRequest();
        var settled = false;
        function fail() {
            if (!settled) {
                settled = true;
                tryUrl(idx + 1, urls);
            }
        }
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE || settled)
                return;
            if (xhr.status === 200) {
                settled = true;
                var found = windowsFromPage(xhr.responseText);
                if (found && !sameWindows(found, extractWindows(scheduleText(provider)))) {
                    drift = true;
                    ToastService.showNotice(t("notice.policyChanged"), found.join(", ") + " UTC");
                } else if (found) {
                    // DeepSeek bundles holidays; warn if the page stops saying so.
                    drift = provider === "deepseek" && !/holiday/i.test(xhr.responseText);
                }
                checkedAtMs = Date.now();
                refreshTexts();
            } else {
                fail();
            }
        };
        try {
            xhr.timeout = checkTimeoutMs;
        } catch (e) {}
        try {
            xhr.ontimeout = fail;
        } catch (e2) {}
        try {
            xhr.open("GET", urls[idx]);
            xhr.send();
        } catch (e3) {
            fail();
        }
    }
    function checkDrift() {
        if (!autoCheck || offlineOnly)
            return;
        var urls = [sourceUrl];
        for (var i = 0; i < fallbackUrls.length; i++) {
            if (urls.indexOf(fallbackUrls[i]) === -1)
                urls.push(fallbackUrls[i]);
        }
        tryUrl(0, urls);
    }

    Component.onCompleted: update()

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.update()
    }
    // First check shortly after startup, then every checkIntervalH hours.
    Timer {
        interval: 30000
        running: true
        repeat: false
        onTriggered: root.checkDrift()
    }
    Timer {
        interval: Math.max(1, root.checkIntervalH) * 3600000
        running: root.autoCheck && !root.offlineOnly
        repeat: true
        onTriggered: root.checkDrift()
    }

    IpcHandler {
        target: "plugin:deepseek-peak"

        function refresh(): string {
            root.checkDrift();
            return "policy check triggered";
        }
        function status(): string {
            return (root.isPeak ? "peak" : "off-peak") + " · " + root.countdownHMS + (root.drift ? " · drift" : "");
        }
    }
}
