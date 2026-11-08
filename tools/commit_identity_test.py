#!/usr/bin/env python3
"""Security and regression tests for tools/commit_identity.py.

Synthetic addresses are built at runtime so this file contains none.
"""
from __future__ import annotations

import hashlib
import os
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import commit_identity as ci  # noqa: E402
import pr_hygiene as hygiene  # noqa: E402

AT = "@"
PERSONAL = "person.one" + AT + "example.com"
PERSONAL_CASE = "Person.One" + AT + "Example.com"
OTHER = "person.two" + AT + "example.com"
NOREPLY = "co.author" + AT + "users.noreply.example"
ROOT = Path(__file__).resolve().parents[1]


def isolated(**extra) -> dict:
    env = os.environ.copy()
    for key in list(env):
        if "EMAIL" in key or key.startswith("GIT_") or key == ci.ENV_NAME:
            env.pop(key, None)
    env.update(extra)
    return env


def run(repo: Path, args: list[str], env: dict | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-C", str(repo), "-c", "commit.gpgsign=false", *args],
        check=True, capture_output=True, text=True, env=env or isolated(),
    )


def init_repo() -> Path:
    path = Path(tempfile.mkdtemp(prefix="commit-identity-"))
    run(path, ["init", "-q", "-b", "main"])
    return path


def commit(repo: Path, filename: str, text: str, message: str,
           author: str, committer: str | None = None,
           author_name: str = "Synthetic Author",
           committer_name: str = "Synthetic Committer") -> str:
    committer = committer or author
    target = repo / filename
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text)
    run(repo, ["add", "--", filename])
    message_file = repo / ".commit-message"
    message_file.write_text(message)
    env = isolated(
        GIT_AUTHOR_NAME=author_name,
        GIT_COMMITTER_NAME=committer_name,
        GIT_AUTHOR_EMAIL=author,
        GIT_COMMITTER_EMAIL=committer,
    )
    run(repo, ["commit", "-q", "-F", str(message_file)], env)
    message_file.unlink()
    return run(repo, ["rev-parse", "HEAD"]).stdout.strip()


def codes(findings: list[ci.Finding]) -> list[str]:
    return sorted(item.code for item in findings)


def rendered(findings: list[ci.Finding]) -> str:
    return "\n".join(f"{item.code} {item.where} {item.message}" for item in findings)


def assert_silent(text: str) -> None:
    if "@" in text or "/home/" in text or "/Users/" in text:
        raise AssertionError("output contained an address or a home path")


def check(repo: Path, base: str, head: str, email: str | None) -> list[ci.Finding]:
    return ci.check_repository(repo, base, head, email)


def test_match_and_future_only() -> None:
    repo = init_repo()
    base = commit(
        repo, "a.txt", "a\n",
        "base\n\nCo-authored-by: Old <" + NOREPLY + ">\n",
        OTHER,
    )
    head = commit(repo, "b.txt", "b\n", "feature\n\nNo credit trailer.\n", PERSONAL_CASE)
    findings = check(repo, base, head, PERSONAL)
    assert findings == [], codes(findings)
    empty = ci.load_commits(repo, base, base)[1]
    assert codes(empty) == ["no-new-commits"]


