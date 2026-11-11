#!/usr/bin/env python3
"""Self-test for tools/required_checks.py. Run: python3 tools/required_checks_test.py"""
from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import required_checks as rc  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
FAILED = 0


def check(name: str, ok: bool, detail: str = "") -> None:
    global FAILED
    FAILED += not ok
    if not ok:
        print(f"FAIL {name}: {detail}")


def run() -> int:
    global FAILED
    FAILED = 0

    check("current tree", rc.check_tree() == [])

    err = subprocess.run(
        [sys.executable, str(ROOT / "tools" / "required_checks.py")],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    check("cli exit 0", err.returncode == 0, err.stderr)

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        workflows = root / ".github" / "workflows"
        workflows.mkdir(parents=True)
        list_path = root / ".github" / "required-checks.txt"
        list_path.write_text(
            "demo.yml job Demo check\n",
            encoding="utf-8",
        )
        (workflows / "demo.yml").write_text(
            "jobs:\n  job:\n    name: Demo check\n    runs-on: ubuntu-latest\n",
            encoding="utf-8",
        )
        check("fixture match", rc.check_tree(root) == [])

        (workflows / "demo.yml").write_text(
            "jobs:\n  job:\n    name: Renamed check\n    runs-on: ubuntu-latest\n",
            encoding="utf-8",
        )
        mismatch = rc.check_tree(root)
        check("fixture mismatch", len(mismatch) == 1 and "Renamed check" in mismatch[0])
        check("fixture committed side", len(mismatch) == 1 and "Demo check" in mismatch[0])

    print(f"required_checks_test: {FAILED} failed")
    return 1 if FAILED else 0


def main() -> int:
    return run()


if __name__ == "__main__":
    raise SystemExit(main())
