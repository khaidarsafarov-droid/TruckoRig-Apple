#!/usr/bin/env python3
"""Checks that the string catalog matches the keys the code actually uses.

Xcode only notices a missing translation when it builds, and there is no Xcode on CI, so this
compares the two directly:

  * every key used in Swift exists in Localizable.xcstrings
  * every key in the catalog is still used somewhere
  * every key has English, Russian, French and Spanish, and none is blank
  * the number of format specifiers matches between the key and each language
  * French plural variations include `one` and `other`, and the singular/plural
    wording agrees where the catalog uses those forms
  * InfoPlist.xcstrings translates the permission strings, and en/es/ru stay
    equal to the strings already shipped in Info.plist

    python3 Tools/check_strings.py
"""

from __future__ import annotations

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, "TruckoRig", "Resources", "Localizable.xcstrings")
INFO_CATALOG = os.path.join(ROOT, "TruckoRig", "Resources", "InfoPlist.xcstrings")
INFO_PLIST = os.path.join(ROOT, "TruckoRig", "Resources", "Info.plist")
PROJECT = os.path.join(ROOT, "TruckoRig.xcodeproj", "project.pbxproj")
SOURCE_DIRS = ["TruckoRig", "TruckoRigWidget"]

# Only these namespaces are localized keys; everything else in quotes is an SF Symbol, a bundle
# identifier or plain data.
NAMESPACES = (
    "about.", "action.", "analytics.", "attach.", "auth.", "camera.", "date.", "diesel.", "duration.", "error.",
    "expense.", "format.", "gallery.", "goal.", "heatmap.", "home.", "improve.", "journal.", "load.", "maintenance.", "map.",
    "media.", "onboard.", "paycheck.", "penalty.", "premium.", "privacy.", "profile.", "receipt.", "relay.", "scanner.", "screen.",
    "settings.", "stat.", "status.", "stop.", "tab.", "tax.", "widget.", "app.name", "notify.",
)

# French plural pairs: the `one` form must contain the singular word and not the
# plural word; `other` must contain the plural word.
FRENCH_PLURALS = {
    "duration.days %lld": ("jour", "jours"),
    "journal.week.summary %lld %@": ("voyage", "voyages"),
    "relay.parsed.many %lld": ("voyage", "voyages"),
    "settings.backup.saved %lld %@": ("voyage", "voyages"),
    "scanner.pages %lld": ("page", "pages"),
    "scanner.sessionCount %lld": ("numérisation", "numérisations"),
    "maintenance.days.left %lld": ("jour", "jours"),
    "maintenance.overdue %lld": ("jour", "jours"),
    "goal.days.left.chip %lld": ("jour", "jours"),
    "tax.calendar.subtitle %lld %lld": ("Jour", "Jours"),
    "tax.inDays %lld": ("jour", "jours"),
    "tax.perDiem %lld %@": ("jour", "jours"),
    "map.subtitle.week %lld": ("voyage", "voyages"),
    "map.subtitle.month %lld": ("voyage", "voyages"),
    "map.subtitle.year %lld": ("voyage", "voyages"),
    "notify.maintenance.tasks %lld %@": ("tâche", "tâches"),
}

# Keys the code selects itself. French still has to agree.
FRENCH_FIXED_PLURALS = {
    "load.card.stops.one %lld": ("arrêt", "arrêts"),
}

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


def forms(localization: dict) -> dict[str, str]:
    """Name of the form -> translated text. `stringUnit` is a single form."""
    if "variations" in localization:
        plural = localization.get("variations", {}).get("plural", {})
        return {
            name: item.get("stringUnit", {}).get("value", "")
            for name, item in plural.items()
        }
    return {"stringUnit": localization.get("stringUnit", {}).get("value", "")}


def check_language(key: str, localization: dict | None, language: str, problems: list[str]) -> None:
    if not localization:
        problems.append(f"{key}: missing or blank {language}")
        return
    translated = forms(localization)
    if not translated:
        problems.append(f"{key}: missing or blank {language}")
        return
    if language == "fr" and "variations" in localization:
        missing = {"one", "other"} - set(translated)
        if missing:
            problems.append(f"{key}: fr plural is missing {', '.join(sorted(missing))}")
    for name, value in translated.items():
        if not value.strip():
            problems.append(f"{key}: missing or blank {language} ({name})")
            continue
        if argument_count(value) != argument_count(key):
            problems.append(f"{key}: {language} ({name}) has a different number of format specifiers")


def check_french_plurals(key: str, localization: dict, problems: list[str]) -> None:
    pair = FRENCH_PLURALS.get(key)
    if pair:
        singular, plural = pair
        translated = forms(localization)
        one = translated.get("one", "")
        other = translated.get("other", "")
        if plural in one or singular not in one:
            problems.append(f"{key}: fr plural `one` must use « {singular} »")
        if plural not in other:
            problems.append(f"{key}: fr plural `other` must use « {plural} »")
        return
    fixed = FRENCH_FIXED_PLURALS.get(key)
    if not fixed:
        return
    singular, plural = fixed
    value = forms(localization).get("stringUnit", "")
    if plural in value or singular not in value:
        problems.append(f"{key}: fr must use « {singular} »")


def check_info_plist(problems: list[str]) -> None:
    import re

    plist = open(INFO_PLIST, encoding="utf-8").read()
    shipped = dict(re.findall(r"<key>(NS(?:Camera|PhotoLibrary|LocationWhenInUse)UsageDescription)</key>\s*<string>(.*?)</string>", plist, re.S))
    catalog = json.load(open(INFO_CATALOG, encoding="utf-8"))["strings"]
    if set(catalog) != set(shipped):
        problems.append(f"InfoPlist.xcstrings keys {sorted(catalog)} != Info.plist {sorted(shipped)}")
    for key, entry in catalog.items():
        localizations = entry.get("localizations", {})
        for language in ("en", "es", "ru"):
            value = localizations.get(language, {}).get("stringUnit", {}).get("value", "")
            if value != shipped.get(key, ""):
                problems.append(f"{key}: {language} permission text changed")
        french = localizations.get("fr", {}).get("stringUnit", {}).get("value", "")
        if not french.strip():
            problems.append(f"{key}: missing or blank fr")
        elif french == shipped.get(key):
            problems.append(f"{key}: fr permission text is still the untranslated string")


def check_project_regions(problems: list[str]) -> None:
    text = open(PROJECT, encoding="utf-8").read()
    start = text.find("knownRegions = (")
    end = text.find(");", start)
    block = text[start:end]
    for region in ("en", "es", "fr", "ru", "Base"):
        if f"\t\t\t\t{region}," not in block and f"\t\t\t\t{region}\n" not in block:
            # Base and others are written as `\t\t\t\tfr,`
            if f"{region}," not in block:
                problems.append(f"knownRegions is missing {region}")


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
        for language in ("en", "ru", "fr", "es"):
            check_language(key, localizations.get(language), language, problems)
        if "fr" in localizations:
            check_french_plurals(key, localizations["fr"], problems)

        expected = used.get(base(key))
        if expected is not None and expected != argument_count(key):
            problems.append(
                f"{key}: code passes {expected} arguments but the key declares {argument_count(key)}"
            )

    check_info_plist(problems)
    check_project_regions(problems)

    if problems:
        for problem in problems:
            print(f"error: {problem}")
        return 1

    print(f"Localizable.xcstrings OK — {len(strings)} keys, en + ru + fr + es, specifiers consistent")
    return 0


if __name__ == "__main__":
    sys.exit(main())