def test_rejects_wrong_fields_and_trailer_without_echo() -> None:
    repo = init_repo()
    base = commit(repo, "a.txt", "a\n", "base\n", PERSONAL)
    author_bad = commit(repo, "b.txt", "b\n", "author\n", OTHER, PERSONAL)
    committer_bad = commit(repo, "c.txt", "c\n", "committer\n", PERSONAL, OTHER)
    both = commit(repo, "d.txt", "d\n", "both\n", OTHER)
    trailer = commit(
        repo, "e.txt", "e\n",
        "kept identity\n\nCo-authored-by: Helper <" + NOREPLY + ">\n",
        PERSONAL,
    )
    prose = commit(
        repo, "f.txt", "f\n",
        "We rejected Co-authored-by trailers in prose.\n",
        PERSONAL,
    )
    assert codes(check(repo, base, author_bad, PERSONAL)) == ["author-email-mismatch"]
    assert codes(check(repo, author_bad, committer_bad, PERSONAL)) == ["committer-email-mismatch"]
    assert codes(check(repo, committer_bad, both, PERSONAL)) == [
        "author-email-mismatch", "committer-email-mismatch",
    ]
    trailer_findings = check(repo, both, trailer, PERSONAL)
    assert codes(trailer_findings) == ["credit-trailer"]
    assert "noreply" not in rendered(trailer_findings)
    assert codes(check(repo, trailer, prose, PERSONAL)) == []
    signed = commit(repo, "g.txt", "g\n", "note\n\nSigned-off-by: Synthetic\n", PERSONAL)
    assert "credit-trailer" in codes(check(repo, prose, signed, PERSONAL))


def test_names_are_not_compared() -> None:
    repo = init_repo()
    base = commit(repo, "a.txt", "a\n", "base\n", PERSONAL)
    head = commit(
        repo, "b.txt", "b\n", "names\n", PERSONAL,
        author_name="One Name", committer_name="Other Name",
    )
    assert check(repo, base, head, PERSONAL) == []


def test_unrelated_history_is_not_walked() -> None:
    repo = init_repo()
    base = commit(
        repo, "a.txt", "a\n",
        "old\n\nCo-authored-by: Old <" + NOREPLY + ">\n",
        OTHER,
    )
    run(repo, ["checkout", "--orphan", "side"])
    run(repo, ["rm", "-rf", "."])
    head = commit(repo, "z.txt", "z\n", "orphan\n", PERSONAL)
    findings = check(repo, base, head, PERSONAL)
    assert codes(findings) == ["base-not-ancestor"]
    assert base not in rendered(findings)
    assert "credit-trailer" not in codes(findings)


def test_exact_head_and_stale() -> None:
    repo = init_repo()
    base = commit(repo, "a.txt", "a\n", "base\n", PERSONAL)
    head = commit(
        repo, "b.txt", "b\n",
        "bad\n\nCo-authored-by: Helper <" + NOREPLY + ">\n",
        OTHER,
    )
    refused = ci.load_commits(repo, base, "main")[1]
    assert codes(refused) == ["head-not-sha"]
    assert "credit-trailer" not in codes(refused)
    assert ci.stale_findings(head, head) == []
    assert codes(ci.stale_findings(base, head)) == ["stale-head"]
    assert codes(ci.stale_findings("main", head)) == ["stale-head"]
    assert ci.require_sha(head, "head-not-sha") is None
    assert ci.require_sha(head[:12], "head-not-sha") is not None


def test_config_fails_closed() -> None:
    missing, findings = ci.load_email.__wrapped__() if False else (None, None)
    del missing, findings
    env = isolated()
    assert "FLAGORIA_COMMIT_IDENTITY_EMAIL" not in env
    old = os.environ.pop(ci.ENV_EMAIL, None)
    try:
        email, found = ci.load_email()
        assert email is None and codes(found) == ["identity-config-missing"]
        os.environ[ci.ENV_EMAIL] = "not an address"
        email, found = ci.load_email()
        assert email is None and codes(found) == ["identity-config-invalid"]
        os.environ[ci.ENV_EMAIL] = PERSONAL + "\n"
        assert codes(ci.load_email()[1]) == ["identity-config-invalid"]
        os.environ[ci.ENV_EMAIL] = "*@example.com"
        assert codes(ci.load_email()[1]) == ["identity-config-invalid"]
        os.environ[ci.ENV_EMAIL] = PERSONAL
        assert ci.load_email()[0].casefold() == PERSONAL
    finally:
        if old is None:
            os.environ.pop(ci.ENV_EMAIL, None)
        else:
            os.environ[ci.ENV_EMAIL] = old


