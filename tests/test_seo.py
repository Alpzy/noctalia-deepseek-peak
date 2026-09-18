import pathlib
def test_seo_assets():
    assert pathlib.Path("LICENSE").exists()
    assert pathlib.Path("catalog.toml").exists()
    assert pathlib.Path("deepseek-peak/plugin.toml").exists()
    assert pathlib.Path("deepseek-peak/translations/en.json").exists()
    assert pathlib.Path("deepseek-peak/i18n/en.json").exists(), (
        "v4 loader reads <plugin>/i18n/<lang>.json"
    )
    readme = pathlib.Path("README.md").read_text()
    for kw in ["DeepSeek", "peak", "off-peak", "Noctalia", "Niri", "01:00", "06:00"]:
        assert kw in readme, f"missing keyword {kw}"
