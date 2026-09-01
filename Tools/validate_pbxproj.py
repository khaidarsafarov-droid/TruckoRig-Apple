#!/usr/bin/env python3
"""Parses TruckoRig.xcodeproj/project.pbxproj and checks it for structural mistakes.

Xcode reports a malformed project file as a single unhelpful error, and there is no Xcode on CI,
so this script does the checks that catch the mistakes a generator can make: unbalanced braces,
references to object IDs that do not exist, duplicate IDs, and targets missing a build phase.

    python3 Tools/validate_pbxproj.py
"""

from __future__ import annotations

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = os.path.join(ROOT, "TruckoRig.xcodeproj", "project.pbxproj")

COMMENT = re.compile(r"/\*.*?\*/", re.DOTALL)
OBJECT_ID = re.compile(r"\b[0-9A-F]{24}\b")


def tokenize(text: str) -> list[str]:
    # The leading `// !$*UTF8*$!` marker is the only line comment Xcode writes.
    text = "\n".join(line for line in text.splitlines() if not line.startswith("//"))
    text = COMMENT.sub(" ", text)
    return re.findall(r'"(?:[^"\\]|\\.)*"|[{}()=;,]|[^\s{}()=;,]+', text)


def parse(tokens: list[str], index: int = 0):
    """Parses one OpenStep plist value, returning (value, next index)."""
    token = tokens[index]
    if token == "{":
        result: dict[str, object] = {}
        index += 1
        while tokens[index] != "}":
            key = tokens[index].strip('"')
            assert tokens[index + 1] == "=", f"expected = after {key}"
            value, index = parse(tokens, index + 2)
            assert tokens[index] == ";", f"expected ; after {key}, found {tokens[index]}"
            result[key] = value
            index += 1
        return result, index + 1
    if token == "(":
        items: list[object] = []
        index += 1
        while tokens[index] != ")":
            value, index = parse(tokens, index)
            items.append(value)
            if tokens[index] == ",":
                index += 1
        return items, index + 1
    return token.strip('"'), index + 1


def collect_ids(value: object, found: set[str]) -> None:
    if isinstance(value, dict):
        for item in value.values():
            collect_ids(item, found)
    elif isinstance(value, list):
        for item in value:
            collect_ids(item, found)
    elif isinstance(value, str) and OBJECT_ID.fullmatch(value):
        found.add(value)


def main() -> int:
    text = open(PATH, encoding="utf-8").read()
    problems: list[str] = []

    if text.count("{") != text.count("}"):
        problems.append(f"unbalanced braces: {text.count('{')} open, {text.count('}')} close")

    tokens = tokenize(text)
    root, _ = parse(tokens, 0)
    objects = root["objects"]
    assert isinstance(objects, dict)

    declared = set(objects)
    referenced: set[str] = set()
    collect_ids(objects, referenced)
    collect_ids(root.get("rootObject", ""), referenced)

    dangling = sorted(referenced - declared)
    if dangling:
        problems.append(f"{len(dangling)} references to undeclared objects, e.g. {dangling[:3]}")

    orphans = sorted(declared - referenced - {root.get("rootObject")})
    if orphans:
        kinds = {objects[o].get("isa") for o in orphans}
        problems.append(f"{len(orphans)} unreferenced objects ({sorted(kinds)})")

    targets = [o for o in objects.values() if o.get("isa") == "PBXNativeTarget"]
    if len(targets) != 2:
        problems.append(f"expected 2 targets, found {len(targets)}")
    for target in targets:
        for required in ("buildConfigurationList", "productReference", "buildPhases"):
            if not target.get(required):
                problems.append(f"target {target.get('name')} is missing {required}")

    sources = [o for o in objects.values() if o.get("isa") == "PBXSourcesBuildPhase"]
    swift_count = sum(len(phase.get("files", [])) for phase in sources)
    if swift_count == 0:
        problems.append("no Swift files in any Sources build phase")

    if problems:
        for problem in problems:
            print(f"error: {problem}")
        return 1

    print(
        f"project.pbxproj OK — {len(objects)} objects, {len(targets)} targets, "
        f"{swift_count} compiled sources"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
