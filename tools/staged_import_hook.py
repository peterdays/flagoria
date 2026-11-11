#!/usr/bin/env python3
"""Local pre-commit guard for staged Godot .import files.

Off until this checkout runs:

    python3 tools/staged_import_hook.py install

Install wires the check through the hooks path already in use. It does not
change core.hooksPath and does not remove other hooks.

Rejects a commit when a staged ``*.import`` file is not staged together with
its source asset (the path without the trailing ``.import``). Set
``FLAGORIA_ALLOW_IMPORT_ONLY=1`` or ``git config flagoria.allowImportOnly true``
for an intentional import-only commit (for example a project-wide re-import).
"""
from __future__ import annotations

import os
import stat
import subprocess
import sys
from pathlib import Path

MARKER = "flagoria-staged-import-hook"
CHAIN_MARKER = "flagoria-staged-import-chain"
HOOK_NAME = "pre-commit"
OPT_OUT_ENV = "FLAGORIA_ALLOW_IMPORT_ONLY"
OPT_OUT_CONFIG = "flagoria.allowImportOnly"

SHIM = f"""#!/bin/sh
# {MARKER}
set -e
root=$(git rev-parse --show-toplevel) || exit 1
exec python3 "$root/tools/staged_import_hook.py" {HOOK_NAME} "$@"
"""

CHAIN = f"""#!/bin/sh
# {CHAIN_MARKER}
here=$(CDPATH= cd -- "$(dirname "$0")" && pwd) || exit 1
if [ -x "$here/{HOOK_NAME}.flagoria-previous" ]; then
  "$here/{HOOK_NAME}.flagoria-previous" "$@"
  status=$?
  [ "$status" -eq 0 ] || exit "$status"
fi
"$here/{HOOK_NAME}.flagoria-import" "$@"
exit $?
"""


class HookFailure(Exception):
    pass


def git(repo: str, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        ["git", *args],
        cwd=repo,
        capture_output=True,
        text=True,
    )
    if check and result.returncode != 0:
        raise HookFailure("staged import: git command failed")
    return result


def work_tree(repo: str) -> Path:
    result = git(repo, "rev-parse", "--show-toplevel")
    return Path(result.stdout.strip())


def git_hooks_dir(repo: str) -> Path:
    common = git(repo, "rev-parse", "--git-common-dir").stdout.strip()
    path = Path(common)
    if not path.is_absolute():
        path = work_tree(repo) / path
    hooks = path / "hooks"
    hooks.mkdir(parents=True, exist_ok=True)
    return hooks


def effective_hooks_path(repo: str) -> Path | None:
    result = git(repo, "config", "--get", "core.hooksPath", check=False)
    if result.returncode != 0:
        return None
    raw = result.stdout.strip()
    if not raw:
        return None
    path = Path(raw)
    if not path.is_absolute():
        path = work_tree(repo) / path
    return path


def within(path: Path, root: Path) -> bool:
    try:
        path.resolve().relative_to(root.resolve())
    except ValueError:
        return False
    return True


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def is_ours(path: Path, marker: str) -> bool:
    return path.is_file() and marker in read_text(path)


def delegates_to_git_hooks(hooks_path: Path, git_hooks: Path) -> bool:
    marker = hooks_path / ".cursor-original-hooks-path"
    if not marker.is_file():
        return False
    target = Path(marker.read_text(encoding="utf-8").strip())
    if not target.is_absolute():
        target = (hooks_path / target).resolve()
    return target.resolve() == git_hooks.resolve()


def entry_calls_original(hooks_path: Path) -> bool:
    entry = hooks_path / HOOK_NAME
    if entry.is_symlink() and os.readlink(entry) == ".dispatcher":
        return True
    if entry.is_file():
        return ".cursor-original-hooks-path" in read_text(entry)
    return False


def write_exec(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)


def install_shim(dest: Path) -> None:
    current = dest / HOOK_NAME
    identity = dest / f"{HOOK_NAME}.flagoria-import"
    if is_ours(current, MARKER) and not is_ours(current, CHAIN_MARKER):
        write_exec(current, SHIM)
        return
    if is_ours(current, CHAIN_MARKER):
        write_exec(current, CHAIN)
        write_exec(identity, SHIM)
        return
    if current.exists() or current.is_symlink():
        previous = dest / f"{HOOK_NAME}.flagoria-previous"
        if previous.exists() or previous.is_symlink():
            raise HookFailure(f"staged import: {HOOK_NAME} already has a saved previous hook")
        current.rename(previous)
        write_exec(identity, SHIM)
        write_exec(current, CHAIN)
        return
    write_exec(current, SHIM)


def link_dispatcher_entry(hooks_path: Path) -> None:
    entry = hooks_path / HOOK_NAME
    if entry.exists() or entry.is_symlink():
        if not entry_calls_original(hooks_path):
            raise HookFailure(
                f"staged import: active {HOOK_NAME} does not run the checkout hooks; left unchanged"
            )
        return
    dispatcher = hooks_path / ".dispatcher"
    if not dispatcher.is_file():
        raise HookFailure(
            f"staged import: active hooks path has no {HOOK_NAME} entry; left unchanged"
        )
    entry.symlink_to(".dispatcher")


def install(repo: str) -> None:
    git_hooks = git_hooks_dir(repo)
    configured = effective_hooks_path(repo)
    if configured is None:
        install_shim(git_hooks)
        print("staged import: installed for this checkout")
        return
    if delegates_to_git_hooks(configured, git_hooks):
        link_dispatcher_entry(configured)
        install_shim(git_hooks)
        print("staged import: installed for this checkout")
        print(f"staged import: {HOOK_NAME} runs through the active hooks path")
        return
    if within(configured, work_tree(repo)) or within(configured, git_hooks.parent):
        install_shim(configured)
        print("staged import: installed for this checkout")
        return
    raise HookFailure(
        "staged import: active hooks path is outside this checkout and does not chain; left unchanged"
    )


def asset_path(import_path: str) -> str:
    if import_path.endswith(".import"):
        return import_path[: -len(".import")]
    return import_path


def opt_out(repo: str) -> bool:
    if os.environ.get(OPT_OUT_ENV) == "1":
        return True
    result = git(repo, "config", "--local", "--get", OPT_OUT_CONFIG, check=False)
    if result.returncode != 0:
        return False
    value = result.stdout.strip().lower()
    return value in ("1", "true", "yes")


def staged_paths(repo: str) -> list[str]:
    result = git(repo, "diff", "--cached", "--name-only", "--diff-filter=ACM")
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def check_commit(repo: str) -> list[str]:
    if opt_out(repo):
        return []
    staged = staged_paths(repo)
    staged_set = set(staged)
    errors: list[str] = []
    for path in staged:
        if not path.endswith(".import"):
            continue
        asset = asset_path(path)
        if asset in staged_set:
            continue
        errors.append(
            "staged import: "
            f"{path} is staged without its asset {asset!r}; "
            f"stage the asset too or set {OPT_OUT_ENV}=1 "
            f"(or git config {OPT_OUT_CONFIG} true) for an import-only commit"
        )
    return errors


def main(argv: list[str]) -> int:
    if len(argv) >= 1 and argv[0] == "install":
        try:
            install(os.getcwd())
        except HookFailure as exc:
            print(str(exc), file=sys.stderr)
            return 1
        return 0
    if len(argv) >= 1 and argv[0] == HOOK_NAME:
        errors = check_commit(os.getcwd())
        if errors:
            for error in errors:
                print(error, file=sys.stderr)
            return 1
        return 0
    print("usage: python3 tools/staged_import_hook.py install", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
