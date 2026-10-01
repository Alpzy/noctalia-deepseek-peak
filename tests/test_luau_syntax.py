import pathlib
import shutil
import subprocess

import pytest

LUAU_FILES = [
    "deepseek-peak/widget.luau",
    "deepseek-peak/panel.luau",
    "deepseek-peak/checker.luau",
]


def _lua():
    return shutil.which("lua5.4") or shutil.which("lua") or shutil.which("luajit")


def test_luau_entry_scripts_parse():
    lua = _lua()
    if lua is None:
        pytest.skip("no lua interpreter available")
    for rel in LUAU_FILES:
        path = pathlib.Path(rel)
        assert path.exists(), f"{rel} missing"
        result = subprocess.run(
            [lua, "-e", f"assert(loadfile('{path}'))"],
            capture_output=True, text=True,
        )
        assert result.returncode == 0, f"{rel}: {result.stderr}"


def test_widget_uses_v5_api_not_v4_objects():
    text = pathlib.Path("deepseek-peak/widget.luau").read_text()
    assert "barWidget.setGlyph" in text or "barWidget.render" in text
    assert "noctalia.getConfig" in text
    assert "pluginApi" not in text, "v4 plugin object must not leak into v5 script"
    assert "setUpdateInterval" in text
    assert "weekendMode" in text, "weekendMode setting must still affect the schedule"
