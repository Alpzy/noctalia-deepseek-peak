# AGENTS.md

Instructions for AI coding agents working in this repository. Human-facing
docs live in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md); read both.

## What this is

A Noctalia (Quickshell/QML) bar widget showing DeepSeek's peak/off-peak API
pricing state, plus an info-only panel. v4 QML is the shipped target; a v5
Luau port exists in `deepseek-peak/` but is **experimental and untested** —
do not publish it.

## Hard rules

- **Do not push** until the maintainer explicitly asks.
- **`opencode.json`, `.opencode/`, `.superpowers/`, `.dev/`** are local-only
  and git-ignored. Never commit AI/session artifacts or a dev harness.
- **Peak logic has one source: `deepseek-peak/peak.js`.** It is inlined into
  `BarWidget.qml` and `Panel.qml` between generated markers by
  `python tools/sync_peak.py`. After editing `peak.js`, run the sync tool.
  Never hand-edit the generated block; `pytest` fails if it drifts.
- **i18n has one source: `deepseek-peak/i18n/en.json`** (nested keys). Add a
  key to `en.json` and all locales, then `python tools/sync_i18n.py` for the
  v5 `translations/` mirror. Only languages in Noctalia's
  `Commons/I18n.qml` `availableLanguages` are loaded by the shell.
- **Transient runtime state must not persist.** `drift`/`checkedAtMs` live in
  `pluginApi.pluginSettings` in memory only; settings save strips them.
- **Verify against the installed shell source**, not assumptions:
  `/etc/xdg/quickshell/noctalia-shell/` (`Widgets/`, `Commons/`, `Services/`).
  Qt's QML engine has no usable `Intl` — do timezone math manually.
- Keep functions at component root scope (QML bindings cannot see functions
  nested inside child layouts), and never bind the same property twice.

## Commands

```bash
uvx --with pytest pytest tests/ -q      # full suite
node tests/test_logic.js                # pure logic assertions
python tools/sync_peak.py --check       # generated peak block in sync
python tools/sync_i18n.py --check       # translations/ mirror in sync
/usr/lib/qt6/bin/qmllint -I <shelldir> deepseek-peak/*.qml   # optional lint
```

## Architecture

- `deepseek-peak/BarWidget.qml` — bar capsule (dot + `HH:MM:SS`), reads
  settings every tick, **owns the policy-drift checker** so checks run
  whenever the widget is on the bar.
- `deepseek-peak/Panel.qml` — info-only, dynamic height, reads state shared
  through `pluginSettings`.
- `deepseek-peak/Settings.qml` + `SettingsControls.qml` — the only settings
  surface (Plugins window → Configure).
- `deepseek-peak/peak.js` — pure schedule/time functions (tested in node).
- `deepseek-peak/schedule.json` — schedule data, cross-checked against
  `peak.js` by `tests/test_logic.js`.

## Local UI verification

`.dev/harness/` renders the widget offscreen with the real Noctalia widgets
and writes PNGs to `.dev/harness/captures/`: `.dev/harness/setup.sh &&
.dev/harness/run.sh`. Use it before claiming a UI change works.
