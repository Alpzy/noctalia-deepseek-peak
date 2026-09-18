import json
import pathlib


def load():
    return json.loads(pathlib.Path("deepseek-peak/schedule.json").read_text())


def test_schedule_file_shape():
    s = load()
    assert s["peakWindows"] == [["01:00", "04:00"], ["06:00", "10:00"]]
    assert s["weekendOffPeak"]["timezone"] == "Asia/Shanghai"
    assert s["version"]
    assert s["sourceUrl"].startswith("https://api-docs.deepseek.com/")


# Behavior and the schedule.json <-> peak.js cross-check live in
# tests/test_logic.js (executed via tests/test_logic_node.py) so the schedule
# logic has exactly one implementation.
