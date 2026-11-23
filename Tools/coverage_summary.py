#!/usr/bin/env python3
"""Write the xccov JSON summary to the GitHub step summary and stdout."""

from __future__ import annotations

import json
import os
import sys


def percent(value: float) -> str:
    return f"{value * 100:.1f}%"


def main() -> int:
    path = sys.argv[1]
    data = json.load(open(path, encoding="utf-8"))
    targets = data.get("targets") or []
    apps = [
        target
        for target in targets
        if "test" not in target.get("name", "").lower()
        and target.get("name", "").startswith("TruckoRig")
    ]
    if not apps:
        names = ", ".join(target.get("name", "?") for target in targets) or "(none)"
        print(f"::error::No TruckoRig coverage target in {names}")
        return 1
    app = max(apps, key=lambda target: target.get("executableLines") or 0)
    executable = int(app.get("executableLines") or 0)
    covered = int(app.get("coveredLines") or 0)
    if executable <= 0:
        print(f"::error::{app.get('name')} has no executable lines. Coverage was not collected.")
        return 1
    line = app.get("lineCoverage")
    if line is None:
        line = covered / executable
    print(f"COVERAGE_PERCENT={line * 100:.1f}")
    print(f"Coverage {app.get('name')}: {percent(float(line))} ({covered}/{executable} lines)")

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as handle:
            handle.write("\n## Code coverage\n\n")
            handle.write("| Target | Line coverage | Covered | Executable |\n")
            handle.write("| --- | ---: | ---: | ---: |\n")
            overall = data.get("lineCoverage")
            if overall is not None:
                handle.write(
                    f"| All targets | {percent(float(overall))} | "
                    f"{data.get('coveredLines', '')} | {data.get('executableLines', '')} |\n"
                )
            for target in targets:
                target_line = target.get("lineCoverage")
                if target_line is None:
                    continue
                handle.write(
                    f"| {target.get('name', '')} | {percent(float(target_line))} | "
                    f"{target.get('coveredLines', '')} | {target.get('executableLines', '')} |\n"
                )
    return 0


if __name__ == "__main__":
    sys.exit(main())
