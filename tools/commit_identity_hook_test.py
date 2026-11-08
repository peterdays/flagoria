#!/usr/bin/env python3
"""Synthetic-repo tests for tools/commit_identity_hook.py.

Run: python3 tools/commit_identity_hook_test.py

Addresses and names are assembled at run time. Failure output redacts them.
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
import commit_identity_hook as hook  # noqa: E402

AT = "@"
LOCAL_NAME = "Case" + " " + "Local"
OTHER_NAME = "Case" + " " + "Other"
LOCAL_EMAIL = "case.local" + AT + "example.com"
OTHER_EMAIL = "case.other" + AT + "example.com"
GLOBAL_EMAIL = "agent.standin" + AT + "example.net"
SECRETS = (LOCAL_NAME, OTHER_NAME, LOCAL_EMAIL, OTHER_EMAIL, GLOBAL_EMAIL)

DISPATCHER = """#!/bin/sh
# Test stand-in for a hooks dispatcher: original hook, then named cursor hooks.
set -e
HOOKS_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
HOOK_NAME=$(basename "$0")
input=$(cat)
if [ -f "$HOOKS_DIR/.cursor-original-hooks-path" ]; then
  orig=$(cat "$HOOKS_DIR/.cursor-original-hooks-path")
  if [ -x "$orig/$HOOK_NAME" ]; then
    printf '%s' "$input" | "$orig/$HOOK_NAME" "$@"
  fi
fi
for cursor_hook in "$HOOKS_DIR"/$HOOK_NAME.cursor*; do
  if [ -x "$cursor_hook" ]; then
    printf '%s' "$input" | "$cursor_hook" "$@"
  fi
