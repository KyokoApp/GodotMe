#!/usr/bin/env python3
"""Fast, dependency-free sanity check for the GDScript in this repo.

`godot --check-only` is the real gate (it runs in CI), but it needs a Godot
download and a full project import, so a five-minute CI round trip was once
spent on a single duplicated function. This catches that class of mistake in
under a second:

  * the same `func name(...)` declared twice in one file
  * a `func` declared twice with different indentation (a botched copy/paste)

Usage:  python3 tools/gd_dup_check.py [root ...]      (default: game launcher)
Exit:   0 clean, 1 problems found.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

FUNC_RE = re.compile(r"^(?P<indent>\t*)(?:static\s+)?func\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*\(")


def check_file(path: Path) -> list[str]:
    problems: list[str] = []
    seen: dict[str, int] = {}
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        match = FUNC_RE.match(line)
        if not match:
            continue
        name = match.group("name")
        if name in seen:
            problems.append(
                "%s:%d: '%s' sudah dideklarasikan di baris %d"
                % (path, number, name, seen[name])
            )
        else:
            seen[name] = number
    return problems


def main(argv: list[str]) -> int:
    roots = [Path(a) for a in argv[1:]] or [Path("game"), Path("launcher")]
    failures: list[str] = []
    count = 0
    for root in roots:
        if not root.exists():
            continue
        for path in sorted(root.rglob("*.gd")):
            if ".godot" in path.parts:
                continue
            count += 1
            failures.extend(check_file(path))
    for line in failures:
        print("FAIL " + line)
    print("[gd_dup_check] %d berkas, %d masalah" % (count, len(failures)))
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
