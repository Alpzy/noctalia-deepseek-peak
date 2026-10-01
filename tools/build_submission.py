#!/usr/bin/env python3
"""Build the v5 submission tree for noctalia-dev/community-plugins.

The community repo takes one top-level directory per plugin. This repo keeps
the v4 Quickshell implementation, dev harness, tests, and 23-locale i18n tree;
the submission ships only what runs on Noctalia v5 plus the English catalog
source.

Usage:
  python3 tools/build_submission.py [out-dir]
Default out-dir: build/submission (git-ignored).
"""
from __future__ import annotations

import json
import pathlib
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PLUGIN = ROOT / "deepseek-peak"

FILES = (
    "plugin.toml",
    "widget.luau",
    "panel.luau",
    "checker.luau",
    "schedule.json",
    "README.md",
    "thumbnail.webp",
)
LIB_FILES = ("schedule.luau", "settings.luau")
TRANSLATIONS = ("en.json",)


def build(out_dir: pathlib.Path) -> int:
    dest = out_dir / "deepseek-peak"
    if dest.exists():
        shutil.rmtree(dest)
    (dest / "lib").mkdir(parents=True)
    (dest / "translations").mkdir()

    for name in FILES:
        src = PLUGIN / name
        if not src.exists():
            print(f"error: missing {src}", file=sys.stderr)
            return 1
        shutil.copy2(src, dest / name)
    for name in LIB_FILES:
        shutil.copy2(PLUGIN / "lib" / name, dest / "lib" / name)
    for name in TRANSLATIONS:
        shutil.copy2(PLUGIN / "translations" / name, dest / "translations" / name)

    # Sanity: the community store requires every label_key to resolve in en.json.
    manifest = (dest / "plugin.toml").read_text()
    translations = json.loads((dest / "translations" / "en.json").read_text())

    def has_key(dotted: str) -> bool:
        node = translations
        for part in dotted.split("."):
            if not isinstance(node, dict) or part not in node:
                return False
            node = node[part]
        return True

    import re

    missing = [key for key in re.findall(r'(?:label_key|description_key)\s*=\s*"([^"]+)"', manifest)
               if not has_key(key)]
    if missing:
        print(f"error: en.json is missing {missing}", file=sys.stderr)
        return 1

    count = sum(1 for p in dest.rglob("*") if p.is_file())
    print(f"built {dest} ({count} files)")
    return 0


if __name__ == "__main__":
    out = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "build" / "submission"
    raise SystemExit(build(out))
