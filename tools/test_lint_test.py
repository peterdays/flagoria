#!/usr/bin/env python3
"""Tests for tools/test_lint.py. Run: python3 tools/test_lint_test.py"""
from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_lint as tl  # noqa: E402


def _write(root: Path, rel: str, body: str) -> None:
    p = root / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(body)


def test_duplicate_in_one_file() -> None:
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _write(root, "tests/run_tests.gd", "extends SceneTree\n")
        _write(root, "tests/a/test_a.gd", "func _test_x() -> int:\nfunc _test_x() -> int:\n")
        errs = tl.lint(root)
        assert any("duplicate test name x" in e for e in errs)


def test_duplicate_across_files() -> None:
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _write(root, "tests/run_tests.gd", "")
        _write(root, "tests/a/test_a.gd", "func _test_same() -> int:\n")
        _write(root, "tests/b/test_b.gd", "func _test_same() -> int:\n")
        errs = tl.lint(root)
        assert any("duplicate test name same" in e for e in errs)


def test_loose_test_prefix() -> None:
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _write(root, "tests/run_tests.gd", "")
        _write(root, "tests/a/test_a.gd", "func test_nope() -> int:\n")
        errs = tl.lint(root)
        assert any("test_nope" in e and "_test_" in e for e in errs)


def test_bad_signature_parameters() -> None:
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _write(root, "tests/run_tests.gd", "")
        _write(root, "tests/a/test_a.gd", "func _test_bad(p: int) -> int:\n")
        errs = tl.lint(root)
        assert any("_test_bad" in e and "parameters" in e for e in errs)


def test_real_tree_clean() -> None:
    errs = tl.lint(ROOT)
    assert not errs, errs


def test_cli_exits_nonzero() -> None:
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _write(root, "tests/run_tests.gd", "")
        _write(root, "tests/a/test_a.gd", "func test_bad() -> int:\n")
        proc = subprocess.run(
            [sys.executable, str(ROOT / "tools" / "test_lint.py"), "--root", str(root)],
            capture_output=True,
            text=True,
            cwd=ROOT,
            env={k: v for k, v in os.environ.items() if k != "PYTHONDONTWRITEBYTECODE"},
        )
        assert proc.returncode != 0
        assert "test_bad" in proc.stderr
        assert "tests/a/test_a.gd:1" in proc.stderr


def main() -> int:
    tests = [
        test_duplicate_in_one_file,
        test_duplicate_across_files,
        test_loose_test_prefix,
        test_bad_signature_parameters,
        test_real_tree_clean,
        test_cli_exits_nonzero,
    ]
    fail = 0
    for t in tests:
        try:
            t()
        except AssertionError as exc:
            fail += 1
            print(f"FAIL {t.__name__}: {exc}")
    print(f"test_lint_test: {len(tests) - fail}/{len(tests)} ok")
    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main())
