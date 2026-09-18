import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

Item {
    id: root
    property ShellScreen screen
    property var pluginApi

    // Widget properties passed from Bar.qml for per-instance settings
    property string widgetId: ""
    property string section: ""
    property int sectionWidgetIndex: -1
    property int sectionWidgetsCount: 0

    // Per-screen bar properties (multi-monitor + vertical bar support)
    readonly property string screenName: screen?.name ?? ""
    readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
    readonly property bool isBarVertical: barPosition === "left" || barPosition === "right"
    readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)
    readonly property real barFontSize: Style.getBarFontSizeForScreen(screenName)

    // Display settings live in pluginSettings (Settings panel saves them);
    // readSettings() refreshes them every tick since plain-JS settings
    // objects don't emit change notifiers for QML bindings.
    property string displayMode: "compact"
    property color offPeakColor: "#4ade80"
    property color peakColor: "#f87171"
    property color driftColor: "#fbbf24"
    property bool showTooltip: true
    property string weekendMode: "beijing-anchored"
    // Drift checker settings (checker lives here so it runs whenever the
    // widget is on the bar, not only while the panel is open).
    property bool autoCheck: true
    property bool offlineOnly: false
    property int checkIntervalH: 6
    property string customSourceUrl: ""
    readonly property string sourceUrl: customSourceUrl !== "" ? customSourceUrl : "https://api-docs.deepseek.com/quick_start/pricing/"
    readonly property var fallbackUrls: ["https://api-docs.deepseek.com/quick_start/pricing/", "https://www.deepseek.com/en/pricing"]
    property int checkTimeoutMs: 10000
    // Drift is shared with the panel via pluginSettings (in-memory only,
    // never persisted). Offline-first: the bar renders from the bundled
    // schedule regardless; drift only tints amber.
    property bool drift: (pluginApi?.pluginSettings?.drift ?? false)
    property bool isPeak: false
    property int secondsToNext: 0
    property int _ticksSinceCalc: 999
    // Text is (re)built in update() so late-arriving translations are picked up.
    property string stateText: ""
    property string tooltipFormat: ""
    property string countdownText: formatHMS(secondsToNext)

    // Content dimensions follow the bar capsule: the loader extends the
    // click area to full bar height, the visual stays at content size.
    readonly property real contentWidth: contentRow.implicitWidth + Style.marginM * 2
    readonly property real contentHeight: capsuleHeight

    implicitWidth: contentWidth
    implicitHeight: contentHeight

    // BEGIN peak.js (generated - edit peak.js and run tools/sync_peak.py)
// Shared pure logic for the DeepSeek peak/off-peak widget.
// Mirrors deepseek-peak/schedule.json (peak 01:00-04:00 + 06:00-10:00 UTC,
// Mon-Fri; weekend off-peak anchored to Beijing Sat/Sun = Fri 16:00Z-Sun 16:00Z).
//
// Single source of truth: tools/sync_peak.py inlines this file's body between
// the generated markers in BarWidget.qml and Panel.qml (the Noctalia v4 plugin
// loader cannot resolve relative .js imports from plugin QML).
//
// JS day convention: Date.getUTCDay() Sun=0..Sat=6 (differs from Python
// datetime.weekday() Mon=0..Sun=6 used in tests/test_schedule.py).

function pad(n) {
    return (n < 10 ? "0" : "") + n;
}

// Canonical peak windows, mirrored from deepseek-peak/schedule.json.
// tests/test_logic.js asserts these stay in sync with that file.
function scheduleWindows() {
    return [["01:00", "04:00"], ["06:00", "10:00"]];
}

function scheduleText() {
    return "01:00-04:00, 06:00-10:00 UTC";
}

function formatHMS(s) {
    s = Math.max(0, Math.floor(s));
    return pad(Math.floor(s / 3600)) + ":" + pad(Math.floor((s % 3600) / 60)) + ":" + pad(s % 60);
}

function isPeakAt(date, weekendMode) {
    var h = date.getUTCHours() + date.getUTCMinutes() / 60;
    if (weekendMode === "utc") {
        var uDay = date.getUTCDay();
        if (uDay === 0 || uDay === 6)
            return false;
        return (h >= 1 && h < 4) || (h >= 6 && h < 10);
    }
    var day = date.getUTCDay();
    var bjDay = new Date(date.getTime() + 8 * 3600 * 1000).getUTCDay();
    if (bjDay === 0 || bjDay === 6)
        return false;
    if (day === 6)
        return false;
    if (day === 5 && date.getUTCHours() >= 16)
        return false;
    if (day === 0 && date.getUTCHours() < 16)
        return false;
    return (h >= 1 && h < 4) || (h >= 6 && h < 10);
}

// Two-phase scan: coarse 60s steps to find the flip minute, then 1s refine
// inside that minute. Second-exact, ~228 iterations max instead of up to 10080.
function secondsUntilNext(date, weekendMode) {
    var peak = isPeakAt(date, weekendMode);
    var coarse = 0;
    for (var s = 60; s <= 7 * 86400; s += 60) {
        var d = new Date(date.getTime() + s * 1000);
        if (isPeakAt(d, weekendMode) !== peak) {
            coarse = s;
            break;
        }
    }
    if (coarse === 0)
        return 0;
    for (var t = coarse - 59; t <= coarse; t++) {
        var e = new Date(date.getTime() + t * 1000);
        if (isPeakAt(e, weekendMode) !== peak)
            return t;
    }
    return coarse;
}

