import pathlib
import shutil
import subprocess

import pytest


def test_peak_js_behavior():
    node = shutil.which("node")
    if node is None:
        pytest.skip("node not available")
    test_file = pathlib.Path("tests/test_logic.js")
    result = subprocess.run(
        [node, str(test_file)],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert "all assertions passed" in result.stdout


def test_peak_js_exists_and_inlined_in_sync():
    peak = pathlib.Path("deepseek-peak/peak.js")
    assert peak.exists()
    body = peak.read_text().strip("\n")
    for rel in ("deepseek-peak/Main.qml", "deepseek-peak/BarWidget.qml", "deepseek-peak/Panel.qml"):
        text = pathlib.Path(rel).read_text()
        assert "// BEGIN peak.js (generated" in text and "// END peak.js (generated)" in text, (
            f"{rel} must carry the generated peak.js block"
        )
        assert body in text, f"{rel} generated block is stale; run tools/sync_peak.py"
        assert 'import "peak.js"' not in text, "plugin QML cannot import relative .js"
        assert "Peak." not in text, "use bare calls; the shared block is inlined"
