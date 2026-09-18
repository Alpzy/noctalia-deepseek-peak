# Development

How to work on **DeepSeek Peak Hours**, a Noctalia bar widget for Niri (and
any other compositor Noctalia supports). AI agents should also read
[../AGENTS.md](../AGENTS.md).

## What the widget does

DeepSeek bills its API at peak/off-peak rates: peak is 01:00–04:00 and
06:00–10:00 UTC, Monday–Friday (09:00–12:00 and 14:00–18:00 Beijing), and
off-peak is everything else at half the peak price. Weekends are off-peak all
day, anchored to the Beijing calendar. The widget shows a coloured dot and a
countdown; clicking opens a small info panel.

## Layout

```
deepseek-peak/
  Main.qml             shared state, policy-drift checker, display strings, IPC
  BarWidget.qml        bar capsule (dot + countdown), tooltip, click/right-click
  Panel.qml            info-only popup (dynamic height, registry panel contract)
  Settings.qml         Plugins > Configure entry point
  SettingsControls.qml shared settings controls used by Settings.qml
  peak.js              single source of schedule + time math
  schedule.json        schedule data (mirrored by peak.js, checked by tests)
  i18n/<lang>.json     translations loaded by v4 Noctalia
  translations/<lang>.json  generated mirror for the experimental v5 port
  plugin.toml, widget.luau, panel.luau   experimental v5 port (untested)
tools/
  sync_peak.py         inlines peak.js into Main.qml
  sync_i18n.py         mirrors i18n/ into translations/
tests/                 pytest suite + node logic tests
```

## Setup

Requirements: `qs`/Noctalia v4 installed, Python 3, Node (for logic tests),
optionally `uv`.

```bash
uvx --with pytest pytest tests/ -q     # full suite
node tests/test_logic.js               # just the pure logic
```

Install into a live shell for manual testing:

```bash
cp -r deepseek-peak ~/.config/noctalia/plugins/
# add to ~/.config/noctalia/plugins.json under "states":
#   "deepseek-peak": { "enabled": true, "sourceUrl": "local" }
```

Then enable it in Settings → Plugins and add it in Settings → Bar.

### Fast iteration without restarts

Noctalia has a debug/hot-reload mode:

1. Settings → About → click the version area 8 times (5 s window) → "Debug
   enabled" toast. This is runtime-only and resets when the shell restarts.
2. Settings → Plugins → the plugin's row → click the small bug icon to enable
   development mode.
3. Copy edited files into `~/.config/noctalia/plugins/deepseek-peak/`; the
   shell reloads the plugin within ~0.5 s. Check the shell log at
   `/run/user/$(id -u)/quickshell/by-id/*/log.qslog` for `Plugin load error`.

### Offscreen rendering harness

`.dev/harness/` (git-ignored) renders `BarWidget.qml`/`Panel.qml` with the
real Noctalia widgets on Qt's offscreen platform and writes PNGs, so UI
changes can be checked without a shell session or a compositor restart:

```bash
.dev/harness/setup.sh && .dev/harness/run.sh   # writes .dev/harness/captures/
```

It symlinks `Commons/`, `Widgets/`, `Modules/`, `Helpers/`, `Assets/` from the
installed shell and stubs the services that need a Wayland/layer-shell
backend.

## Editing rules

- **Schedule/time logic changes go in `peak.js` only**, then
  `python tools/sync_peak.py` inlines it into `Main.qml`, `BarWidget.qml`
  and `Panel.qml`. `tests/test_logic.js` fails if any inline drifts.
  Bar and panel compute their own tier/countdown so a missing or failed
  `Main` can never blank the UI; `Main` owns the drift checker.
- **Hot reload does not re-read manifests.** Adding or removing an entry
  point, or editing `manifest.json` fields, requires a shell restart; QML/JS
  and timer edits reload fine (with debug + development mode enabled).
- **Keep functions at the component root.** QML bindings cannot call
  functions nested inside child layouts (this caused a real bug where the
  panel silently rendered nothing).
- **Never bind the same property twice** in one object; the component fails
  to load with "value set multiple times".
- **No `Intl`.** Qt's QML engine does not implement timezone options; do
  manual offset math (`peak.js` shows how).
- **Icon names must exist** in `Commons/IconsTabler.qml`; unknown names render
  the `skull` fallback glyph (`circle-filled` is the dot used here).
- **Transient UI state must not be persisted.** `drift` and `checkedAtMs` live
  only on the `Main.qml` instance, shared with the bar/panel through
  `pluginApi.mainInstance`; the settings save path also deletes any legacy
  copies from `settings.json`.

## Translations

`deepseek-peak/i18n/*.json` use nested keys. The shell only loads languages
listed in `/etc/xdg/quickshell/noctalia-shell/Commons/I18n.qml`
(`availableLanguages`) — adding files for other locales has no effect.
`tests/test_i18n.py` enforces identical key sets across locales and keeps
`{n}` placeholders intact. The four `bar.*` state labels are intentionally
identical in every language so the bar capsule stays narrow.

## Releasing (v4 registry)

The shipped target is Noctalia v4, published to
[`noctalia-dev/noctalia-plugins`](https://github.com/noctalia-dev/noctalia-plugins).
That repository requires, inside the plugin directory: `manifest.json`,
`README.md`, and `preview.png` (16:9, 960×540). The v5 port is **not**
published; `community-plugins` additionally requires `thumbnail.webp`, a
valid `plugin.toml` and `translations/en.json`, and must be tested on a real
v5 shell first.
