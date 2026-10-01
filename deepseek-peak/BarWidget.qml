import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

Item {
    id: root

    // Injected properties
    property var pluginApi: null
    property ShellScreen screen
    property string widgetId: ""
    property string section: ""
    property int sectionWidgetIndex: -1
    property int sectionWidgetsCount: 0

    // Settings
    readonly property var cfg: pluginApi?.pluginSettings || ({})
    readonly property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})

    readonly property string displayMode: cfg.displayMode ?? defaults.displayMode ?? "compact"
    readonly property color offPeakColor: cfg.offPeakColor ?? defaults.offPeakColor ?? "#4ade80"
    readonly property color peakColor: cfg.peakColor ?? defaults.peakColor ?? "#f87171"
    readonly property color driftColor: cfg.driftColor ?? defaults.driftColor ?? "#fbbf24"
    readonly property bool showTooltip: cfg.showTooltip ?? defaults.showTooltip ?? true
    readonly property string provider: (cfg.provider ?? defaults.provider ?? "deepseek") === "ollama" ? "ollama" : "deepseek"

    // Optional shared state from Main.qml: used for drift/progress only.
    // Tier/countdown are computed locally so the bar keeps working even if
    // Main is missing.
    readonly property var main: pluginApi?.mainInstance
    readonly property bool drift: main ? main.drift : false

    // Local schedule state (peak.js is inlined below; see tools/sync_peak.py)
    property bool isPeak: false
    property int secondsToNext: 0
    property int _ticks: 999
    property string _lastProvider: ""
    property var _block: null
    property real blockProgress: 0
    property string countdownText: formatHMS(0)
    property string stateText: ""
    property string tooltipFormat: ""

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

// Bounds of the current peak/off-peak block. Coarse 15-minute scan backwards
// (max 10 days) refined to the second. Peak blocks are hours long, so a
// 15-minute probe never skips a transition. Callers cache the result and
// recompute only when the tier changes or the block ends.
function blockBounds(now, provider) {
    var peak = isPeakAt(now, provider);
    var maxBack = 10 * 86400;
    var step = 900;
    var back = 0;
    for (var s = step; s <= maxBack; s += step) {
        if (isPeakAt(new Date(now.getTime() - s * 1000), provider) !== peak) {
            back = s;
            break;
        }
    }
    var startMs = now.getTime() - back * 1000;
    if (back > 0) {
        for (var t = back - (step - 1); t <= back; t++) {
            if (isPeakAt(new Date(now.getTime() - t * 1000), provider) !== peak) {
                // now - t is the last instant of the previous tier, so the
                // block starts one second later.
                startMs = now.getTime() - (t - 1) * 1000;
                break;
            }
        }
    }
    var forward = secondsUntilNext(now, provider);
    var endMs = forward > 0 ? now.getTime() + forward * 1000 : now.getTime() + maxBack * 1000;
    return {provider: provider, isPeak: peak, startMs: startMs, endMs: endMs};
}

// One provider's live state. `block` is the caller's cached blockBounds result;
// when it is still valid the countdown is derived from its end, avoiding a
// full forward scan every tick (holiday blocks can span a week).
function providerSnapshot(now, provider, block) {
    var peak = isPeakAt(now, provider);
    var b = block;
    if (!b || b.provider !== provider || b.isPeak !== peak || now.getTime() >= b.endMs) {
        b = blockBounds(now, provider);
    } else {
        return {
            isPeak: peak,
            secondsToNext: Math.max(0, Math.round((b.endMs - now.getTime()) / 1000)),
            onHoliday: isHoliday(now, provider),
            progress: (b.endMs - b.startMs) > 0 ? Math.min(1, Math.max(0, (now.getTime() - b.startMs) / (b.endMs - b.startMs))) : 0,
            block: b
        };
    }
    var total = b.endMs - b.startMs;
    return {
        isPeak: peak,
        secondsToNext: Math.max(0, Math.round((b.endMs - now.getTime()) / 1000)),
        onHoliday: isHoliday(now, provider),
        progress: total > 0 ? Math.min(1, Math.max(0, (now.getTime() - b.startMs) / total)) : 0,
        block: b
    };
}

