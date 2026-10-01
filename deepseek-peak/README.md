# DeepSeek Peak Hours

A Noctalia bar widget showing peak/off-peak API rate tiers: green off-peak,
red at peak (2×), with a live countdown to the next flip. Clicking opens a
small info panel; right-clicking swaps provider.

Supports two tariffs with different peak windows:

| Provider | Peak (UTC, Mon–Fri) | Off-peak |
|---|---|---|
| **DeepSeek** | 01:00–04:00, 06:00–10:00 | everything else; weekends + Chinese public holidays all day |
| **Ollama** (DeepSeek models) | 12:00–18:00 | everything else; weekends (UTC) all day |

Off-peak is half the peak price for both.

![preview](preview.png)

## Install (Noctalia v4)

```bash
cp -r deepseek-peak ~/.config/noctalia/plugins/
```

Add the plugin to `~/.config/noctalia/plugins.json` (required — plugins are
not auto-discovered):

```json
"states": {
    "deepseek-peak": { "enabled": true, "sourceUrl": "local" }
}
```

Then enable it in Settings → Plugins and add it in Settings → Bar.

## Configure

Settings → Plugins → DeepSeek Peak Hours → Configure:

- provider: `deepseek` or `ollama`
- display mode: `compact` (dot + countdown), `icon`, `full`
- off-peak / peak / drift colours
- tooltip on hover
- optional policy check: enable/disable, interval, custom source URL, offline-only

## Notes

- Works offline: schedules and Chinese holidays are bundled; the online check
  only adds the amber drift warning and never blanks the widget.
- 23 languages, following Noctalia's supported locale list.
- Holiday data from [NateScarlet/holiday-cn](https://github.com/NateScarlet/holiday-cn) (MIT); see the repository's THIRD_PARTY_NOTICES.md.
- The v5 Luau port in this directory is **experimental and untested**; do not
  publish it yet.

## License

MIT