function isWeekendOffDay(date, weekendMode) {
    if (weekendMode === "utc") {
        var uDay = date.getUTCDay();
        return uDay === 0 || uDay === 6;
    }
    var bjDay = new Date(date.getTime() + 8 * 3600 * 1000).getUTCDay();
    return bjDay === 0 || bjDay === 6;
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

function windowLine(now, weekendMode, tz) {
    // null = weekend: the host shows its localized "off-peak all day".
    if (isWeekendOffDay(now, weekendMode))
        return null;
    return fmtHM(now, 1, 0, tz) + "-" + fmtHM(now, 4, 0, tz) + " · " + fmtHM(now, 6, 0, tz) + "-" + fmtHM(now, 10, 0, tz);
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

    function readSettings() {
        var s = (root.pluginApi && root.pluginApi.pluginSettings) || {};
        var d = (root.pluginApi && root.pluginApi.manifest && root.pluginApi.manifest.metadata && root.pluginApi.manifest.metadata.defaultSettings) || {};
        root.displayMode = s.displayMode || d.displayMode || "compact";
        root.offPeakColor = s.offPeakColor || d.offPeakColor || "#4ade80";
        root.peakColor = s.peakColor || d.peakColor || "#f87171";
        root.driftColor = s.driftColor || d.driftColor || "#fbbf24";
        root.showTooltip = (s.showTooltip !== undefined) ? !!s.showTooltip : ((d.showTooltip !== undefined) ? !!d.showTooltip : true);
        root.weekendMode = s.weekendMode || d.weekendMode || "beijing-anchored";
        root.autoCheck = (s.autoCheck !== undefined) ? !!s.autoCheck : ((d.autoCheck !== undefined) ? !!d.autoCheck : true);
        root.offlineOnly = (s.offlineOnly !== undefined) ? !!s.offlineOnly : ((d.offlineOnly !== undefined) ? !!d.offlineOnly : false);
        root.checkIntervalH = s.checkIntervalH || d.checkIntervalH || 6;
        root.customSourceUrl = s.customSourceUrl || d.customSourceUrl || "";
    }
    // --- Policy-drift checker (in-memory state shared with the panel) ---
    function setDrift(value) {
        drift = !!value;
        if (pluginApi && pluginApi.pluginSettings)
            pluginApi.pluginSettings.drift = !!value;
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
                var m = xhr.responseText.match(/Peak hours are ([^<]+)/);
                if (m && !sameWindows(extractWindows(m[1]), extractWindows(scheduleText()))) {
                    setDrift(true);
                    ToastService.showNotice("DeepSeek pricing policy may have changed: " + m[1].trim());
                } else if (m) {
                    setDrift(false);
                }
                if (pluginApi && pluginApi.pluginSettings)
                    pluginApi.pluginSettings.checkedAtMs = Date.now();
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
    function t(key, params) {
        return (pluginApi && pluginApi.tr) ? pluginApi.tr(key, params) : key;
    }
    function refreshTexts() {
        stateText = isPeak ? t("bar.peak") : t("bar.offPeak");
        tooltipFormat = (isPeak ? t("bar.tooltipPeak") : t("bar.tooltipOffPeak")) + " — " + t("bar.nextFlip") + " " + countdownText + (drift ? " — " + t("bar.driftSuffix") : "");
    }
    function update() {
        var now = new Date();
        readSettings();
        // Pull shared drift flag (this widget's checker writes pluginSettings.drift).
        if (root.pluginApi && root.pluginApi.pluginSettings && root.pluginApi.pluginSettings.drift !== undefined)
            root.drift = !!root.pluginApi.pluginSettings.drift;
        isPeak = isPeakAt(now, weekendMode);
        // Throttle: full scan at most every 30s; tick down 1s in between.
        // Re-scan immediately when flip is imminent so countdown stays exact.
        if (_ticksSinceCalc >= 30 || secondsToNext <= 1) {
            secondsToNext = secondsUntilNext(now, weekendMode);
            _ticksSinceCalc = 0;
        } else {
            secondsToNext = Math.max(0, secondsToNext - 1);
            _ticksSinceCalc += 1;
        }
        refreshTexts();
    }
    Component.onCompleted: update()
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.update()
    }
    // First policy check shortly after startup, then every checkIntervalH.
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
    // Visual capsule - centered within the full click area
    Rectangle {
        id: visualCapsule
        x: Style.pixelAlignCenter(parent.width, width)
        y: Style.pixelAlignCenter(parent.height, height)
        width: root.contentWidth
        height: root.contentHeight
        radius: Style.radiusL
        color: mouseArea.containsMouse ? Qt.lighter(Style.capsuleColor, 1.12) : Style.capsuleColor
        border.color: mouseArea.containsMouse ? (root.drift ? root.driftColor : (root.isPeak ? root.peakColor : root.offPeakColor)) : Style.capsuleBorderColor
        border.width: Style.capsuleBorderWidth

        RowLayout {
            id: contentRow
            anchors.centerIn: parent
            spacing: Style.marginS

            NIcon {
                id: dot
                Layout.alignment: Qt.AlignVCenter
                // "circle-filled" is a real tabler dot; unknown names
                // fall back to the "skull" default icon.
                icon: "circle-filled"
                color: root.drift ? root.driftColor : (root.isPeak ? root.peakColor : root.offPeakColor)
            }
            NText {
                Layout.alignment: Qt.AlignVCenter
                visible: root.displayMode !== "icon"
                text: root.displayMode === "full" ? root.stateText + " " + root.countdownText : root.countdownText
                pointSize: barFontSize
                color: Color.mOnSurface
            }
        }
    }
    // MouseArea at root level for extended click area
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
        onExited: {
            TooltipService.hide(root);
        }
        onClicked: function (mouse) {
            TooltipService.hide(root);
            if (root.pluginApi)
                root.pluginApi.openPanel(root.screen, root);
        }
    }
    // Tooltip text lives in root.tooltipFormat; shown via TooltipService
    // on hover when the Show Tooltip setting is on.
}