function dateKeyToMs(key) {
    var parts = key.split("-");
    return Date.UTC(parseInt(parts[0], 10), parseInt(parts[1], 10) - 1, parseInt(parts[2], 10), 12);
}

function isNextDay(a, b) {
    return Math.round((dateKeyToMs(b) - dateKeyToMs(a)) / 86400000) === 1;
}

// Current or next Chinese holiday range (contiguous bundled dates), but only
// when it is active or starts within a week. Returns null otherwise.
function holidayRangeInfo(now, provider) {
    if (!getProfile(provider).holidayOffPeak)
        return null;
    var byYear = holidayDates();
    var all = [];
    for (var year in byYear)
        for (var i = 0; i < byYear[year].length; i++)
            all.push(byYear[year][i]);
    all.sort();
    var bj = new Date(now.getTime() + 8 * 3600 * 1000);
    var todayKey = bj.getUTCFullYear() + "-" + pad(bj.getUTCMonth() + 1) + "-" + pad(bj.getUTCDate());
    var todayMs = Date.UTC(bj.getUTCFullYear(), bj.getUTCMonth(), bj.getUTCDate());
    var idx = 0;
    while (idx < all.length && all[idx] < todayKey)
        idx++;
    if (idx >= all.length)
        return null;
    var start = idx;
    var end = idx;
    if (all[idx] === todayKey) {
        while (start - 1 >= 0 && isNextDay(all[start - 1], all[start]))
            start--;
        while (end + 1 < all.length && isNextDay(all[end], all[end + 1]))
            end++;
        return {active: true, startMs: dateKeyToMs(all[start]), endMs: dateKeyToMs(all[end]), inDays: 0};
    }
    while (end + 1 < all.length && isNextDay(all[end], all[end + 1]))
        end++;
    var inDays = Math.round((dateKeyToMs(all[start]) - todayMs) / 86400000);
    if (inDays > 7)
        return null;
    return {active: false, startMs: dateKeyToMs(all[start]), endMs: dateKeyToMs(all[end]), inDays: inDays};
}
// END peak.js (generated)

    // Per-screen bar properties (multi-monitor and vertical bar support)
    readonly property string screenName: screen?.name ?? ""
    readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
    readonly property bool isBarVertical: barPosition === "left" || barPosition === "right"
    readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)
    readonly property real barFontSize: Style.getBarFontSizeForScreen(screenName)

    readonly property color stateColor: drift ? driftColor : (isPeak ? peakColor : offPeakColor)

    // Content dimensions follow the bar capsule: the loader extends the
    // click area to full bar height, the visual stays at content size.
    readonly property real contentWidth: contentRow.implicitWidth + Style.marginM * 2
    readonly property real contentHeight: capsuleHeight

    implicitWidth: isBarVertical ? capsuleHeight : contentWidth
    implicitHeight: isBarVertical ? contentWidth : contentHeight

    function t(key, params) {
        return pluginApi?.tr(key, params);
    }
    function refreshTexts() {
        countdownText = formatHMS(secondsToNext);
        stateText = isPeak ? t("bar.peak") : t("bar.offPeak");
        tooltipFormat = providerName(provider) + " · " + (isPeak ? t("bar.tooltipPeak") : t("bar.tooltipOffPeak")) + " — " + t("bar.nextFlip") + " " + countdownText + (drift ? " — " + t("bar.driftSuffix") : "");
    }
    // Dual-provider tooltip grid (active provider marked with ●).
    function tooltipGrid() {
        var states = main ? main.providerStates : null;
        var rows = [];
        if (!states) {
            rows.push(["● " + providerName(provider), isPeak ? t("bar.tooltipPeak") : t("bar.tooltipOffPeak"), countdownText]);
            return rows;
        }
        var keys = ["deepseek", "ollama"];
        for (var i = 0; i < keys.length; i++) {
            var k = keys[i];
            var s = states[k];
            if (!s)
                continue;
            rows.push([
                (k === provider ? "● " : "○ ") + providerName(k),
                s.isPeak ? t("bar.tooltipPeak") : t("bar.tooltipOffPeak"),
                formatHMS(s.secondsToNext),
                Math.round(s.progress * 100) + "%"
            ]);
        }
        return rows;
    }
    function update() {
        var now = new Date();
        if (provider !== _lastProvider) {
            _lastProvider = provider;
            _ticks = 999;
        }
        isPeak = isPeakAt(now, provider);
        if (_ticks >= 30 || secondsToNext <= 1) {
            secondsToNext = secondsUntilNext(now, provider);
            _ticks = 0;
        } else {
            secondsToNext = Math.max(0, secondsToNext - 1);
            _ticks += 1;
        }
        // Progress comes from Main when available; local fallback otherwise.
        if (main && main.providerStates && main.providerStates[provider]) {
            blockProgress = main.providerStates[provider].progress;
        } else {
            var snap = providerSnapshot(now, provider, _block);
            _block = snap.block;
            blockProgress = snap.progress;
        }
        refreshTexts();
        if (mouseArea.containsMouse && showTooltip)
            TooltipService.show(root, tooltipGrid(), "auto");
    }

    Component.onCompleted: update()
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.update()
    }

    // Visual capsule - centered within the full click area
    Rectangle {
        id: visualCapsule
        x: Style.pixelAlignCenter(parent.width, width)
        y: Style.pixelAlignCenter(parent.height, height)
        width: root.contentWidth
        height: root.contentHeight
        radius: Style.radiusL
        color: mouseArea.containsMouse ? Qt.lighter(Style.capsuleColor, 1.12) : Style.capsuleColor
        border.color: mouseArea.containsMouse ? root.stateColor : Style.capsuleBorderColor
        border.width: Style.capsuleBorderWidth

        RowLayout {
            id: contentRow
            anchors.centerIn: parent
            spacing: Style.marginS

            NIcon {
                Layout.alignment: Qt.AlignVCenter
                icon: "circle-filled"
                color: root.stateColor
            }
            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                visible: root.displayMode !== "icon"
                spacing: Math.max(1, Math.round(1 * Style.uiScaleRatio))

                NText {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.displayMode === "full" ? root.stateText + " " + root.countdownText : root.countdownText
                    pointSize: root.barFontSize
                    color: Color.mOnSurface
                }
                NLinearGauge {
                    Layout.alignment: Qt.AlignHCenter
                    orientation: Qt.Horizontal
                    ratio: root.blockProgress
                    fillColor: root.stateColor
                    Layout.preferredWidth: 32 * Style.uiScaleRatio
                    Layout.preferredHeight: Math.max(2, Math.round(3 * Style.uiScaleRatio))
                }
            }
        }
    }

    // Right-click menu
    NPopupContextMenu {
        id: contextMenu
        model: [
            {
                "label": pluginApi?.tr("menu.useDeepSeek") + (root.provider === "deepseek" ? "  ✓" : ""),
                "action": "use-deepseek",
                "icon": "sparkles"
            },
            {
                "label": pluginApi?.tr("menu.useOllama") + (root.provider === "ollama" ? "  ✓" : ""),
                "action": "use-ollama",
                "icon": "circle-letter-o"
            },
            {
                "label": pluginApi?.tr("menu.refresh"),
                "action": "refresh",
                "icon": "refresh"
            },
            {
                "label": pluginApi?.tr("menu.settings"),
                "action": "settings",
                "icon": "settings"
            }
        ]
        onTriggered: action => {
            contextMenu.close();
            PanelService.closeContextMenu(screen);
            if (!pluginApi)
                return;
            if (action === "settings")
                BarService.openPluginSettings(screen, pluginApi.manifest);
            else if (action === "refresh") {
                if (pluginApi.mainInstance)
                    pluginApi.mainInstance.refresh();
            } else if (action === "use-deepseek" || action === "use-ollama") {
                pluginApi.pluginSettings.provider = action === "use-ollama" ? "ollama" : "deepseek";
                pluginApi.saveSettings();
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: {
            if (root.showTooltip && root.tooltipFormat !== "")
                TooltipService.show(root, root.tooltipFormat, "auto");
        }
        onExited: TooltipService.hide(root)
        onClicked: function (mouse) {
            TooltipService.hide(root);
            if (!pluginApi)
                return;
            if (mouse.button === Qt.LeftButton)
                pluginApi.togglePanel(root.screen, root);
            else if (mouse.button === Qt.RightButton)
                PanelService.showContextMenu(contextMenu, root, screen);
        }
    }
}