done
"""


def redact(text: str) -> str:
    for secret in SECRETS:
        text = text.replace(secret, "<redacted>")
    return text


def fail(message: str) -> None:
    raise SystemExit(redact(message))


def run(args: list[str], repo: Path, env: dict[str, str] | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
    merged = os.environ.copy()
    merged.pop("GIT_AUTHOR_NAME", None)
    merged.pop("GIT_AUTHOR_EMAIL", None)
    merged.pop("GIT_COMMITTER_NAME", None)
    merged.pop("GIT_COMMITTER_EMAIL", None)
    if env:
        merged.update(env)
    result = subprocess.run(args, cwd=repo, capture_output=True, text=True, env=merged)
    if check and result.returncode != 0:
        fail(f"{args} -> {result.returncode}\\n{result.stdout}\\n{result.stderr}")
    return result


def git(repo: Path, *args: str, env: dict[str, str] | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
    return run(["git", *args], repo, env=env, check=check)


def write_exec(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8")
    path.chmod(0o755)


def init_pair(root: Path, name: str) -> tuple[Path, Path]:
    bare = root / f"{name}.git"
    work = root / name
    git(root, "init", "--bare", "-b", "main", str(bare))
    git(root, "init", "-b", "main", str(work))
    git(work, "remote", "add", "origin", str(bare))
    git(work, "config", "commit.gpgsign", "false")
    git(work, "config", "user.name", LOCAL_NAME)
    git(work, "config", "user.email", LOCAL_EMAIL)
    tools = work / "tools"
    tools.mkdir()
    shutil.copy(Path(__file__).resolve().with_name("commit_identity_hook.py"), tools / "commit_identity_hook.py")
    return work, bare


def commit(repo: Path, message: str, *, name: str = LOCAL_NAME, email: str = LOCAL_EMAIL,
           committer_name: str | None = None, committer_email: str | None = None) -> str:
    stamp = repo / "note.txt"
    stamp.write_text(stamp.read_text(encoding="utf-8") + message + "\n" if stamp.exists() else message + "\n", encoding="utf-8")
    git(repo, "add", "note.txt")
    env = {
        "GIT_AUTHOR_NAME": name,
        "GIT_AUTHOR_EMAIL": email,
        "GIT_COMMITTER_NAME": committer_name or name,
        "GIT_COMMITTER_EMAIL": committer_email or email,
    }
    git(repo, "commit", "-m", message, env=env)
    return git(repo, "rev-parse", "HEAD").stdout.strip()


def ref_sha(bare: Path, ref: str) -> str | None:
    result = git(bare, "rev-parse", "--verify", "-q", ref, check=False)
    if result.returncode != 0:
        return None
    return result.stdout.strip()


def push(repo: Path, *refspecs: str) -> subprocess.CompletedProcess[str]:
    return git(repo, "push", "origin", *refspecs, check=False)


def assert_secrets_absent(result: subprocess.CompletedProcess[str]) -> None:
    blob = result.stdout + result.stderr
    for secret in SECRETS:
        if secret in blob:
            fail(f"output leaked identity while running {result.args}")


def assert_rejected(result: subprocess.CompletedProcess[str], before: str | None, bare: Path, ref: str) -> None:
    if result.returncode == 0:
        fail(f"push succeeded and should have been rejected: {result.args}")
    assert_secrets_absent(result)
    if ref_sha(bare, ref) != before:
        fail(f"remote {ref} changed on a rejected push")


def assert_accepted(result: subprocess.CompletedProcess[str], bare: Path, ref: str, sha: str) -> None:
    if result.returncode != 0:
        fail(f"push failed: {result.returncode} {result.stderr}")
    assert_secrets_absent(result)
    if ref_sha(bare, ref) != sha:
        fail(f"remote {ref} did not receive the commit")


def test_matching_commit_passes(root: Path) -> None:
    work, bare = init_pair(root, "pass")
    hook.install(str(work))
    sha = commit(work, "matching identity")
    result = push(work, "HEAD:refs/heads/main")
    assert_accepted(result, bare, "refs/heads/main", sha)


def test_wrong_author_and_committer(root: Path) -> None:
    work, bare = init_pair(root, "mismatch")
    hook.install(str(work))
    base = commit(work, "base")
    push(work, "HEAD:refs/heads/main")
    commit(work, "bad author", name=OTHER_NAME, email=OTHER_EMAIL)
    author = push(work, "HEAD:refs/heads/main")
    assert_rejected(author, base, bare, "refs/heads/main")
    if "author does not match" not in author.stderr:
        fail("wrong author was not named as an author mismatch")
    git(work, "reset", "--hard", base)
    commit(work, "bad committer", committer_name=OTHER_NAME, committer_email=OTHER_EMAIL)
    committer = push(work, "HEAD:refs/heads/main")
    assert_rejected(committer, base, bare, "refs/heads/main")
    if "committer does not match" not in committer.stderr:
        fail("wrong committer was not named as a committer mismatch")


def test_trailers_rejected(root: Path) -> None:
    work, bare = init_pair(root, "trailer")
    hook.install(str(work))
    base = commit(work, "base")
    first = push(work, "HEAD:refs/heads/main")
    assert_accepted(first, bare, "refs/heads/main", base)
    credit = "Co-authored-by: " + OTHER_NAME + " <" + OTHER_EMAIL + ">"
    for label in (credit, "Made-with: tool", "Generated-by: tool"):
        git(work, "reset", "--hard", base)
        commit(work, "credit\n\n" + label)
        result = push(work, "HEAD:refs/heads/main")
        assert_rejected(result, base, bare, "refs/heads/main")
        if "agent-credit trailer" not in result.stderr:
            fail("trailer push was rejected for another reason")
        if OTHER_EMAIL in result.stderr or OTHER_NAME in result.stderr:
            fail("trailer rejection included trailer contents")
    git(work, "reset", "--hard", base)
    prose = commit(work, "Notes on Co-authored-by lines")
    assert_accepted(push(work, "HEAD:refs/heads/main"), bare, "refs/heads/main", prose)


def test_missing_identity(root: Path) -> None:
    work, bare = init_pair(root, "missing")
    hook.install(str(work))
    base = commit(work, "base")
    push(work, "HEAD:refs/heads/main")
    commit(work, "later")
    git(work, "config", "--local", "--unset", "user.name")
    git(work, "config", "--local", "--unset", "user.email")
    global_config = root / "global.gitconfig"
    global_config.write_text(f"[user]\n\tname = {OTHER_NAME}\n\temail = {GLOBAL_EMAIL}\n", encoding="utf-8")
    env = os.environ.copy()
    env["GIT_CONFIG_GLOBAL"] = str(global_config)
    result = subprocess.run(
        ["git", "push", "origin", "HEAD:refs/heads/main"],
        cwd=work, capture_output=True, text=True, env=env,
    )
    assert_rejected(result, base, bare, "refs/heads/main")
    if "unset" not in result.stderr:
        fail("missing identity did not report that local identity is unset")


def test_security_hook_still_runs(root: Path) -> None:
    work, bare = init_pair(root, "security")
    parent = root / "security-home"
    parent.mkdir()
    hooks = parent / "active-hooks"
    hooks.mkdir()
    write_exec(hooks / ".dispatcher", DISPATCHER)
    (hooks / ".cursor-original-hooks-path").write_text(str(work / ".git" / "hooks"), encoding="utf-8")
    (hooks / "commit-msg").symlink_to(".dispatcher")
    marker = parent / "marker"
    fail_flag = parent / "fail"
    security = (
        "#!/bin/sh\n"
        f"printf 'ran\\n' >> '{marker}'\n"
        f"if [ -f '{fail_flag}' ]; then echo security-hook-rejected >&2; exit 1; fi\n"
        "exit 0\n"
    )
    write_exec(hooks / "pre-push.cursor.security", security)
    write_exec(hooks / "commit-msg.cursor.security", security)
    before_security = (hooks / "pre-push.cursor.security").read_bytes()
    before_commit = (hooks / "commit-msg").readlink()
    git(work, "config", "core.hooksPath", str(hooks))
    hooks_path_before = git(work, "config", "--get", "core.hooksPath").stdout.strip()
    hook.install(str(work))
    hooks_path_after = git(work, "config", "--get", "core.hooksPath").stdout.strip()
    if hooks_path_before != hooks_path_after:
        fail("install changed core.hooksPath")
    if (hooks / "commit-msg").readlink() != before_commit:
        fail("install replaced commit-msg")
    if (hooks / "pre-push.cursor.security").read_bytes() != before_security:
        fail("install modified the security hook")
    if os.readlink(hooks / "pre-push") != ".dispatcher":
        fail("pre-push was not linked to the dispatcher")
    if hook.MARKER not in (work / ".git" / "hooks" / "pre-push").read_text(encoding="utf-8"):
        fail("shim was not installed in the checkout hooks")
    hook.install(str(work))
    if os.readlink(hooks / "pre-push") != ".dispatcher":
        fail("second install replaced the dispatcher link")

    fail_flag.write_text("1", encoding="utf-8")
    commit_try = git(work, "commit", "--allow-empty", "-m", "blocked", check=False)
    if commit_try.returncode == 0:
        fail("commit-msg security hook did not fail the commit")
    if "security-hook-rejected" not in commit_try.stderr:
        fail("commit-msg security failure was not propagated")
    if not marker.exists() or "ran" not in marker.read_text(encoding="utf-8"):
        fail("commit-msg security hook did not run")
    fail_flag.unlink()
    marker.write_text("", encoding="utf-8")

    sha = commit(work, "good")
    fail_flag.write_text("1", encoding="utf-8")
    rejected = push(work, "HEAD:refs/heads/main")
    assert_rejected(rejected, None, bare, "refs/heads/main")
    if "security-hook-rejected" not in rejected.stderr:
        fail("pre-push security failure was not propagated")
    if marker.read_text(encoding="utf-8").count("ran") < 1:
        fail("pre-push security hook did not run")
    fail_flag.unlink()
    marker.write_text("", encoding="utf-8")
    accepted = push(work, "HEAD:refs/heads/main")
    assert_accepted(accepted, bare, "refs/heads/main", sha)
    if "ran" not in marker.read_text(encoding="utf-8"):
        fail("security hook did not run on a passing push")


def test_in_repo_chain_preserves_security(root: Path) -> None:
    work, bare = init_pair(root, "chain")
    local_hooks = work / "local-hooks"
    local_hooks.mkdir()
    marker = root / "chain-marker"
    fail_flag = root / "chain-fail"
    write_exec(local_hooks / "pre-push", (
        "#!/bin/sh\n"
        f"printf 'ran\\n' >> '{marker}'\n"
        f"if [ -f '{fail_flag}' ]; then echo security-hook-rejected >&2; exit 1; fi\n"
        "exit 0\n"
    ))
    git(work, "config", "core.hooksPath", str(local_hooks))
    before = git(work, "config", "--get", "core.hooksPath").stdout.strip()
    hook.install(str(work))
    if git(work, "config", "--get", "core.hooksPath").stdout.strip() != before:
        fail("chain install changed core.hooksPath")
    if hook.CHAIN_MARKER not in (local_hooks / "pre-push").read_text(encoding="utf-8"):
        fail("in-repo pre-push was not chained")
    if "printf 'ran" not in (local_hooks / "pre-push.flagoria-previous").read_text(encoding="utf-8"):
        fail("previous pre-push was not preserved")
    sha = commit(work, "chained good")
    fail_flag.write_text("1", encoding="utf-8")
    rejected = push(work, "HEAD:refs/heads/main")
    assert_rejected(rejected, None, bare, "refs/heads/main")
    if "ran" not in marker.read_text(encoding="utf-8"):
        fail("chained security hook did not run")
    fail_flag.unlink()
    accepted = push(work, "HEAD:refs/heads/main")
    assert_accepted(accepted, bare, "refs/heads/main", sha)


def test_chain_forwards_every_ref_to_read_loop(root: Path) -> None:
    ## A standard `while read` loop, with no extra end-of-file clause, must see
    ## every ref. Rejecting the only ref, or the last of several, leaves the remote unchanged.
    work, bare = init_pair(root, "readlines")
    local_hooks = work / "line-hooks"
    local_hooks.mkdir()
    seen = root / "refs-seen"
    original = (
        "#!/bin/sh\n"
        f"seen='{seen}'\n"
        ": > \"$seen\"\n"
        "while IFS= read -r line; do\n"
        "  printf '%s\\n' \"$line\" >> \"$seen\"\n"
        "  set -- $line\n"
        "  if [ \"$3\" = refs/heads/reject ]; then exit 1; fi\n"
        "done\n"
        "exit 0\n"
    )
    write_exec(local_hooks / "pre-push", original)
    original_bytes = (local_hooks / "pre-push").read_bytes()
    git(work, "config", "core.hooksPath", str(local_hooks))
    hook.install(str(work))
    if (local_hooks / "pre-push.flagoria-previous").read_bytes() != original_bytes:
        fail("chained security hook bytes changed")
    if "input=$(cat)" in (local_hooks / "pre-push").read_text(encoding="utf-8"):
        fail("chain still captures stdin with command substitution")
    base = commit(work, "base")
    accepted = push(work, "HEAD:refs/heads/main")
    assert_accepted(accepted, bare, "refs/heads/main", base)
    first = [line.split() for line in seen.read_text(encoding="utf-8").splitlines() if line.strip()]
    if len(first) != 1 or len(first[0]) != 4 or first[0][2] != "refs/heads/main":
        fail(f"single-ref push was not read in full: {first}")
    git(work, "checkout", "-b", "reject")
    commit(work, "reject me")
    one = push(work, "HEAD:refs/heads/reject")
    assert_rejected(one, None, bare, "refs/heads/reject")
    if ref_sha(bare, "refs/heads/main") != base:
        fail("rejected single-ref push moved main")
    if not any(len(line.split()) == 4 and line.split()[2] == "refs/heads/reject"
            for line in seen.read_text(encoding="utf-8").splitlines()):
        fail("single-ref rejection never saw the ref line")
    git(work, "checkout", "main")
    git(work, "checkout", "-b", "ok")
    commit(work, "ok side")
    many = push(work, "ok:refs/heads/ok", "reject:refs/heads/reject")
    assert_rejected(many, None, bare, "refs/heads/ok")
    if ref_sha(bare, "refs/heads/reject") is not None:
        fail("rejected multi-ref push updated the last ref")
    if ref_sha(bare, "refs/heads/main") != base:
        fail("rejected multi-ref push moved main")
    got = [line.split()[2] for line in seen.read_text(encoding="utf-8").splitlines() if len(line.split()) == 4]
    if got != ["refs/heads/ok", "refs/heads/reject"]:
        fail(f"read loop did not see both refs, last included: {got}")


def test_external_unrelated_hooks_left_alone(root: Path) -> None:
    work, _bare = init_pair(root, "external")
    hooks = root / "external-hooks"
    hooks.mkdir()
    write_exec(hooks / "pre-push", "#!/bin/sh\necho foreign >&2\nexit 0\n")
    before = (hooks / "pre-push").read_bytes()
    git(work, "config", "core.hooksPath", str(hooks))
    try:
        hook.install(str(work))
    except hook.HookFailure as exc:
        text = str(exc)
    else:
        fail("external unrelated hooks path was modified or install succeeded")
    if "left unchanged" not in text:
        fail("external refusal did not say the hooks were left unchanged")
    if (hooks / "pre-push").read_bytes() != before:
        fail("external pre-push bytes changed")
    for secret in SECRETS:
        if secret in text:
            fail("install error leaked identity")


def test_new_branch_multiref_noop_delete(root: Path) -> None:
    work, bare = init_pair(root, "history")
    bad = commit(work, "accepted history\n\nCo-authored-by: " + OTHER_NAME + " <" + OTHER_EMAIL + ">")
    first = push(work, "HEAD:refs/heads/main")
    assert_accepted(first, bare, "refs/heads/main", bad)
    git(work, "fetch", "origin")
    hook.install(str(work))
    git(work, "checkout", "-b", "feature")
    good = commit(work, "new work")
    created = push(work, "HEAD:refs/heads/feature")
    assert_accepted(created, bare, "refs/heads/feature", good)
    if ref_sha(bare, "refs/heads/main") != bad:
        fail("accepted history on main changed")

    git(work, "checkout", "main")
    git(work, "checkout", "-b", "good-branch")
    good_tip = commit(work, "good side")
    git(work, "checkout", "main")
    git(work, "checkout", "-b", "bad-branch")
    commit(work, "bad side\n\nCo-authored-by: " + OTHER_NAME + " <" + OTHER_EMAIL + ">")
    multi = push(work, "good-branch:refs/heads/good-branch", "bad-branch:refs/heads/bad-branch")
    assert_rejected(multi, None, bare, "refs/heads/good-branch")
    if ref_sha(bare, "refs/heads/bad-branch") is not None:
        fail("rejected multi-ref push updated the bad branch")
    if ref_sha(bare, "refs/heads/feature") != good:
        fail("rejected multi-ref push changed an existing branch")

    again = push(work, "main:refs/heads/main")
    if again.returncode != 0:
        fail(f"up-to-date push failed: {again.stderr}")
    assert_secrets_absent(again)
    if ref_sha(bare, "refs/heads/main") != bad:
        fail("no-op push changed main")

    empty = hook.check_push(str(work), "")
    if empty:
        fail("empty pre-push input was rejected")
    same = hook.check_push(str(work), f"refs/heads/main {bad} refs/heads/main {bad}\n")
    if same:
        fail("identical local and remote sha was rejected")

    deleted = push(work, ":refs/heads/feature")
    if deleted.returncode != 0:
        fail(f"delete was rejected: {deleted.stderr}")
    assert_secrets_absent(deleted)
    if ref_sha(bare, "refs/heads/feature") is not None:
        fail("delete did not remove the remote branch")
    _ = good_tip


def test_signature_block_is_not_the_message(root: Path) -> None:
    del root
    raw = "\n".join([
        "tree abc",
        f"author {LOCAL_NAME} <{LOCAL_EMAIL}> 1700000000 +0000",
        f"committer {LOCAL_NAME} <{LOCAL_EMAIL}> 1700000000 +0000",
        "gpgsig -----BEGIN SSH SIGNATURE-----",
        " signature-line",
        "",
        "subject",
        "",
        "Co-authored-by: " + OTHER_NAME + " <" + OTHER_EMAIL + ">",
    ])
    headers, body = hook.header_and_body(raw)
    if not any(line.startswith("author ") for line in headers):
        fail("author header was lost beside a signature")
    if "Co-authored-by:" not in body:
        fail("message trailer was swallowed by the signature block")
    if "signature-line" in body:
        fail("signature text was treated as the message")


def main() -> int:
    root = Path(tempfile.mkdtemp(prefix="commit-identity-"))
    try:
        tests = [
            test_matching_commit_passes,
            test_wrong_author_and_committer,
            test_trailers_rejected,
            test_missing_identity,
            test_security_hook_still_runs,
            test_in_repo_chain_preserves_security,
            test_chain_forwards_every_ref_to_read_loop,
            test_external_unrelated_hooks_left_alone,
            test_new_branch_multiref_noop_delete,
            test_signature_block_is_not_the_message,
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