def test_squash_is_separate() -> None:
    trailer = ci.Commit("a" * 40, PERSONAL, PERSONAL, "subject\n\nCo-authored-by: Helper <" + NOREPLY + ">\n")
    clean = ci.Commit("b" * 40, PERSONAL, PERSONAL, "subject\n\nbody\n")
    assert codes(ci.squash_findings([trailer], "title", "body", "COMMIT_OR_PR_TITLE", "COMMIT_MESSAGES")) == [
        "squash-credit-trailer",
    ]
    assert ci.squash_findings([trailer], "title", "", "COMMIT_OR_PR_TITLE", "BLANK") == []
    body_hit = ci.squash_findings(
        [clean], "title", "Co-authored-by: Helper <" + NOREPLY + ">\n", "PR_TITLE", "PR_BODY",
    )
    assert codes(body_hit) == ["squash-credit-trailer"]
    assert ci.squash_findings([trailer], "title", "clean body\n", "PR_TITLE", "PR_BODY") == []
    joined = ci.squash_findings(
        [clean, trailer], "title", "", "COMMIT_OR_PR_TITLE", "COMMIT_MESSAGES",
    )
    assert codes(joined) == ["squash-credit-trailer"]
    unknown = ci.squash_findings([clean], "title", "", "NOPE", "BLANK")
    assert codes(unknown) == ["squash-mode-unknown"]


def test_merge_via() -> None:
    assert codes(ci.merge_via_findings("github-web", "squash")) == ["web-merge-committer-uncontrolled"]
    assert codes(ci.merge_via_findings("github-web", "merge")) == ["web-merge-committer-uncontrolled"]
    assert codes(ci.merge_via_findings("github-web", "rebase")) == ["web-merge-committer-uncontrolled"]
    assert ci.merge_via_findings("local", "commit") == []
    assert ci.merge_via_findings("local", "squash") == []
    assert codes(ci.merge_via_findings("github-web", "octopus")) == ["merge-via-unknown"]
    assert codes(ci.merge_via_findings("fork", "squash")) == ["merge-via-unknown"]


def test_hooks_are_not_executed_and_are_reported() -> None:
    repo = init_repo()
    base = commit(repo, "a.txt", "a\n", "base\n", PERSONAL)
    head = commit(repo, "b.txt", "b\n", "feature\n", PERSONAL)
    hook_dir = Path(tempfile.mkdtemp(prefix="hooks-"))
    marker = hook_dir / "marker"
    for name in ("prepare-commit-msg.cursor.co-author", "commit-msg.cursor.co-author", "post-commit"):
        hook = hook_dir / name
        hook.write_text(
            "#!/bin/sh\ntouch " + str(marker) + "\n"
            "printf '%s\\n' 'Co-authored-by: Helper' >> \"$1\"\n"
            "git interpret-trailers --trailer 'Co-authored-by: Helper'\n"
        )
        hook.chmod(hook.stat().st_mode | stat.S_IXUSR)
    sample = hook_dir / "commit-msg.sample"
    sample.write_text("#!/bin/sh\ngit interpret-trailers --trailer 'Co-authored-by: Helper'\n")
    sample.chmod(sample.stat().st_mode | stat.S_IXUSR)
    plain = hook_dir / "pre-commit"
    plain.write_text("#!/bin/sh\necho ok\n")
    plain.chmod(plain.stat().st_mode | stat.S_IXUSR)
    run(repo, ["config", "core.hooksPath", str(hook_dir)])
    assert ci.read_config(repo, "core.hooksPath") == str(hook_dir)
    assert "core.hooksPath=/dev/null" in ci.git_command(repo, ["log"])
    findings = check(repo, base, head, PERSONAL)
    assert findings == []
    assert not marker.exists()
    live = ci.live_controls(repo)
    assert_silent(rendered(live))
    assert "prepare-commit-msg.cursor.co-author" in rendered(live)
    assert "commit-msg.cursor.co-author" in rendered(live)
    assert "commit-msg.sample" not in rendered(live)
    assert "controls-unreviewed-hook" in codes(live)
    assert "controls-injector" in codes(live)
    missing = init_repo()
    run(missing, ["config", "core.hooksPath", str(hook_dir / "missing")])
    assert codes(ci.live_controls(missing)) == ["controls-unreadable"]


