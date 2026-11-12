#!/usr/bin/env python3
"""Decide whether verify.yml may skip Godot and tools/verify.sh.

Full verify is the default. The docs-only fast path applies only when every
changed path matches .github/verify-docs-only-allow.txt and none of the
force-full paths below appear in the change.

Allowlist and policy comments live in the allowlist file only; keep force-full
rules here.

  git diff --name-only origin/main...HEAD | python3 tools/verify_fast_path.py
  python3 tools/verify_fast_path.py --files paths.txt

Writes fast_path=true|false to $GITHUB_OUTPUT when set.

Self-test: python3 tools/verify_fast_path.py --self-test
"""
from __future__ import annotations

import argparse
import fnmatch
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ALLOW_FILE = ROOT / ".github" / "verify-docs-only-allow.txt"

# These paths always require full verify when present in the change (issue #456).
FORCE_FULL = (
    ".github/verify-docs-only-allow.txt",
    ".github/workflows/verify.yml",
    "tools/verify_fast_path.py",
)


def load_allowlist(path: Path = ALLOW_FILE) -> list[str]:
    patterns: list[str] = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if line:
            patterns.append(line)
    if not patterns:
        raise ValueError(f"verify fast path: no patterns in {path.name}")
    return patterns


def path_allowlisted(path: str, patterns: list[str]) -> bool:
    return any(fnmatch.fnmatchcase(path, pattern) for pattern in patterns)


def classify(paths: list[str], patterns: list[str] | None = None) -> tuple[bool, str]:
    """Return (fast_path, reason)."""
    if patterns is None:
        patterns = load_allowlist()
    if not paths:
        return False, "no changed paths"
    for path in paths:
        if path in FORCE_FULL:
            return False, "force-full path changed: " + path
    for path in paths:
        if not path_allowlisted(path, patterns):
            return False, "non-allowlisted path: " + path
    return True, "all %d path(s) allowlisted" % len(paths)


def read_paths(files: str | None) -> list[str]:
    if files:
        text = Path(files).read_text(encoding="utf-8", errors="replace")
    else:
        text = sys.stdin.read()
    return [line.strip() for line in text.splitlines() if line.strip()]


def self_test() -> int:
    patterns = load_allowlist()
    fail = 0

    def check(paths: list[str], want: bool, label: str) -> None:
        nonlocal fail
        got, reason = classify(paths, patterns)
        if got != want:
            print(
                "FAIL %s: paths=%r want fast_path=%s got %s (%s)"
                % (label, paths, want, got, reason),
                file=sys.stderr,
            )
            fail += 1

    check(["docs/architecture.md"], True, "docs")
    check(["README.md", "docs/tiles.md"], True, "readme and docs")
    check(
        [".cursor/skills/verify-flagoria/features/smoke.md"],
        True,
        "feature doc",
    )
    check(["Scripts/player.gd"], False, "gameplay script")
    check(["tools/verify.sh"], False, "verify script")
    check([".github/workflows/pr-hygiene.yml"], False, "other workflow")
    check([".github/verify-docs-only-allow.txt"], False, "allowlist edit")
    check([".github/workflows/verify.yml"], False, "verify workflow edit")
    check(["tools/verify_fast_path.py"], False, "classifier edit")
    check([], False, "empty paths")
    check(
        ["docs/audio.md", "Scripts/player.gd"],
        False,
        "mixed docs and code",
    )

    total = 11
    print("verify_fast_path self-test: %d/%d ok" % (total - fail, total))
    return 1 if fail else 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--files", help="changed paths, one per line (default: stdin)")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()
    if args.self_test:
        return self_test()
    paths = read_paths(args.files)
    patterns = load_allowlist()
    fast, reason = classify(paths, patterns)
    if fast:
        print("verify: docs-only fast path — %s" % reason)
        for path in paths:
            print("  allowlisted: " + path)
    else:
        print("verify: full path — %s" % reason)
        for path in paths:
            tag = "allowlisted" if path_allowlisted(path, patterns) else "not allowlisted"
            print("  %s: %s" % (tag, path))
    out = os.environ.get("GITHUB_OUTPUT")
    if out:
        with open(out, "a", encoding="utf-8") as fh:
            fh.write("fast_path=%s\n" % str(fast).lower())
    return 0


if __name__ == "__main__":
    sys.exit(main())
