#!/usr/bin/env python3
"""Reject bare sleeps and unseeded randomness in netcode stress scenarios.

A stress scenario is a test tools/stress_netcode.py runs, plus any probe
script that scenario's file launches (a res://tests/*.gd path in the file).
The check fails on await _wait(, OS.delay_msec(, await create_timer(, or an
unseeded rand*()/randomize() in those functions. A wait that polls a condition
until a deadline is fine. A function that assigns .seed may use rand*.

tools/stress_scenario_lint_allow.txt lists legacy files and functions. Do not
add a new scenario to it.

The check does not follow helpers outside the scenario function and its probe.
Picking a free UDP port may stay random. Both are called out in AGENTS.md.

Run: python3 tools/stress_scenario_lint.py
Self-test: python3 tools/stress_scenario_lint.py --self-test
"""
from __future__ import annotations

import argparse
import importlib.util
import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ALLOW = "tools/stress_scenario_lint_allow.txt"
FUNC_RE = re.compile(r"^func (\w+)\(", re.M)
SLEEP_RE = re.compile(
    r"await\s+_wait\s*\(|\bOS\s*\.\s*delay_msec\s*\(|await\s+create_timer\s*\("
)
RAND_RE = re.compile(
    r"(?<![\w.])(randomize|randf_range|randi_range|randfn|randf|randi)\s*\("
)
SEED_RE = re.compile(r"\.seed\s*=|\bseed\s*\(")
# Top-level tests/*.gd probes only. tests/helpers/test_helpers.gd is extended by
# every test file and is not a stress probe.
PROBE_RE = re.compile(r"res://tests/([A-Za-z0-9_]+\.gd)")


def blank_comments(source: str) -> str:
    """Replace # comments with spaces so matches keep their line numbers."""
    return re.sub(r"#[^\n]*", lambda m: " " * len(m.group(0)), source)


def functions(source: str) -> list[tuple[str, int, int]]:
    starts = list(FUNC_RE.finditer(source))
    out = []
    for i, match in enumerate(starts):
        end = starts[i + 1].start() if i + 1 < len(starts) else len(source)
        out.append((match.group(1), match.end(), end))
    return out


def parse_allow(text: str) -> set[str]:
    allowed = set()
    for raw in text.splitlines():
        line = raw.split("#", 1)[0].strip()
        if line:
            allowed.add(line)
    return allowed


def lint_source(rel: str, source: str, allowed: set[str], names: set[str] | None = None) -> list[str]:
    """Diagnostics for one file. names limits which functions are scanned.

    None scans every function (a probe). A set scans only those function names
    (the scenario functions in a test file).
    """
    if rel in allowed:
        return []
    blank = blank_comments(source)
    errors = []
    for name, start, end in functions(blank):
        if names is not None and name not in names:
            continue
        if "%s::%s" % (rel, name) in allowed:
            continue
        body = blank[start:end]
        seeded = SEED_RE.search(body) is not None
        for match in SLEEP_RE.finditer(body):
            line = blank.count("\n", 0, start + match.start()) + 1
            errors.append(
                "%s:%d: %s: bare sleep; wait on explicit state with a bounded timeout"
                % (rel, line, name)
            )
        if seeded:
            continue
        for match in RAND_RE.finditer(body):
            line = blank.count("\n", 0, start + match.start()) + 1
            errors.append("%s:%d: %s: unseeded %s(); seed the generator" % (rel, line, name, match.group(1)))
    return errors


def load_stress(root: Path):
    path = root / "tools" / "stress_netcode.py"
    spec = importlib.util.spec_from_file_location("flagoria_stress_netcode_%s" % path.stat().st_mtime_ns, path)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load tools/stress_netcode.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def scenario_targets(root: Path) -> list[tuple[str, set[str] | None]]:
    """(relative path, function names or None for a whole probe) in scan order."""
    mod = load_stress(root)
    scenario_names = set(mod.net_scenarios(mod.test_sources()))
    func_names = {"_" + name for name in scenario_names}
    tests = root / "tests"
    files = sorted(tests.rglob("test_*.gd"), key=lambda p: p.relative_to(tests).as_posix())
    chosen: list[tuple[str, set[str] | None]] = []
    probes: set[str] = set()
    for path in files:
        source = path.read_text(encoding="utf-8", errors="replace")
        present = {name for name, _s, _e in functions(source) if name in func_names}
        if not present:
            continue
        rel = path.relative_to(root).as_posix()
        chosen.append((rel, present))
        for match in PROBE_RE.finditer(source):
            probes.add("tests/" + match.group(1))
    for rel in sorted(probes):
        chosen.append((rel, None))
    return chosen


