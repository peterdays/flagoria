#!/usr/bin/env python3
"""Static lint for the headless test registry (tests/run_tests.gd).

Mirrors discovery in tests/run_tests.gd so mistakes (duplicate `_test_*` names,
misnamed `test_*` functions, wrong signatures) fail before Godot runs the suite.

Run: python3 tools/test_lint.py [--root DIR]
Self-test: python3 tools/test_lint.py --self-test
"""
from __future__ import annotations

import argparse
import re
import sys
import tempfile
from pathlib import Path

RUNNER = "tests/run_tests.gd"
REGISTERED_RE = re.compile(r"(?m)^func (_test_[a-z0-9_]+)\(\)")
LOOSE_RE = re.compile(
    r"(?mi)^([ \t]*)(static[ \t]+)?func[ \t]+(_?test_\w*)[ \t]*\(([^)]*)\)"
)
EXACT_RE = re.compile(r"^func _test_[a-z0-9_]+\(\)$")


def test_paths(root: Path) -> list[Path]:
    tests = root / "tests"
    paths = sorted(tests.rglob("test_*.gd"), key=lambda p: p.relative_to(tests).as_posix())
    runner = root / RUNNER
    if runner.is_file():
        paths.append(runner)
    paths.sort(key=lambda p: p.relative_to(root).as_posix())
    return paths


def line_number(source: str, index: int) -> int:
    return source.count("\n", 0, index) + 1


def lint_source(rel: str, source: str) -> list[str]:
    """Diagnostics for loose or mis-registered test-like functions in one file."""
    found: list[str] = []
    errors: list[str] = []
    for m in REGISTERED_RE.finditer(source):
        found.append(m.group(1))
    for m in LOOSE_RE.finditer(source):
        if EXACT_RE.match(m.group(0)):
            continue
        test_name = m.group(3)
        reasons: list[str] = []
        if m.group(1):
            reasons.append("it is indented; tests must be top-level")
        if m.group(2):
            reasons.append("it is static; drop `static`")
        if not test_name.lower().startswith("_test_"):
            reasons.append("the name must start with `_test_`")
        if test_name != test_name.lower():
            reasons.append("the name has uppercase letters; use lowercase")
        if m.group(4).strip():
            reasons.append("it takes parameters; tests take none")
        if not reasons:
            reasons.append("write it exactly as `func _test_<lowercase_name>()`")
        if test_name in found:
            reasons.append(f"the top-level {test_name} is the one that runs")
        line = line_number(source, m.start())
        errors.append(f"{rel}:{line}: {test_name}: {'; '.join(reasons)}")
    return errors


def lint(root: Path) -> list[str]:
    errors: list[str] = []
    by_name: dict[str, list[tuple[str, int]]] = {}
    for path in test_paths(root):
        rel = path.relative_to(root).as_posix()
        source = path.read_text(encoding="utf-8", errors="replace")
        errors.extend(lint_source(rel, source))
        for m in REGISTERED_RE.finditer(source):
            by_name.setdefault(m.group(1), []).append((rel, line_number(source, m.start())))
    for name, sites in by_name.items():
        if len(sites) < 2:
            continue
        short = name.removeprefix("_test_")
        for rel, line in sites:
            others = ", ".join(f"{r}:{ln}" for r, ln in sites if (r, ln) != (rel, line))
            errors.append(f"{rel}:{line}: duplicate test name {short} (also {others})")
    return errors


def self_test() -> int:
    fail = 0
    cases = [
        (
            {
                "tests/run_tests.gd": "extends SceneTree\n",
                "tests/x/test_a.gd": "func _test_dup() -> int:\nfunc _test_dup() -> int:\n",
            },
            ["duplicate test name dup"],
        ),
        (
            {
                "tests/run_tests.gd": "",
                "tests/x/test_a.gd": "func _test_one() -> int:\n",
                "tests/y/test_b.gd": "func _test_one() -> int:\n",
            },
            ["duplicate test name one"],
        ),
        (
            {"tests/run_tests.gd": "", "tests/x/test_a.gd": "func test_loose() -> int:\n"},
            ["test_loose", "the name must start with `_test_`"],
        ),
        (
            {"tests/run_tests.gd": "", "tests/x/test_a.gd": "func _test_args(x: int) -> int:\n"},
            ["_test_args", "it takes parameters"],
        ),
    ]
    for i, (files, needles) in enumerate(cases, 1):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            for rel, body in files.items():
                p = root / rel
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text(body)
            got = lint(root)
            for needle in needles:
                if not any(needle in line for line in got):
                    fail += 1
                    print(f"case {i}: want {needle!r} in {got}")
    # Clean project should lint ok when copied from real tree — only check structure here.
    print(f"test_lint self-test: {len(cases) - fail}/{len(cases)} cases ok" if fail else "test_lint self-test: ok")
    return 1 if fail else 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--root", default=str(Path(__file__).resolve().parent.parent))
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args(argv)
    if args.self_test:
        return self_test()
    root = Path(args.root)
    errors = lint(root)
    for e in errors:
        print(f"error: {e}", file=sys.stderr)
    if errors:
        print(f"Test registry lint: {len(errors)} problem(s)", file=sys.stderr)
        return 1
    n_files = len(test_paths(root))
    print(f"Test registry lint: ok ({n_files} files)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
