#!/usr/bin/env python3
"""Mirror deepseek-peak/i18n/*.json into deepseek-peak/translations/.

v4 Noctalia loads `<plugin>/i18n/<lang>.json`; the v5 plugin layout expects
`translations/`. The i18n directory is the single source; this keeps the v5
copies identical. Run after editing any locale file.

Usage:
  python tools/sync_i18n.py          # copy
  python tools/sync_i18n.py --check  # exit 1 if a copy is out of date
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "deepseek-peak" / "i18n"
DST = ROOT / "deepseek-peak" / "translations"


def main() -> int:
    check = "--check" in sys.argv
    stale = []
    for src in sorted(SRC.glob("*.json")):
        dst = DST / src.name
        content = src.read_text()
        if not dst.exists() or dst.read_text() != content:
            if check:
                stale.append(src.name)
            else:
                DST.mkdir(parents=True, exist_ok=True)
                dst.write_text(content)
                print(f"updated translations/{src.name}")
    if stale:
        print("out of sync (run tools/sync_i18n.py): " + ", ".join(stale))
        return 1
    if not check:
        print("i18n mirrored to translations/")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
