#!/usr/bin/env python3
"""Local pre-push check for the repo-local author and committer.

The check is off until this checkout runs:

    python3 tools/commit_identity_hook.py install

That command wires the check through the hooks path already in use. It does
not change core.hooksPath and does not remove other hooks. A fresh checkout
does not run the check until install is run there.

New outgoing commits must use the raw author and committer from this
checkout's local git user.name and user.email. A Co-authored-by, Made-with,
or Generated-by trailer is allowed and left in place. Commits already
reachable from a remote-tracking ref are not rechecked. GitHub's own merge
committer is outside this check.
"""
from __future__ import annotations

import os
import stat
import subprocess
import sys
from pathlib import Path

MARKER = "flagoria-commit-identity-hook"
CHAIN_MARKER = "flagoria-commit-identity-chain"
SHIM = """#!/bin/sh
# flagoria-commit-identity-hook
set -e
root=$(git rev-parse --show-toplevel) || exit 1
exec python3 "$root/tools/commit_identity_hook.py" pre-push "$@"
"""

CHAIN = """#!/bin/sh
# flagoria-commit-identity-chain
# Keep the exact stdin bytes. A command substitution drops the trailing
# newline, and a while-read hook then never sees the last ref.
here=$(CDPATH= cd -- "$(dirname "$0")" && pwd) || exit 1
payload=$(mktemp) || exit 1
trap 'rm -f "$payload"' EXIT
cat > "$payload" || exit 1
if [ -x "$here/pre-push.flagoria-previous" ]; then
  "$here/pre-push.flagoria-previous" "$@" < "$payload"
  status=$?
  [ "$status" -eq 0 ] || exit "$status"
fi
"$here/pre-push.flagoria-identity" "$@" < "$payload"
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
        raise HookFailure("commit identity: git command failed")
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


def local_config(repo: str, key: str) -> str | None:
    result = git(repo, "config", "--local", "--get", key, check=False)
    if result.returncode != 0:
        return None
    value = result.stdout.rstrip("\n")
    return value or None


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
    pre = hooks_path / "pre-push"
    if pre.is_symlink() and os.readlink(pre) == ".dispatcher":
        return True
    if pre.is_file():
        text = read_text(pre)
        return ".cursor-original-hooks-path" in text
    return False


def write_exec(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)


def install_shim(dest: Path) -> None:
    """Place the check in dest, chaining any foreign pre-push ahead of it."""
    current = dest / "pre-push"
    if is_ours(current, MARKER) and not is_ours(current, CHAIN_MARKER):
        write_exec(current, SHIM)
        return
    if is_ours(current, CHAIN_MARKER):
        write_exec(current, CHAIN)
        write_exec(dest / "pre-push.flagoria-identity", SHIM)
        return
    if current.exists() or current.is_symlink():
        previous = dest / "pre-push.flagoria-previous"
        if previous.exists() or previous.is_symlink():
            raise HookFailure("commit identity: pre-push already has a saved previous hook")
        current.rename(previous)
        write_exec(dest / "pre-push.flagoria-identity", SHIM)
        write_exec(current, CHAIN)
        return
    write_exec(current, SHIM)


def link_dispatcher_entry(hooks_path: Path) -> None:
    """Let an existing dispatcher own pre-push. Do not replace a hook that is already there."""
    pre = hooks_path / "pre-push"
    if pre.exists() or pre.is_symlink():
        if not entry_calls_original(hooks_path):
            raise HookFailure(
                "commit identity: active pre-push does not run the checkout hooks; left unchanged"
            )
        return
    dispatcher = hooks_path / ".dispatcher"
    if not dispatcher.is_file():
        raise HookFailure(
            "commit identity: active hooks path has no pre-push entry; left unchanged"
        )
    pre.symlink_to(".dispatcher")


def install(repo: str) -> None:
    git_hooks = git_hooks_dir(repo)
    configured = effective_hooks_path(repo)
    if configured is None:
        install_shim(git_hooks)
        print("commit identity: installed for this checkout")
        return
    if delegates_to_git_hooks(configured, git_hooks):
        link_dispatcher_entry(configured)
        install_shim(git_hooks)
        print("commit identity: installed for this checkout")
        print("commit identity: pre-push runs through the active hooks path")
        return
    if within(configured, work_tree(repo)) or within(configured, git_hooks.parent):
        install_shim(configured)
        print("commit identity: installed for this checkout")
        return
    raise HookFailure(
        "commit identity: active hooks path is outside this checkout and does not chain; left unchanged"
    )


def zero_sha(sha: str) -> bool:
    return bool(sha) and set(sha) <= {"0"}


def parse_push_line(line: str) -> tuple[str, str, str, str] | None:
    if not line.strip():
        return None
    parts = line.split()
    if len(parts) != 4:
        raise HookFailure("commit identity: malformed pre-push input")
    return parts[0], parts[1], parts[2], parts[3]


def outgoing_shas(repo: str, local_sha: str, remote_sha: str) -> list[str]:
    if zero_sha(local_sha) or local_sha == remote_sha:
        return []
    command = ["rev-list", local_sha]
    excluded: list[str] = []
    if remote_sha and not zero_sha(remote_sha):
        excluded.append(remote_sha)
    remotes = git(repo, "for-each-ref", "--format=%(objectname)", "refs/remotes")
    excluded.extend(line.strip() for line in remotes.stdout.splitlines() if line.strip())
    if excluded:
        command.append("--not")
        command.extend(excluded)
    listed = git(repo, *command, check=False)
    if listed.returncode != 0:
        raise HookFailure("commit identity: cannot list outgoing commits")
    return [line.strip() for line in listed.stdout.splitlines() if line.strip()]


def header_and_body(raw: str) -> tuple[list[str], str]:
    lines = raw.splitlines()
    headers: list[str] = []
    for index, line in enumerate(lines):
        if line == "":
            return headers, "\n".join(lines[index + 1 :])
        if line.startswith(" ") or line.startswith("gpgsig "):
            continue
        headers.append(line)
    return headers, ""


def identity_from_header(line: str) -> tuple[str, str]:
    rest = line.split(" ", 1)[1]
    name, after = rest.rsplit(" <", 1)
    email = after.split(">", 1)[0]
    return name, email


def commit_errors(repo: str, sha: str, name: str, email: str) -> list[str]:
    shown = sha[:12]
    raw = git(repo, "cat-file", "-p", sha).stdout
    headers, _body = header_and_body(raw)
    author = committer = None
    for line in headers:
        if line.startswith("author "):
            author = identity_from_header(line)
        elif line.startswith("committer "):
            committer = identity_from_header(line)
    errors: list[str] = []
    if author != (name, email):
        errors.append(f"commit identity: {shown} author does not match repo-local identity")
    if committer != (name, email):
        errors.append(f"commit identity: {shown} committer does not match repo-local identity")
    # Platform attribution trailers (Co-authored-by, Made-with, Generated-by)
    # stay in the message. They are not an author or committer header.
    return errors


def check_push(repo: str, payload: str) -> list[str]:
    name = local_config(repo, "user.name")
    email = local_config(repo, "user.email")
    if name is None or email is None:
        return ["commit identity: repo-local user.name or user.email is unset"]
    errors: list[str] = []
    seen: set[str] = set()
    for line in payload.splitlines():
        parsed = parse_push_line(line)
        if parsed is None:
            continue
        _local_ref, local_sha, _remote_ref, remote_sha = parsed
        for sha in outgoing_shas(repo, local_sha, remote_sha):
            if sha in seen:
                continue
            seen.add(sha)
            errors.extend(commit_errors(repo, sha, name, email))
    return errors


def main(argv: list[str]) -> int:
    if len(argv) >= 1 and argv[0] == "install":
        try:
            install(os.getcwd())
        except HookFailure as exc:
            print(str(exc), file=sys.stderr)
            return 1
        return 0
    if len(argv) >= 1 and argv[0] == "pre-push":
        try:
            errors = check_push(os.getcwd(), sys.stdin.read())
        except HookFailure as exc:
            print(str(exc), file=sys.stderr)
            return 1
        if errors:
            for error in errors:
                print(error, file=sys.stderr)
            return 1
        return 0
    print("usage: python3 tools/commit_identity_hook.py install", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
