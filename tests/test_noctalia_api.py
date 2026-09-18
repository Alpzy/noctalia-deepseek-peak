import pathlib
import re

SETTINGS = (
    pathlib.Path("deepseek-peak/Settings.qml").read_text()
    + pathlib.Path("deepseek-peak/SettingsControls.qml").read_text()
)


def test_settings_uses_currentKey_not_currentIndex():
    assert "currentIndex" not in SETTINGS, (
        "NComboBox has no currentIndex property; use currentKey + onSelected"
    )
    assert "onCurrentIndexChanged" not in SETTINGS
    assert "currentKey" in SETTINGS
    assert "onSelected" in SETTINGS


def test_settings_uses_onToggled():
    assert "onCheckedChanged" not in SETTINGS, (
        "NToggle never sets checked itself; handle onToggled instead"
    )
    assert "onToggled" in SETTINGS


def extract_windows(text):
    return sorted(
        f"{a}-{b}" for a, b in re.findall(r"(\d{2}:\d{2})\s*-\s*(\d{2}:\d{2})", text)
    )


OFFICIAL_TEXT = (
    "01:00 - 04:00 and 06:00 - 10:00 UTC, Monday through Friday "
    "(all other hours are off-peak)."
)
BUNDLED_TEXT = "01:00-04:00, 06:00-10:00 UTC"


def test_drift_compare_ignores_formatting():
    assert extract_windows(OFFICIAL_TEXT) == extract_windows(BUNDLED_TEXT)


def test_drift_compare_catches_real_change():
    changed = "02:00 - 05:00 and 06:00 - 10:00 UTC, Monday through Friday."
    assert extract_windows(changed) != extract_windows(BUNDLED_TEXT)


def test_bar_uses_capsule_sizing():
    bar = pathlib.Path("deepseek-peak/BarWidget.qml").read_text()
    assert "getCapsuleHeightForScreen" in bar
    assert "contentWidth" in bar and "contentHeight" in bar
    assert "Style.pixelAlignCenter" in bar
    assert "\n    width:" not in bar and "\n    height: 28" not in bar


def test_bar_declares_every_root_property_it_uses():
    bar = pathlib.Path("deepseek-peak/BarWidget.qml").read_text()
    declared = set(re.findall(r"property\s+\w+\s+(\w+)", bar))
    declared |= set(re.findall(r"function\s+(\w+)", bar))
    for name in set(re.findall(r"root\.(\w+)", bar)):
        if name in ("pluginApi", "screen"):
            continue
        assert name in declared, f"BarWidget uses undeclared root.{name}"


def test_bar_dot_hover_tooltip_and_menu():
    bar = pathlib.Path("deepseek-peak/BarWidget.qml").read_text()
    assert 'icon: "circle-filled"' in bar, "use a real dot glyph"
    assert '"zap"' not in bar
    assert "Color.mHover" not in bar, "mHover is blinding; use a subtle hover"
    assert "TooltipService.show" in bar and "TooltipService.hide" in bar
    assert "openPluginSettings" in bar, "right-click should open widget settings"
    assert "togglePanel" in bar, "left-click should toggle the panel"


def test_shared_state_lives_in_main():
    main = pathlib.Path("deepseek-peak/Main.qml").read_text()
    bar = pathlib.Path("deepseek-peak/BarWidget.qml").read_text()
    panel = pathlib.Path("deepseek-peak/Panel.qml").read_text()
    assert "function checkDrift()" in main and "XMLHttpRequest" in main
    assert "Math.max(1, root.checkIntervalH) * 3600000" in main, (
        "honor the checkIntervalH setting"
    )
    assert "IpcHandler" in main
    assert "mainInstance" in bar and "mainInstance" in panel
    assert "XMLHttpRequest" not in bar and "XMLHttpRequest" not in panel, (
        "components are display-only; the checker lives in Main.qml"
    )
    assert "function checkDrift" not in bar and "function checkDrift" not in panel


def test_panel_follows_registry_panel_contract():
    panel = pathlib.Path("deepseek-peak/Panel.qml").read_text()
    assert "geometryPlaceholder" in panel
    assert "allowAttach" in panel
    assert "contentPreferredWidth: 320 * Style.uiScaleRatio" in panel
    assert "contentPreferredHeight: panelColumn.implicitHeight" in panel
    assert "anchors.fill: parent" in panel
    assert "SettingsControls" not in panel, "settings belong to the Plugins window"
    assert "NCollapsible" not in panel
    assert panel.count("pointSize: Style.fontSizeS") >= 3


def test_settings_save_strips_transient_state():
    settings = pathlib.Path("deepseek-peak/Settings.qml").read_text()
    assert "delete root.pluginApi.pluginSettings.drift" in settings
    assert "delete root.pluginApi.pluginSettings.checkedAtMs" in settings


def test_manifest_matches_registry_rules():
    import json

    manifest = json.loads(pathlib.Path("deepseek-peak/manifest.json").read_text())
    assert manifest["id"] == "deepseek-peak"
    assert manifest["version"] == "1.0.0"
    assert manifest["repository"] == "https://github.com/noctalia-dev/noctalia-plugins"
    assert "main" in manifest["entryPoints"], "shared state needs a main entry"
    assert manifest["tags"], "registry expects tags"
    defaults = manifest["metadata"]["defaultSettings"]
    for key in ("displayMode", "weekendMode", "autoCheck", "checkIntervalH",
                "offlineOnly", "customSourceUrl", "showTooltip"):
        assert key in defaults, f"missing default for {key}"


def test_qml_uses_translations():
    cases = (
        ("deepseek-peak/Main.qml", "panel."),
        ("deepseek-peak/BarWidget.qml", "bar."),
        ("deepseek-peak/SettingsControls.qml", "settings."),
    )
    for rel, prefix in cases:
        text = pathlib.Path(rel).read_text()
        assert "tr(" in text, f"{rel} must translate user-facing text"
        assert prefix in text, f"{rel} should use {prefix}* translation keys"


def test_no_halfx_wording():
    for rel in (
        "deepseek-peak/BarWidget.qml",
        "deepseek-peak/widget.luau",
        "deepseek-peak/translations/en.json",
    ):
        assert "0.5x" not in pathlib.Path(rel).read_text(), f"{rel} still shows 0.5x"
