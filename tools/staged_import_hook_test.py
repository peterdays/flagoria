#!/usr/bin/env python3
"""Synthetic-repo tests for tools/staged_import_hook.py.

Part of the local hook test suite. Run: python3 tools/staged_import_hook_test.py
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import staged_import_hook as hook  # noqa: E402


def run(args: list[str], repo: Path, env: dict[str, str] | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
    merged = os.environ.copy()
    if env:
        merged.update(env)
    result = subprocess.run(args, cwd=repo, capture_output=True, text=True, env=merged)
    if check and result.returncode != 0:
        raise SystemExit(f"{args} -> {result.returncode}\n{result.stdout}\n{result.stderr}")
    return result


def git(repo: Path, *args: str, env: dict[str, str] | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
    return run(["git", *args], repo, env=env, check=check)


def init_repo(root: Path, name: str) -> Path:
    work = root / name
    git(root, "init", "-b", "main", str(work))
    git(work, "config", "commit.gpgsign", "false")
    git(work, "config", "user.name", "Hook Tester")
    git(work, "config", "user.email", "hook.tester@example.com")
    tools = work / "tools"
    tools.mkdir()
    here = Path(__file__).resolve().parent
    shutil.copy(here / "staged_import_hook.py", tools / "staged_import_hook.py")
    return work


def write_asset_pair(repo: Path, rel: str = "art/sprite.png") -> tuple[Path, Path]:
    asset = repo / rel
    asset.parent.mkdir(parents=True, exist_ok=True)
    asset.write_bytes(b"\x89PNG\r\n")
    import_side = Path(str(asset) + ".import")
    import_side.write_text(
        "[remap]\n\nimporter=\"texture\"\n",
        encoding="utf-8",
    )
    return asset, import_side


def test_rejects_import_without_asset(root: Path) -> None:
    repo = init_repo(root, "reject")
    hook.install(str(repo))
    asset, import_side = write_asset_pair(repo)
    git(repo, "add", str(import_side.relative_to(repo)))
    result = git(repo, "commit", "-m", "import only", check=False)
    if result.returncode == 0:
        raise SystemExit("commit should have been rejected")
    if "staged import:" not in result.stderr or str(asset.relative_to(repo)) not in result.stderr:
        raise SystemExit(f"unexpected stderr: {result.stderr}")


def test_accepts_import_with_asset(root: Path) -> None:
    repo = init_repo(root, "accept")
    hook.install(str(repo))
    asset, import_side = write_asset_pair(repo, "data/icon.png")
    git(repo, "add", str(asset.relative_to(repo)), str(import_side.relative_to(repo)))
    result = git(repo, "commit", "-m", "asset and import", check=False)
    if result.returncode != 0:
        raise SystemExit(f"commit should have passed: {result.stderr}")


def test_opt_out_env_allows_import_only(root: Path) -> None:
    repo = init_repo(root, "optout")
    hook.install(str(repo))
    _asset, import_side = write_asset_pair(repo, "textures/foo.tres")
    git(repo, "add", str(import_side.relative_to(repo)))
    result = git(repo, "commit", "-m", "import only ok", env={hook.OPT_OUT_ENV: "1"}, check=False)
    if result.returncode != 0:
        raise SystemExit(f"opt-out commit should have passed: {result.stderr}")


def main() -> int:
    root = Path(tempfile.mkdtemp(prefix="staged-import-"))
    try:
        tests = [
            test_rejects_import_without_asset,
            test_accepts_import_with_asset,
            test_opt_out_env_allows_import_only,
        ]
        for test in tests:
            test(root)
            print(f"ok {test.__name__}")
    finally:
        shutil.rmtree(root, ignore_errors=True)
    print(f"ok {len(tests)} tests")
    return 0


if __name__ == "__main__":
    sys.exit(main())
