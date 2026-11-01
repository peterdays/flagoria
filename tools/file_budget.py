#!/usr/bin/env python3
"""File size budget: keep each script small enough to read whole.

Fails (exit 1) when a file is over its line budget:
  * a .gd file under Scripts/ (any depth), or flagoria_main.gd: 500 lines;
  * a .gd file under tests/ (any depth): 1,500 lines.

A file may go over its budget only when tools/file_budget_allow.txt lists it.
One entry per line, "#" starts a comment:
  <path> <cap> <reason>
<cap> is the most lines the file may have, normally its size when it was
listed, so it cannot grow. <reason> says why this file may stay large, in at
least four words. An entry also fails when its file is gone, its cap is not
over the budget, or the file has dropped to the budget or under (remove the
entry then).

Run: python3 tools/file_budget.py [--root DIR] [--allow FILE]
Self-test: python3 tools/file_budget.py --self-test
"""
from __future__ import annotations

import argparse
import sys
import tempfile
from pathlib import Path

SCRIPT_BUDGET = 500
TEST_BUDGET = 1500
ALLOW = "tools/file_budget_allow.txt"
MIN_REASON_WORDS = 4


def budgeted_files(root: Path) -> dict[str, int]:
    """Relative path -> budget for every file the check covers."""
    out: dict[str, int] = {}
    for p in sorted((root / "Scripts").rglob("*.gd")):
        out[p.relative_to(root).as_posix()] = SCRIPT_BUDGET
    if (root / "flagoria_main.gd").is_file():
        out["flagoria_main.gd"] = SCRIPT_BUDGET
    for p in sorted((root / "tests").rglob("*.gd")):
        out[p.relative_to(root).as_posix()] = TEST_BUDGET
    return out


def count_lines(path: Path) -> int:
    return len(path.read_text(encoding="utf-8", errors="replace").splitlines())


def parse_allow(text: str) -> tuple[dict[str, int], list[str]]:
    """Allowlist text -> ({path: cap}, errors)."""
    caps: dict[str, int] = {}
    errors: list[str] = []
    for n, raw in enumerate(text.splitlines(), 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        parts = line.split(None, 2)
        if len(parts) < 2 or not parts[1].isdigit():
            errors.append(f"{ALLOW}:{n}: expected '<path> <cap> <reason>', got: {raw.strip()}")
            continue
        reason = parts[2] if len(parts) == 3 else ""
        if len(reason.split()) < MIN_REASON_WORDS:
            errors.append(f"{ALLOW}:{n}: {parts[0]}: give a specific reason of at least {MIN_REASON_WORDS} words")
        caps[parts[0]] = int(parts[1])
    return caps, errors


def check(root: Path, allow_text: str) -> list[str]:
    files = budgeted_files(root)
    caps, errors = parse_allow(allow_text)
    for path, budget in files.items():
        lines = count_lines(root / path)
        cap = caps.get(path)
        if cap is None and lines > budget:
            errors.append(f"{path}: {lines} lines, over the {budget}-line budget. Split it, or list it in {ALLOW} with a reason.")
        elif cap is not None and lines > cap:
            errors.append(f"{path}: {lines} lines, over its cap of {cap} in {ALLOW}. Split it rather than raising the cap.")
        elif cap is not None and lines <= budget:
            errors.append(f"{path}: {lines} lines, within the {budget}-line budget. Remove its entry from {ALLOW}.")
    for path, cap in caps.items():
        if path not in files:
            errors.append(f"{ALLOW}: {path} is not a budgeted file (missing or moved). Remove or fix the entry.")
        elif cap <= files[path]:
            errors.append(f"{ALLOW}: {path} cap {cap} is not over the {files[path]}-line budget. Remove the entry.")
    return errors


def self_test() -> int:
    reason = "data table of tile names"
    cases = [
        # (files {path: lines}, allowlist text, expected failure count)
        ({"Scripts/a.gd": 500, "flagoria_main.gd": 10, "tests/t.gd": 1500}, "", 0),
        ({"Scripts/a.gd": 501}, "", 1),
        ({"Scripts/deep/er/a.gd": 501}, "", 1),
        ({"flagoria_main.gd": 501}, "", 1),
        ({"tests/x/t.gd": 1501}, "", 1),
        ({"tools/big.gd": 5000, "Scripts/a.txt": 5000}, "", 0),
        ({"Scripts/a.gd": 600}, f"Scripts/a.gd 600 {reason}\n", 0),
        ({"Scripts/a.gd": 601}, f"Scripts/a.gd 600 {reason}\n", 1),
        ({"Scripts/a.gd": 600}, "Scripts/a.gd 600 data\n", 1),
        ({"Scripts/a.gd": 600}, "Scripts/a.gd 600\n", 1),
        ({"Scripts/a.gd": 600}, f"Scripts/a.gd big {reason}\n", 2),
        ({"Scripts/a.gd": 400}, f"Scripts/a.gd 600 {reason}\n", 1),
        ({"Scripts/a.gd": 10}, f"Scripts/a.gd 450 {reason}\n", 2),
        ({}, f"Scripts/gone.gd 600 {reason}\n", 1),
        ({"Scripts/a.gd": 600}, f"# comment\n\nScripts/a.gd 600 {reason}  # trailing\n", 0),
    ]
    fail = 0
    for i, (files, allow, want) in enumerate(cases, 1):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            for rel, n in files.items():
                p = root / rel
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text("x\n" * n)
            got = check(root, allow)
        if len(got) != want:
            fail += 1
            print(f"case {i}: want {want} failure(s), got {len(got)}: {got}")
    print(f"file_budget self-test: {len(cases) - fail}/{len(cases)} ok")
    return 1 if fail else 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--root", default=str(Path(__file__).resolve().parent.parent))
    ap.add_argument("--allow", help=f"allowlist file (default: <root>/{ALLOW})")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args(argv)
    if args.self_test:
        return self_test()
    root = Path(args.root)
    allow = Path(args.allow) if args.allow else root / ALLOW
    errors = check(root, allow.read_text(encoding="utf-8") if allow.is_file() else "")
    for e in errors:
        print(f"error: {e}", file=sys.stderr)
    if errors:
        print(f"File budget: {len(errors)} problem(s)", file=sys.stderr)
        return 1
    print(f"File budget: ok ({len(budgeted_files(root))} files)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
