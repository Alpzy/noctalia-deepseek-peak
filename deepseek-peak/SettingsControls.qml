import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

// Settings controls embedded by Settings.qml (Plugins window). The panel is
// info-only by design, so this is the single settings surface.
ColumnLayout {
    id: root
    property var pluginApi: null

    property string editDisplayMode: (pluginApi?.pluginSettings?.displayMode || pluginApi?.manifest?.metadata?.defaultSettings?.displayMode || "compact")
    property string editProvider: (pluginApi?.pluginSettings?.provider || pluginApi?.manifest?.metadata?.defaultSettings?.provider || "deepseek")
    property color editOffPeakColor: (pluginApi?.pluginSettings?.offPeakColor || pluginApi?.manifest?.metadata?.defaultSettings?.offPeakColor || "#4ade80")
    property color editPeakColor: (pluginApi?.pluginSettings?.peakColor || pluginApi?.manifest?.metadata?.defaultSettings?.peakColor || "#f87171")
    property color editDriftColor: (pluginApi?.pluginSettings?.driftColor || pluginApi?.manifest?.metadata?.defaultSettings?.driftColor || "#fbbf24")
    property bool editShowTooltip: (pluginApi?.pluginSettings?.showTooltip ?? pluginApi?.manifest?.metadata?.defaultSettings?.showTooltip ?? true)
    property bool editAutoCheck: (pluginApi?.pluginSettings?.autoCheck ?? pluginApi?.manifest?.metadata?.defaultSettings?.autoCheck ?? true)
    property bool editOfflineOnly: (pluginApi?.pluginSettings?.offlineOnly ?? pluginApi?.manifest?.metadata?.defaultSettings?.offlineOnly ?? false)
    property string editCheckIntervalH: String(pluginApi?.pluginSettings?.checkIntervalH ?? pluginApi?.manifest?.metadata?.defaultSettings?.checkIntervalH ?? 6)
    property string editCustomSourceUrl: (pluginApi?.pluginSettings?.customSourceUrl ?? pluginApi?.manifest?.metadata?.defaultSettings?.customSourceUrl ?? "")

    spacing: Style.marginM

    function t(key, params) {
        return (pluginApi && pluginApi.tr) ? pluginApi.tr(key, params) : key;
    }

    NLabel {
        label: root.t("settings.provider.label")
        description: root.t("settings.provider.description")
    }
    NComboBox {
        Layout.fillWidth: true
        model: [
            {key: "deepseek", name: root.t("provider.deepseek")},
            {key: "ollama", name: root.t("provider.ollama")}
        ]
        currentKey: root.editProvider
        onSelected: function (key) { root.editProvider = key; }
    }

    NLabel {
        label: root.t("settings.display-mode.label")
        description: root.t("settings.display-mode.description")
    }
    NComboBox {
        Layout.fillWidth: true
        model: [
            {key: "compact", name: root.t("settings.display-mode.compact")},
            {key: "icon", name: root.t("settings.display-mode.icon")},
            {key: "full", name: root.t("settings.display-mode.full")}
        ]
        currentKey: root.editDisplayMode
        onSelected: function (key) { root.editDisplayMode = key; }
    }

    NLabel {
        label: root.t("settings.off-peak-color.label")
        description: root.t("settings.off-peak-color.description")
    }
    NColorPicker {
        Layout.preferredWidth: Style.sliderWidth
        Layout.preferredHeight: Style.baseWidgetSize
        selectedColor: root.editOffPeakColor
        onColorSelected: function (color) {
            root.editOffPeakColor = color;
        }
    }

    NLabel {
        label: root.t("settings.peak-color.label")
        description: root.t("settings.peak-color.description")
    }
    NColorPicker {
        Layout.preferredWidth: Style.sliderWidth
        Layout.preferredHeight: Style.baseWidgetSize
        selectedColor: root.editPeakColor
        onColorSelected: function (color) {
            root.editPeakColor = color;
        }
    }

    NLabel {
        label: root.t("settings.drift-color.label")
        description: root.t("settings.drift-color.description")
    }
    NColorPicker {
        Layout.preferredWidth: Style.sliderWidth
        Layout.preferredHeight: Style.baseWidgetSize
        selectedColor: root.editDriftColor
        onColorSelected: function (color) {
            root.editDriftColor = color;
        }
    }

    NToggle {
        Layout.fillWidth: true
        label: root.t("settings.show-tooltip.label")
        description: root.t("settings.show-tooltip.description")
        checked: root.editShowTooltip
        onToggled: function (checked) { root.editShowTooltip = checked; }
    }
    NToggle {
        Layout.fillWidth: true
        label: root.t("settings.auto-check.label")
        description: root.t("settings.auto-check.description")
        checked: root.editAutoCheck
        onToggled: function (checked) { root.editAutoCheck = checked; }
    }
    NToggle {
        Layout.fillWidth: true
        label: root.t("settings.offline-only.label")
        description: root.t("settings.offline-only.description")
        checked: root.editOfflineOnly
        onToggled: function (checked) { root.editOfflineOnly = checked; }
    }

    NTextInput {
        Layout.fillWidth: true
        label: root.t("settings.check-interval-h.label")
        description: root.t("settings.check-interval-h.description")
        text: root.editCheckIntervalH
        onTextChanged: root.editCheckIntervalH = text
    }
    NTextInput {
        Layout.fillWidth: true
        label: root.t("settings.custom-source-url.label")
        description: root.t("settings.custom-source-url.description")
        placeholderText: root.t("settings.custom-source-url.placeholder")
        text: root.editCustomSourceUrl
        onTextChanged: root.editCustomSourceUrl = text
    }


    // Collect without persisting; the host (Settings dialog) writes the result
    // into pluginSettings itself.
    function collectSettings() {
        return {
            provider: root.editProvider,
            displayMode: root.editDisplayMode,
            offPeakColor: root.editOffPeakColor.toString(),
            peakColor: root.editPeakColor.toString(),
            driftColor: root.editDriftColor.toString(),
            showTooltip: root.editShowTooltip,
            autoCheck: root.editAutoCheck,
            offlineOnly: root.editOfflineOnly,
            checkIntervalH: parseInt(root.editCheckIntervalH, 10) || 6,
            customSourceUrl: root.editCustomSourceUrl,
        };
    }
}
