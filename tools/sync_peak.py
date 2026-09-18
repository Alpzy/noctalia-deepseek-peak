#!/usr/bin/env python3
"""Inline deepseek-peak/peak.js into the QML components.

The Noctalia v4 plugin loader cannot resolve relative `.js` imports from
plugin QML (it loads plugin files through a virtual FileView URL and reports
"File name case mismatch"), so the shared logic must live inside each QML
file. peak.js stays the single source of truth; this script copies its body
between the generated markers in BarWidget.qml and Panel.qml and de-prefixes
`Peak.` call sites.

Usage:
  python tools/sync_peak.py          # rewrite the generated blocks
  python tools/sync_peak.py --check  # exit 1 if a rewrite would be needed
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PEAK = ROOT / "deepseek-peak" / "peak.js"
TARGETS = [
    ROOT / "deepseek-peak" / "BarWidget.qml",
    ROOT / "deepseek-peak" / "Panel.qml",
]
BEGIN = "// BEGIN peak.js (generated - edit peak.js and run tools/sync_peak.py)"
END = "// END peak.js (generated)"


def rendered(target: Path) -> str:
    text = target.read_text()
    body = PEAK.read_text().strip("\n")
    start = text.index(BEGIN)
    stop = text.index(END) + len(END)
    block = BEGIN + "\n" + body + "\n" + END
    updated = text[:start] + block + text[stop:]
    updated = updated.replace('import "peak.js" as Peak\n', "")
    updated = updated.replace('import "peak.js" as Peak\r\n', "")
    updated = updated.replace("Peak.", "")
    return updated


def main() -> int:
    check = "--check" in sys.argv
    failures = []
    for target in TARGETS:
        wanted = rendered(target)
        current = target.read_text()
        if wanted != current:
            if check:
                failures.append(target.name)
            else:
                target.write_text(wanted)
                print(f"updated {target.relative_to(ROOT)}")
    if failures:
        print("out of sync (run tools/sync_peak.py): " + ", ".join(failures))
        return 1
    if not check:
        print("sync complete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