def test_tree_controls_are_future_only() -> None:
    repo = init_repo()
    hook = repo / ".githooks" / "commit-msg"
    hook.parent.mkdir()
    hook.write_text("#!/bin/sh\ngit interpret-trailers --trailer 'Co-authored-by: Helper'\n")
    base = commit(repo, ".githooks/commit-msg", hook.read_text(), "base hook\n", PERSONAL)
    head = commit(repo, "a.txt", "a\n", "feature\n", PERSONAL)
    assert ci.tree_controls(repo, [ci.parse_commit_object(head, ci.git(repo, "cat-file", "-p", head).stdout)]) == []
    added = repo / ".githooks" / "prepare-commit-msg"
    added.write_text("#!/bin/sh\ngit interpret-trailers --trailer 'Co-authored-by: Helper'\n")
    new = commit(repo, ".githooks/prepare-commit-msg", added.read_text(), "add hook\n", PERSONAL)
    found = check(repo, head, new, PERSONAL)
    assert codes(found) == ["controls-injector"]
    assert ".githooks/prepare-commit-msg" in rendered(found)
    assert base not in rendered(found)
    runtime = repo / ".cursor" / "hooks.json"
    runtime.parent.mkdir(parents=True, exist_ok=True)
    runtime.write_text("{}\n")
    newer = commit(repo, ".cursor/hooks.json", "{}\n", "add runtime\n", PERSONAL)
    assert codes(check(repo, new, newer, PERSONAL)) == ["controls-unreviewed-hook"]


def test_configure_and_startup_do_not_leak() -> None:
    home_cfg = Path(os.environ["HOME"]) / ".gitconfig"
    before = hashlib.sha256(home_cfg.read_bytes()).hexdigest() if home_cfg.exists() else None
    destination = Path(tempfile.mkdtemp(prefix="gitconfig-")) / "config"
    env = isolated(**{ci.ENV_EMAIL: PERSONAL, "GIT_AUTHOR_EMAIL": OTHER})
    proc = subprocess.run(
        [sys.executable, str(ROOT / "tools" / "commit_identity.py"),
         "configure-git", "--git-config", str(destination)],
        check=False, capture_output=True, text=True, env=env,
    )
    assert proc.returncode == 1
    assert_silent(proc.stdout + proc.stderr)
    assert "identity-override-mismatch" in proc.stdout
    assert not destination.exists()
    env = isolated(**{ci.ENV_EMAIL: PERSONAL, ci.ENV_NAME: "Synthetic Name"})
    proc = subprocess.run(
        [sys.executable, str(ROOT / "tools" / "commit_identity.py"),
         "configure-git", "--git-config", str(destination)],
        check=False, capture_output=True, text=True, env=env,
    )
    assert proc.returncode == 0, proc.stderr
    assert_silent(proc.stdout + proc.stderr)
    stored = subprocess.check_output(
        ["git", "config", "--file", str(destination), "user.email"], text=True,
    ).strip()
    if stored != PERSONAL:
        raise AssertionError("stored address did not match the synthetic address")
    startup = subprocess.run(
        [str(ROOT / "tools" / "commit_identity_startup.sh")],
        check=False, capture_output=True, text=True, env=isolated(),
    )
    assert startup.returncode == 1
    assert_silent(startup.stdout + startup.stderr)
    repo = init_repo()
    env = isolated(**{
        ci.ENV_EMAIL: PERSONAL,
        "FLAGORIA_COMMIT_IDENTITY_GITCONFIG": str(destination),
        "FLAGORIA_COMMIT_IDENTITY_REPO": str(repo),
    })
    startup = subprocess.run(
        [str(ROOT / "tools" / "commit_identity_startup.sh")],
        check=False, capture_output=True, text=True, env=env,
    )
    assert startup.returncode == 0, startup.stderr
    assert_silent(startup.stdout + startup.stderr)
    after = hashlib.sha256(home_cfg.read_bytes()).hexdigest() if home_cfg.exists() else None
    assert before == after


