#!/usr/bin/env python3
"""Generate and inline the widget's schedule logic.

Two generated artifacts, both enforced by `--check`:

1. The data block inside `deepseek-peak/peak.js`, rebuilt from
   `deepseek-peak/schedule.json` (provider profiles + Chinese holidays).
2. The whole `peak.js` body inlined between markers in Main.qml,
   BarWidget.qml and Panel.qml. The Noctalia v4 plugin loader cannot resolve
   relative .js imports from plugin QML, and the bar/panel compute locally so
   a missing Main can never blank the UI.

Usage:
  python tools/sync_peak.py          # regenerate everything
  python tools/sync_peak.py --check  # exit 1 if anything is out of date
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PEAK = ROOT / "deepseek-peak" / "peak.js"
SCHEDULE = ROOT / "deepseek-peak" / "schedule.json"
TARGETS = [
    ROOT / "deepseek-peak" / "Main.qml",
    ROOT / "deepseek-peak" / "BarWidget.qml",
    ROOT / "deepseek-peak" / "Panel.qml",
]

DATA_BEGIN = "    // BEGIN schedule.json (generated - edit schedule.json and run tools/sync_peak.py)"
DATA_END = "    // END schedule.json (generated)"

LOGIC_BEGIN = "    // BEGIN peak.js (generated - edit peak.js and run tools/sync_peak.py)"
LOGIC_END = "// END peak.js (generated)"


def json_compact(value):
    return json.dumps(value, ensure_ascii=False, separators=(", ", ": "))


def data_block() -> str:
    """Render the schedule.json data as JS accessor functions."""
    schedule = json.loads(SCHEDULE.read_text())
    providers = json_compact({k: v for k, v in schedule["providers"].items()})
    holidays = json_compact(schedule["holidays"])
    return "\n".join([
        DATA_BEGIN,
        f"function providerProfiles() {{ return ({providers}); }}",
        f"function holidayDates() {{ return ({holidays}); }}",
        DATA_END,
    ])


def apply_data_block(body: str) -> str:
    start = body.index(DATA_BEGIN)
    stop = body.index(DATA_END) + len(DATA_END)
    return body[:start] + data_block() + body[stop:]


def rendered_qml(target: Path, body: str) -> str:
    text = target.read_text()
    start = text.index(LOGIC_BEGIN)
    stop = text.index(LOGIC_END) + len(LOGIC_END)
    block = LOGIC_BEGIN + "\n" + body + "\n" + LOGIC_END
    updated = text[:start] + block + text[stop:]
    updated = updated.replace('import "peak.js" as Peak\n', "")
    return updated


def main() -> int:
    check = "--check" in sys.argv
    stale = []

    body = PEAK.read_text()
    regenerated = apply_data_block(body)
    if regenerated != body:
        if check:
            stale.append("peak.js (data block)")
        else:
            PEAK.write_text(regenerated)
            print("updated peak.js data block")
            body = regenerated

    for target in TARGETS:
        wanted = rendered_qml(target, body.strip("\n"))
        if wanted != target.read_text():
            if check:
                stale.append(target.name)
            else:
                target.write_text(wanted)
                print(f"updated {target.relative_to(ROOT)}")

    if stale:
        print("out of sync (run tools/sync_peak.py): " + ", ".join(stale))
        return 1
    if not check:
        print("sync complete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
