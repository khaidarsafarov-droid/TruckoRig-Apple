#!/usr/bin/env python3
"""Checks that the string catalog matches the keys the code actually uses.

Xcode only notices a missing translation when it builds, and there is no Xcode on CI, so this
compares the two directly:

  * every key used in Swift exists in Localizable.xcstrings
  * every key in the catalog is still used somewhere
  * every key has both English and Russian, and neither is blank
  * the number of format specifiers matches between the key, the English and the Russian

    python3 Tools/check_strings.py
"""

from __future__ import annotations

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, "TruckoRig", "Resources", "Localizable.xcstrings")
SOURCE_DIRS = ["TruckoRig", "TruckoRigWidget"]

# Only these namespaces are localized keys; everything else in quotes is an SF Symbol, a bundle
# identifier or plain data.
NAMESPACES = (
    "action.", "analytics.", "auth.", "camera.", "date.", "diesel.", "duration.", "error.",
    "format.", "gallery.", "goal.", "heatmap.", "journal.", "load.", "maintenance.", "map.",
    "media.", "paycheck.", "penalty.", "profile.", "relay.", "scanner.", "screen.", "settings.",
    "stat.", "status.", "stop.", "sync.", "tab.", "welcome.", "widget.", "app.name",
)

STRING_LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')
INTERPOLATION = re.compile(r"\\\(")


def base(key: str) -> str:
    """`sync.pending %lld` and `sync.pending \\(count)` both reduce to `sync.pending`."""
    return key.split(" ")[0]


def argument_count(text: str) -> int:
    return len(INTERPOLATION.findall(text)) + text.count("%lld") + text.count("%@")


def used_keys() -> dict[str, int]:
    """Base key -> number of interpolated arguments, as written in Swift."""
    found: dict[str, int] = {}
    for directory in SOURCE_DIRS:
        for current, _, filenames in os.walk(os.path.join(ROOT, directory)):
            for name in filenames:
                if not name.endswith(".swift"):
                    continue
                text = open(os.path.join(current, name), encoding="utf-8").read()
                for literal in STRING_LITERAL.findall(text):
                    if not literal.startswith(NAMESPACES):
                        continue
                    found[base(literal)] = argument_count(literal)
    return found


def main() -> int:
    catalog = json.load(open(CATALOG, encoding="utf-8"))
    strings = catalog["strings"]
    problems: list[str] = []

    declared = {base(key): key for key in strings}
    used = used_keys()

    for key in sorted(set(used) - set(declared)):
        problems.append(f"key used in code but missing from the catalog: {key}")

    for key in sorted(set(declared) - set(used)):
        problems.append(f"key in the catalog but unused in code: {declared[key]}")

    for key, entry in sorted(strings.items()):
        localizations = entry.get("localizations", {})
        for language in ("en", "ru"):
            value = localizations.get(language, {}).get("stringUnit", {}).get("value", "")
            if not value.strip():
                problems.append(f"{key}: missing or blank {language}")
                continue
            if argument_count(value) != argument_count(key):
                problems.append(f"{key}: {language} has a different number of format specifiers")

        expected = used.get(base(key))
        if expected is not None and expected != argument_count(key):
            problems.append(
                f"{key}: code passes {expected} arguments but the key declares {argument_count(key)}"
            )

    if problems:
        for problem in problems:
            print(f"error: {problem}")
        return 1

    print(f"Localizable.xcstrings OK — {len(strings)} keys, en + ru, specifiers consistent")
    return 0


if __name__ == "__main__":
    sys.exit(main())
