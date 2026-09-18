import json
import pathlib
import re

I18N = pathlib.Path("deepseek-peak/i18n")
TRANSLATIONS = pathlib.Path("deepseek-peak/translations")

# Languages Noctalia's Commons/I18n.qml actually loads. Adding files outside
# this list has no effect in the shell, so coverage is defined by it.
SHELL_LANGUAGES = [
    "en", "en-GB", "cs", "de", "es", "fr", "hu", "it", "ja", "ko-KR", "ku",
    "nl", "nn-HN", "nn-NO", "pl", "pt", "ru", "sv", "tr", "uk-UA", "vi",
    "zh-CN", "zh-TW",
]
PLACEHOLDER = re.compile(r"\{[a-zA-Z0-9_]+\}")


def flatten(obj, prefix=""):
    out = {}
    for key, value in obj.items():
        path = f"{prefix}.{key}" if prefix else key
        if isinstance(value, dict):
            out.update(flatten(value, path))
        else:
            out[path] = value
    return out


def load(path):
    return flatten(json.loads(path.read_text()))


def test_every_shell_language_has_a_file():
    for lang in SHELL_LANGUAGES:
        assert (I18N / f"{lang}.json").exists(), f"missing i18n/{lang}.json"
    files = {p.stem for p in I18N.glob("*.json")}
    extra = files - set(SHELL_LANGUAGES)
    assert not extra, f"locales the shell will never load: {sorted(extra)}"


def test_locales_have_identical_key_sets():
    en = load(I18N / "en.json")
    for lang in SHELL_LANGUAGES:
        if lang == "en":
            continue
        table = load(I18N / f"{lang}.json")
        assert set(table) == set(en), (
            f"{lang}: missing {sorted(set(en) - set(table))}, "
            f"extra {sorted(set(table) - set(en))}"
        )


def test_no_empty_values_and_placeholders_preserved():
    en = load(I18N / "en.json")
    for lang in SHELL_LANGUAGES:
        table = load(I18N / f"{lang}.json")
        for key, value in table.items():
            assert isinstance(value, str) and value.strip(), f"{lang}/{key} is empty"
            assert set(PLACEHOLDER.findall(value)) == set(PLACEHOLDER.findall(en[key])), (
                f"{lang}/{key}: placeholders differ from en"
            )


def test_translations_dir_mirrors_i18n():
    for src in sorted(I18N.glob("*.json")):
        dst = TRANSLATIONS / src.name
        assert dst.exists(), f"translations/{src.name} missing; run tools/sync_i18n.py"
        assert dst.read_text() == src.read_text(), (
            f"translations/{src.name} is stale; run tools/sync_i18n.py"
        )
