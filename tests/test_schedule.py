import json
import pathlib


def load():
    return json.loads(pathlib.Path("deepseek-peak/schedule.json").read_text())


def test_schedule_file_shape():
    s = load()
    assert s["providers"]["deepseek"]["peakWindowsUtc"] == [["01:00", "04:00"], ["06:00", "10:00"]]
    assert s["providers"]["deepseek"]["weekendMode"] == "beijing-anchored"
    assert s["providers"]["ollama"]["peakWindowsUtc"] == [["12:00", "18:00"]]
    assert s["providers"]["ollama"]["weekendMode"] == "utc"
    assert s["providers"]["deepseek"]["holidayOffPeak"] is True
    assert s["providers"]["ollama"]["holidayOffPeak"] is False
    assert s["holidays"]["2026"], "2026 Chinese holidays must be bundled"
    assert all(len(day) == 10 for day in s["holidays"]["2026"])
    assert "holiday-cn" in s["holidaySource"] and "MIT" in s["holidaySource"]
    for provider in s["providers"].values():
        assert provider["sourceUrl"].startswith("https://")


# Behavior, provider profiles and the schedule.json <-> peak.js cross-check live
# in tests/test_logic.js (executed via tests/test_logic_node.py) so the
# schedule logic has exactly one implementation.
