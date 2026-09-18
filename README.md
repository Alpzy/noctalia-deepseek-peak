# DeepSeek Peak Hours — Noctalia Bar Widget

A [Noctalia](https://github.com/noctalia-dev/noctalia) bar widget that shows
whether the DeepSeek API is currently in **peak** (2× price) or **off-peak**
(half price) billing, with a live countdown to the next rate flip. Built for
Niri and any other compositor Noctalia supports.

- 🟢 **Off-peak** — cheap: green dot.
- 🔴 **Peak** — 2× cost: red dot.
- 🟡 **Policy drift** — the official pricing page no longer matches the bundled
  schedule: amber dot and a notice.
- Live `HH:MM:SS` countdown to the next flip, in the bar and in the panel.

![DeepSeek Peak Hours preview](deepseek-peak/preview.png)

## Peak windows

| Window | UTC | Beijing |
|---|---|---|
| Peak 1 | 01:00–04:00 | 09:00–12:00 |
| Peak 2 | 06:00–10:00 | 14:00–18:00 |
| Off-peak | everything else | everything else |

Peak applies Monday–Friday. Weekends are off-peak all day, anchored to the
Beijing calendar (Friday 16:00 UTC through Sunday 16:00 UTC). Source:
<https://api-docs.deepseek.com/quick_start/pricing/>

## Install (Noctalia v4)

```bash
git clone https://github.com/Alpzy/noctalia-deepseek-peak
cp -r noctalia-deepseek-peak/deepseek-peak ~/.config/noctalia/plugins/
```

Register the plugin in `~/.config/noctalia/plugins.json` (required — plugins
are not auto-discovered):

```json
"states": {
    "deepseek-peak": { "enabled": true, "sourceUrl": "local" }
}
```

Restart the shell, then:

1. Settings → Plugins → enable **DeepSeek Peak Hours**.
2. Settings → Bar → add the **DeepSeek Peak Hours** widget.

## Configure

Settings → Plugins → DeepSeek Peak Hours → Configure: display mode
(`compact` / `icon` / `full`), colours, tooltip, weekend anchoring, and the
optional policy check (interval, custom source, offline-only).

## Behaviour

- **Offline-first.** The schedule is bundled; the optional online check only
  compares the published peak windows and warns when they change. A failed
  check leaves the last known state in place.
- **No API key, no request metering.** It only reads the public pricing page.
- **23 languages**, following Noctalia's supported locale list.

## Development

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for architecture, tests, the
offscreen UI harness, and the hot-reload workflow. AI agents should read
[AGENTS.md](AGENTS.md).

The v5 Luau port in `deepseek-peak/` is experimental and not published.

## License

MIT — see [LICENSE](LICENSE).
