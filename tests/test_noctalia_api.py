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


def test_bar_declares_every_root_property_it_uses():
    import re

    bar = pathlib.Path("deepseek-peak/BarWidget.qml").read_text()
    declared = set(re.findall(r"property\s+\w+\s+(\w+)", bar))
    declared |= set(re.findall(r"function\s+(\w+)", bar))
    for name in set(re.findall(r"root\.(\w+)", bar)):
        if name in ("pluginApi", "screen"):
            continue
        assert name in declared, f"BarWidget uses undeclared root.{name}"


def test_bar_uses_capsule_sizing_not_fixed_pixels():
    bar = pathlib.Path("deepseek-peak/BarWidget.qml").read_text()
    assert "getCapsuleHeightForScreen" in bar
    assert "implicitWidth: contentWidth" in bar
    assert "implicitHeight: contentHeight" in bar
    assert "\n    width:" not in bar and "\n    height: 28" not in bar


def test_settings_host_embeds_shared_controls():
    settings = pathlib.Path("deepseek-peak/Settings.qml").read_text()
    assert pathlib.Path("deepseek-peak/SettingsControls.qml").exists()
    assert "SettingsControls" in settings
    assert "collectSettings" in settings


def test_panel_is_info_only():
    panel = pathlib.Path("deepseek-peak/Panel.qml").read_text()
    assert "SettingsControls" not in panel, "settings belong to the Plugins window only"
    assert "NCollapsible" not in panel
    assert "NScrollView" not in panel
    assert panel.count("pointSize: Style.fontSizeS") >= 3


def test_bar_dot_hover_tooltip():
    bar = pathlib.Path("deepseek-peak/BarWidget.qml").read_text()
    assert 'icon: "circle-filled"' in bar, "use a real dot glyph, not an unknown name"
    assert '"zap"' not in bar
    assert "Color.mHover" not in bar, "mHover is blinding; use a subtle hover"
    assert "TooltipService.show" in bar and "TooltipService.hide" in bar


def test_panel_has_padding():
    panel = pathlib.Path("deepseek-peak/Panel.qml").read_text()
    assert "anchors.margins" in panel, "panel content needs padding"


def test_no_halfx_wording():
    for rel in (
        "deepseek-peak/BarWidget.qml",
        "deepseek-peak/widget.luau",
        "deepseek-peak/translations/en.json",
    ):
        assert "0.5x" not in pathlib.Path(rel).read_text(), f"{rel} still shows 0.5x"


def test_panel_checked_row_is_relative():
    panel = pathlib.Path("deepseek-peak/Panel.qml").read_text()
    assert "property double checkedAtMs" in panel
    assert "checkedInfo(" in panel
    assert "root.checkedText" in panel
    assert "toISOString" not in panel, "store epoch ms; relative label needs it"


def test_qml_uses_translations():
    cases = (
        ("deepseek-peak/BarWidget.qml", "bar."),
        ("deepseek-peak/Panel.qml", "panel."),
        ("deepseek-peak/SettingsControls.qml", "settings."),
    )
    for rel, prefix in cases:
        text = pathlib.Path(rel).read_text()
        assert "function t(key" in text, f"{rel} needs the tr helper"
        assert prefix in text, f"{rel} should use {prefix}* translation keys"


def test_checker_lives_in_bar_widget():
    bar = pathlib.Path("deepseek-peak/BarWidget.qml").read_text()
    panel = pathlib.Path("deepseek-peak/Panel.qml").read_text()
    assert "function checkDrift()" in bar and "XMLHttpRequest" in bar
    assert "Math.max(1, root.checkIntervalH) * 3600000" in bar, (
        "honor the checkIntervalH setting"
    )
    assert "XMLHttpRequest" not in panel, "panel is display-only"
    assert "function checkDrift" not in panel
    assert "ToastService" not in panel


def test_settings_save_strips_transient_state():
    settings = pathlib.Path("deepseek-peak/Settings.qml").read_text()
    assert "delete root.pluginApi.pluginSettings.drift" in settings
    assert "delete root.pluginApi.pluginSettings.checkedAtMs" in settings


def test_panel_dynamic_size():
    panel = pathlib.Path("deepseek-peak/Panel.qml").read_text()
    assert "contentPreferredWidth: 320" in panel
    assert "contentPreferredHeight: Math.round(card.implicitHeight" in panel, (
        "panel height must bind to content so SmartPanel resizes live"
    )
    assert "width: contentPreferredWidth" in panel
    assert "height: contentPreferredHeight" in panel