def test_cli_check_and_proposal_are_inactive() -> None:
    repo = init_repo()
    base = commit(repo, "a.txt", "a\n", "base\n", PERSONAL)
    head = commit(repo, "b.txt", "b\n", "feature\n", PERSONAL)
    proc = subprocess.run(
        [sys.executable, str(ROOT / "tools" / "commit_identity.py"),
         "check", "--repo", str(repo), "--base", base, "--head", head],
        check=False, capture_output=True, text=True, env=isolated(**{ci.ENV_EMAIL: PERSONAL}),
    )
    assert proc.returncode == 0, proc.stdout
    assert_silent(proc.stdout)
    proc = subprocess.run(
        [sys.executable, str(ROOT / "tools" / "commit_identity.py"),
         "check", "--repo", str(repo), "--base", base, "--head", head],
        check=False, capture_output=True, text=True, env=isolated(),
    )
    assert proc.returncode == 1
    assert "identity-config-missing" in proc.stdout
    assert_silent(proc.stdout)
    live = list((ROOT / ".github" / "workflows").glob("*identity*"))
    assert live == []
    proposal = (ROOT / "tools" / "commit_identity_workflow.yml").read_text(encoding="utf-8")
    assert "\npull_request:\n" not in proposal
    for needle in (
        "pull_request_target:",
        "persist-credentials: false",
        "github.event.pull_request.base.sha",
        "github.event.pull_request.head.sha",
        'pull/${PR_NUMBER}/head',
        'GITHUB_TOKEN: ""',
        "FLAGORIA_COMMIT_IDENTITY_EMAIL",
        "commit-identity",
        "stale head",
        "merge-via --via github-web --method squash",
        "tools/commit_identity.py check",
        "tools/commit_identity.py squash",
    ):
        assert needle in proposal, needle
    assert "clone_url" not in proposal
    sources = [
        ROOT / "tools" / "commit_identity.py",
        ROOT / "tools" / "commit_identity_test.py",
        ROOT / "tools" / "commit_identity_startup.sh",
        ROOT / "tools" / "commit_identity_workflow.yml",
        ROOT / "docs" / "commit-identity.md",
        ROOT / "AGENTS.md",
    ]
    for path in sources:
        text = path.read_text(encoding="utf-8")
        emails = list(hygiene.EMAIL_RE.finditer(text))
        paths = [hit for pattern in hygiene.PATH_RES for hit in pattern.finditer(text)]
        assert emails == [], path
        assert paths == [], path


def main() -> int:
    tests = [
        test_match_and_future_only,
        test_rejects_wrong_fields_and_trailer_without_echo,
        test_names_are_not_compared,
        test_unrelated_history_is_not_walked,
        test_exact_head_and_stale,
        test_config_fails_closed,
        test_squash_is_separate,
        test_merge_via,
        test_hooks_are_not_executed_and_are_reported,
        test_tree_controls_are_future_only,
        test_configure_and_startup_do_not_leak,
        test_cli_check_and_proposal_are_inactive,
    ]
    failed = 0
    for test in tests:
        try:
            test()
        except Exception as exc:  # noqa: BLE001 — report the case and keep going
            failed += 1
            detail = str(exc)
            if "@" in detail or "/home/" in detail or "/Users/" in detail:
                detail = "details withheld"
            print(f"FAIL {test.__name__}: {type(exc).__name__}: {detail}")
        else:
            print(f"ok   {test.__name__}")
    print(f"\n{len(tests) - failed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
