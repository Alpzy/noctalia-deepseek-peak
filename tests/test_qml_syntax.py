import pathlib

QML_FILES = [
    "deepseek-peak/BarWidget.qml",
    "deepseek-peak/Panel.qml",
    "deepseek-peak/Settings.qml",
]


def test_qml_braces_balanced():
    for rel in QML_FILES:
        text = pathlib.Path(rel).read_text()
        assert text.count("{") == text.count("}"), (
            f"{rel}: unbalanced braces "
            f"({text.count('{')} open vs {text.count('}')} close)"
        )


def test_bar_tryurl_closed_before_helpers():
    text = pathlib.Path("deepseek-peak/BarWidget.qml").read_text()
    idx = text.find("function tryUrl")
    assert idx != -1
    tail = text[idx:]
    marker = tail.find("function update()")
    assert marker != -1
    segment = tail[:marker]
    assert segment.count("{") == segment.count("}"), (
        "tryUrl is not closed before the next top-level function"
    )


def test_no_duplicate_property_bindings():
    text = pathlib.Path("deepseek-peak/Panel.qml").read_text()
    assert text.count("Layout.preferredWidth:") == 0, (
        "Panel sizes from implicit size + padding, not preferredWidth"
    )
    assert text.count("spacing: Style.margin") <= 2, (
        "Panel spacing set multiple times on one object"
    )