def lint_repo(root: Path, allowed: set[str]) -> list[str]:
    errors = []
    for rel, names in scenario_targets(root):
        path = root / rel
        if not path.is_file():
            errors.append("%s: probe path does not exist" % rel)
            continue
        source = path.read_text(encoding="utf-8", errors="replace")
        errors.extend(lint_source(rel, source, allowed, names))
    return errors


def self_test() -> int:
    allowed = {"tests/old_probe.gd", "tests/wall_sync_probe.gd::_place_one_wall"}
    sleep = 'func _place_city():\n\tawait _wait(400)\n'
    settled = 'func _place_city():\n\tvar ok = await _until(func(): return true, 8000)\n'
    seeded = "func _roll():\n\trng.seed = 1\n\trandf()\n"
    bare_rand = "func _roll():\n\trandi()\n"
    cases = [
        ("tests/city_probe.gd", sleep, None, 1),
        ("tests/city_probe.gd", settled, None, 0),
        ("tests/old_probe.gd", sleep, None, 0),
        ("tests/wall_sync_probe.gd", "func _place_one_wall():\n\tawait _wait(400)\n", None, 0),
        ("tests/wall_sync_probe.gd", "func _place_city():\n\tOS.delay_msec(10)\n", None, 1),
        ("tests/roll.gd", seeded, None, 0),
        ("tests/roll.gd", bare_rand, None, 1),
        ("tests/only.gd", "func _test_keep():\n\tawait create_timer(1).timeout\nfunc _other():\n\tawait _wait(1)\n",
         {"_test_keep"}, 1),
    ]
    fail = 0
    for rel, source, names, want in cases:
        got = lint_source(rel, source, allowed, names)
        if len(got) != want:
            fail += 1
            print("case %s: want %d, got %s" % (rel, want, got), file=sys.stderr)
    # A comment must not count, and the real tree must be clean.
    commented = "func _place_city():\n\t# await _wait(400)\n\tpass\n"
    if lint_source("tests/c.gd", commented, set(), None):
        fail += 1
        print("comment was flagged", file=sys.stderr)
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "tests").mkdir()
        (root / "tools").mkdir()
        (root / "tests" / "test_one.gd").write_text(
            'const PROBE := "res://tests/demo_probe.gd"\nfunc _test_demo():\n\treturn 0\n',
            encoding="utf-8",
        )
        (root / "tests" / "demo_probe.gd").write_text("func run():\n\tawait _wait(5)\n", encoding="utf-8")
        (root / "tools" / "stress_netcode.py").write_text(
            "def test_sources():\n    return []\n"
            "def net_scenarios(_sources):\n    return ['test_demo']\n",
            encoding="utf-8",
        )
        got = lint_repo(root, set())
        if len(got) != 1:
            fail += 1
            print("repo case: %s" % got, file=sys.stderr)
    real = lint_repo(ROOT, parse_allow((ROOT / ALLOW).read_text(encoding="utf-8")))
    if real:
        fail += 1
        print("real tree:\n" + "\n".join(real), file=sys.stderr)
    print("stress_scenario_lint self-test: %s" % ("ok" if fail == 0 else "%d failed" % fail))
    return 1 if fail else 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--root", type=Path, default=ROOT)
    args = ap.parse_args()
    if args.self_test:
        return self_test()
    root = args.root
    allowed = parse_allow((root / ALLOW).read_text(encoding="utf-8"))
    errors = lint_repo(root, allowed)
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print("stress scenario lint: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
