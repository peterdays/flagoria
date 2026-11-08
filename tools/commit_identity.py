#!/usr/bin/env python3
"""Future-only raw author and committer check, plus credit-trailer rejection.

The expected address is read from FLAGORIA_COMMIT_IDENTITY_EMAIL. It is never
written to output. Commits already in the trusted base are not rechecked.
Hook and runtime scans are positive signals only: a clean scan is not
acceptance, and no single hook name is treated as the only way a trailer
can appear. The commit object is the record.

This file does not install a workflow, set a secret, or change branch rules.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import stat
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

ADDRESS_RE = re.compile(r"^[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$")
SHA_RE = re.compile(r"^[0-9a-f]{40}$")
ENV_EMAIL = "FLAGORIA_COMMIT_IDENTITY_EMAIL"
ENV_NAME = "FLAGORIA_COMMIT_IDENTITY_NAME"
MAX_HOOK_BYTES = 1024 * 1024

# Credit trailers. Matched as a whole trailer key, not as prose.
TRAILER_KEYS = frozenset({
    "co-authored-by",
    "signed-off-by",
    "assisted-by",
    "generated-by",
    "made-with",
    "acked-by",
    "reviewed-by",
    "reported-by",
    "suggested-by",
    "tested-by",
    "helped-by",
})
APPEND_MARKERS = ("interpret-trailers", "--trailer", ">>")
TITLE_MODES = frozenset({"PR_TITLE", "COMMIT_OR_PR_TITLE"})
MESSAGE_MODES = frozenset({"PR_BODY", "COMMIT_MESSAGES", "BLANK"})
WEB_METHODS = frozenset({"merge", "squash", "rebase"})


@dataclass(frozen=True)
class Finding:
    code: str
    where: str
    message: str


@dataclass(frozen=True)
class Commit:
    sha: str
    author_email: str
    committer_email: str
    message: str


def parse_address(value: str) -> str:
    """Return one raw address. Reject display names, whitespace, and patterns."""
    if value != value.strip() or any(ch.isspace() for ch in value):
        raise ValueError("invalid")
    if not ADDRESS_RE.fullmatch(value):
        raise ValueError("invalid")
    return value


def load_email() -> tuple[str | None, list[Finding]]:
    raw = os.environ.get(ENV_EMAIL)
    if raw is None or raw.strip() == "":
        return None, [Finding(
            "identity-config-missing", "config",
            "private commit identity is not configured",
        )]
    try:
        return parse_address(raw), []
    except ValueError:
        return None, [Finding(
            "identity-config-invalid", "config",
            "private commit identity is not a single address",
        )]


def emails_match(left: str, right: str) -> bool:
    try:
        return parse_address(left).casefold() == parse_address(right).casefold()
    except ValueError:
        return False


def trailer_keys(message: str) -> list[str]:
    found: list[str] = []
    for line in (message or "").splitlines():
        if ":" not in line:
            continue
        key, _value = line.split(":", 1)
        key = key.strip().casefold()
        if key in TRAILER_KEYS:
            found.append(key)
    return found


def email_from_ident(ident: str) -> str:
    start = ident.rfind("<")
    end = ident.rfind(">")
    if start == -1 or end < start:
        return ""
    return ident[start + 1:end].strip()


def parse_commit_object(sha: str, raw: str) -> Commit:
    header, sep, body = raw.partition("\n\n")
    if not sep:
        body = ""
    author = committer = ""
    for line in header.splitlines():
        if line.startswith("author "):
            author = line[len("author "):]
        elif line.startswith("committer "):
            committer = line[len("committer "):]
    return Commit(sha, email_from_ident(author), email_from_ident(committer), body)


class CommandFailed(Exception):
    """A process failed. The message is fixed and never includes arguments."""


def public_failure(exc: BaseException) -> str:
    """Return a fixed phrase. Process arguments and addresses stay out of it."""
    del exc
    return "commit-identity: command failed"


def git_command(repo: Path, args: list[str]) -> list[str]:
    """Object reads disable hooks so a fetched repo cannot run hook code."""
    return ["git", "-C", str(repo), "-c", "core.hooksPath=/dev/null", *args]


def git(repo: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    try:
        proc = subprocess.run(
            git_command(repo, list(args)),
            check=False, capture_output=True, text=True,
        )
    except OSError:
        raise CommandFailed(public_failure(OSError())) from None
    if check and proc.returncode != 0:
        raise CommandFailed(public_failure(subprocess.CalledProcessError(proc.returncode, args))) from None
    return proc


def read_config(repo: Path, key: str) -> str | None:
    """Read repo config without a -c override hiding the stored value."""
    proc = subprocess.run(
        ["git", "-C", str(repo), "config", "--get", key],
        capture_output=True, text=True,
    )
    if proc.returncode != 0:
        return None
    value = proc.stdout.strip()
    return value or None


def require_sha(value: str, code: str) -> Finding | None:
    if not value or not SHA_RE.fullmatch(value):
        return Finding(code, "sha", "expected an exact commit id")
    return None


def object_exists(repo: Path, sha: str) -> bool:
    proc = git(repo, "rev-parse", "--verify", f"{sha}^{{commit}}", check=False)
    return proc.returncode == 0 and proc.stdout.strip() == sha


def load_commits(repo: Path, base: str, head: str) -> tuple[list[Commit], list[Finding]]:
    findings: list[Finding] = []
    for value, code in ((base, "base-not-sha"), (head, "head-not-sha")):
        bad = require_sha(value, code)
        if bad:
            findings.append(bad)
    if findings:
        return [], findings
    if not object_exists(repo, base):
        findings.append(Finding("base-not-resolved", base, "base commit is not in this repository"))
    if not object_exists(repo, head):
        findings.append(Finding("head-not-resolved", head, "head commit is not in this repository"))
    if findings:
        return [], findings
    ancestor = git(repo, "merge-base", "--is-ancestor", base, head, check=False)
    if ancestor.returncode != 0:
        return [], [Finding(
            "base-not-ancestor", head,
            "base is not an ancestor of head; refusing to scan unrelated history",
        )]
    listed = git(repo, "rev-list", "--reverse", f"{base}..{head}")
    shas = [line for line in listed.stdout.splitlines() if line]
    if not shas:
        return [], [Finding("no-new-commits", head, "no commits are new relative to the trusted base")]
    commits: list[Commit] = []
    for sha in shas:
        if not SHA_RE.fullmatch(sha):
            return [], [Finding("head-not-sha", sha, "rev-list returned a non-commit id")]
        raw = git(repo, "cat-file", "-p", sha).stdout
        commits.append(parse_commit_object(sha, raw))
    return commits, []


def check_commits(commits: list[Commit], email: str | None) -> list[Finding]:
    findings: list[Finding] = []
    for commit in commits:
        if email is not None:
            if not emails_match(commit.author_email, email):
                findings.append(Finding(
                    "author-email-mismatch", commit.sha,
                    "author email does not match the configured identity",
                ))
            if not emails_match(commit.committer_email, email):
                findings.append(Finding(
                    "committer-email-mismatch", commit.sha,
                    "committer email does not match the configured identity",
                ))
        for key in trailer_keys(commit.message):
            findings.append(Finding(
                "credit-trailer", commit.sha,
                f"commit message contains a {key} trailer",
            ))
    return findings


def render_squash_message(
    commits: list[Commit], title: str, body: str, title_mode: str, message_mode: str,
) -> str:
    subjects = []
    messages = []
    for commit in commits:
        lines = commit.message.splitlines()
        subjects.append(lines[0] if lines else "")
        messages.append(commit.message)
    if title_mode == "PR_TITLE":
        rendered_title = title or ""
    elif len(commits) == 1:
        rendered_title = subjects[0]
    else:
        rendered_title = title or ""
    if message_mode == "BLANK":
        rendered_body = ""
    elif message_mode == "PR_BODY":
        rendered_body = body or ""
    elif len(commits) == 1:
        rendered_body = commits[0].message
    else:
        rendered_body = "\n\n".join(messages)
    if rendered_body:
        return rendered_title + "\n\n" + rendered_body
    return rendered_title


def squash_findings(
    commits: list[Commit], title: str, body: str, title_mode: str, message_mode: str,
) -> list[Finding]:
    if title_mode not in TITLE_MODES or message_mode not in MESSAGE_MODES:
        return [Finding(
            "squash-mode-unknown", "squash",
            "squash message settings are missing or not a known mode",
        )]
    rendered = render_squash_message(commits, title, body, title_mode, message_mode)
    return [
        Finding("squash-credit-trailer", "squash", f"squash message contains a {key} trailer")
        for key in trailer_keys(rendered)
    ]


def merge_via_findings(via: str, method: str) -> list[Finding]:
    if via == "local" and method in WEB_METHODS | {"commit"}:
        return []
    if via == "github-web" and method in WEB_METHODS:
        return [Finding(
            "web-merge-committer-uncontrolled", method,
            "a GitHub web merge does not preserve the requested committer address",
        )]
    return [Finding(
        "merge-via-unknown", "merge",
        "merge path is not a known controlled commit",
    )]


def stale_findings(expected: str, current: str) -> list[Finding]:
    if require_sha(expected, "stale-head") or require_sha(current, "stale-head"):
        return [Finding("stale-head", "sha", "head sha is not an exact commit id")]
    if expected != current:
        return [Finding(
            "stale-head", expected,
            "pull request head moved before the result was recorded",
        )]
    return []


@dataclass(frozen=True)
class Snapshot:
    """Inputs that can change without a new commit object."""
    head: str
    base: str
    title: str
    body: str
    title_mode: str
    message_mode: str


@dataclass(frozen=True)
class StatusPlan:
    """What a run may record. Final success is withheld.

    A stored status stays in place until a later post replaces it. An in-run
    match does not survive a later settings change, because that change has
    no workflow event, and a GitHub Actions status is not pinned to one
    workflow file. Callers therefore clear with failure and do not post success.
    """
    clear: str
    final: str
    in_run_match: bool
    reason: str


def recorded_state(previous: str | None, posted: str | None) -> str | None:
    """The previous status remains when nothing new is posted."""
    if posted is None:
        return previous
    return posted


def status_plan(before: Snapshot, after: Snapshot, checks_ok: bool) -> StatusPlan:
    reason = "in-run-match-not-durable"
    matched = True
    for field, label in (
        ("head", "head"),
        ("base", "base"),
        ("title", "title"),
        ("body", "body"),
        ("title_mode", "title-mode"),
        ("message_mode", "message-mode"),
    ):
        if getattr(before, field) != getattr(after, field):
            matched = False
            reason = label
            break
    if matched and not checks_ok:
        matched = False
        reason = "checks"
    return StatusPlan("failure", "failure", matched, reason)


def blob_appends_trailer(text: str) -> bool:
    lowered = text.casefold()
    if not any(key in lowered for key in TRAILER_KEYS):
        return False
    return any(marker in lowered or marker in text for marker in APPEND_MARKERS)


def is_hookish(path: str) -> bool:
    base = path.rsplit("/", 1)[-1]
    if base.endswith(".sample"):
        return False
    if base == "hooks.json":
        return True
    prefixes = (
        ".githooks/", ".husky/", ".git/hooks/", ".cursor/hooks/",
    )
    if path.startswith(prefixes) or "/.githooks/" in f"/{path}":
        return True
    names = (
        "commit-msg", "prepare-commit-msg", "pre-commit", "post-commit",
        "post-rewrite", "pre-push",
    )
    return base in names or any(base.startswith(name + ".") for name in names)


def _read_limited(path: Path) -> str | None:
    try:
        info = path.stat()
    except OSError:
        return None
    if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_HOOK_BYTES:
        return None
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None


def scan_hook_dir(directory: Path, where: str) -> list[Finding]:
    if not directory.is_dir():
        return [Finding("controls-unreadable", where, "hook directory cannot be read")]
    findings: list[Finding] = []
    try:
        names = sorted(directory.iterdir())
    except OSError:
        return [Finding("controls-unreadable", where, "hook directory cannot be read")]
    for path in names:
        if not path.is_file():
            continue
        if path.name.endswith(".sample"):
            continue
        executable = bool(path.stat().st_mode & stat.S_IXUSR)
        if not executable:
            continue
        text = _read_limited(path)
        if text is None:
            findings.append(Finding(
                "controls-unreadable", path.name, "executable hook cannot be read",
            ))
            continue
        if blob_appends_trailer(text):
            findings.append(Finding(
                "controls-injector", path.name,
                "executable hook appends a credit trailer",
            ))
        else:
            findings.append(Finding(
                "controls-unreviewed-hook", path.name,
                "executable hook is not a reviewed trailer control",
            ))
    return findings


def live_controls(repo: Path) -> list[Finding]:
    """Inspect hook controls visible in this checkout. Do not print their paths."""
    findings: list[Finding] = []
    git_dir = repo / ".git" / "hooks"
    if git_dir.is_dir():
        findings.extend(scan_hook_dir(git_dir, "git-hooks"))
    hooks_path = read_config(repo, "core.hooksPath")
    if hooks_path:
        path = Path(hooks_path)
        if not path.is_absolute():
            path = (repo / path).resolve()
        findings.extend(scan_hook_dir(path, "hooks-path"))
    template = read_config(repo, "commit.template")
    if template:
        path = Path(template)
        if not path.is_absolute():
            path = (repo / path).resolve()
        text = _read_limited(path)
        if text is None:
            findings.append(Finding(
                "controls-unreadable", "commit-template",
                "commit template cannot be read",
            ))
        elif blob_appends_trailer(text) or trailer_keys(text):
            findings.append(Finding(
                "controls-injector", "commit-template",
                "commit template contains a credit trailer",
            ))
    return findings


def tree_controls(repo: Path, commits: list[Commit]) -> list[Finding]:
    findings: list[Finding] = []
    seen: set[tuple[str, str]] = set()
    for commit in commits:
        listed = git(
            repo, "diff-tree", "-r", "--no-commit-id", "--name-status", "-z", commit.sha,
        )
        parts = listed.stdout.split("\0")
        index = 0
        while index + 1 < len(parts):
            status, path = parts[index], parts[index + 1]
            index += 2
            if status.startswith("R") or status.startswith("C"):
                # rename/copy: next field is the new path
                if index >= len(parts):
                    break
                path = parts[index]
                index += 1
            if not path or not is_hookish(path):
                continue
            key = (commit.sha, path)
            if key in seen:
                continue
            seen.add(key)
            exists = git(repo, "cat-file", "-e", f"{commit.sha}:{path}", check=False)
            if exists.returncode != 0:
                continue
            text = git(repo, "cat-file", "-p", f"{commit.sha}:{path}", check=False)
            if text.returncode != 0:
                findings.append(Finding(
                    "controls-unreadable", path, "hook file in the new commit cannot be read",
                ))
                continue
            if path.endswith("hooks.json"):
                code = "controls-injector" if blob_appends_trailer(text.stdout) or trailer_keys(text.stdout) else "controls-unreviewed-hook"
                message = (
                    "new hook runtime appends a credit trailer"
                    if code == "controls-injector"
                    else "new hook runtime is not a reviewed trailer control"
                )
                findings.append(Finding(code, path, message))
                continue
            if blob_appends_trailer(text.stdout):
                findings.append(Finding(
                    "controls-injector", path, "new file appends a credit trailer",
                ))
    return findings


def check_repository(repo: Path, base: str, head: str, email: str | None) -> list[Finding]:
    commits, findings = load_commits(repo, base, head)
    findings.extend(check_commits(commits, email))
    if commits:
        findings.extend(tree_controls(repo, commits))
    return findings


def _config_text(email: str, name: str) -> str:
    """One user section. The address is a single validated line, not a process argument."""
    if any(ch in name for ch in "\n\r\x00"):
        raise ValueError("name")
    text = "[user]\n\temail = " + email + "\n"
    if name:
        text += "\tname = " + name + "\n"
    return text


def configure_git(config_path: Path) -> list[Finding]:
    email, findings = load_email()
    if email is None:
        return findings
    for key in ("GIT_AUTHOR_EMAIL", "GIT_COMMITTER_EMAIL"):
        override = os.environ.get(key)
        if override is not None and override.strip() and not emails_match(override, email):
            findings.append(Finding(
                "identity-override-mismatch", key,
                "an author or committer override does not match the configured address",
            ))
    if findings:
        return findings
    name = os.environ.get(ENV_NAME, "").strip()
    try:
        config_path.parent.mkdir(parents=True, exist_ok=True)
        config_path.write_text(_config_text(email, name), encoding="utf-8")
    except (OSError, ValueError):
        findings.append(Finding(
            "identity-config-unwritable", "config",
            "could not write the git config file",
        ))
    return findings


def event_title_body(path: str) -> tuple[str, str]:
    payload = json.loads(Path(path).read_text(encoding="utf-8"))
    pr = payload.get("pull_request") or {}
    return pr.get("title") or "", pr.get("body") or ""


def report(findings: list[Finding]) -> int:
    ordered = sorted(findings, key=lambda item: (item.code, item.where, item.message))
    for item in ordered:
        print(f"error: {item.code}: {item.where}: {item.message}")
    if ordered:
        print(f"commit-identity: FAIL {len(ordered)}")
        return 1
    print("commit-identity: PASS")
    return 0


def _add_range(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--repo", default=".")
    parser.add_argument("--base", required=True)
    parser.add_argument("--head", required=True)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="cmd", required=True)

    check_p = sub.add_parser("check")
    _add_range(check_p)

    squash_p = sub.add_parser("squash")
    _add_range(squash_p)
    squash_p.add_argument("--title", default="")
    squash_p.add_argument("--body-file")
    squash_p.add_argument("--event")
    squash_p.add_argument("--title-mode", required=True)
    squash_p.add_argument("--message-mode", required=True)

    controls_p = sub.add_parser("controls")
    controls_p.add_argument("--repo", default=".")

    config_p = sub.add_parser("configure-git")
    config_p.add_argument("--git-config", required=True)

    via_p = sub.add_parser("merge-via")
    via_p.add_argument("--via", required=True)
    via_p.add_argument("--method", required=True)

    stale_p = sub.add_parser("stale")
    stale_p.add_argument("--expected", required=True)
    stale_p.add_argument("--current", required=True)

    plan_p = sub.add_parser("plan")
    plan_p.add_argument("--before", required=True)
    plan_p.add_argument("--after", required=True)
    plan_p.add_argument("--checks-ok", required=True)

    args = parser.parse_args(argv)
    try:
        return _dispatch(args)
    except CommandFailed:
        print(public_failure(CommandFailed("commit-identity: command failed")))
        return 1


def _snapshot(path: str) -> Snapshot:
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    return Snapshot(
        head=str(data.get("head") or ""),
        base=str(data.get("base") or ""),
        title=str(data.get("title") or ""),
        body=str(data.get("body") or ""),
        title_mode=str(data.get("title_mode") or ""),
        message_mode=str(data.get("message_mode") or ""),
    )


def _checks_ok(value: str) -> bool:
    return value.strip().lower() in {"1", "true", "yes"}


def _dispatch(args: argparse.Namespace) -> int:
    if args.cmd == "check":
        email, findings = load_email()
        findings.extend(check_repository(Path(args.repo), args.base, args.head, email))
        return report(findings)
    if args.cmd == "squash":
        title, body = args.title, ""
        if args.body_file:
            body = Path(args.body_file).read_text(encoding="utf-8")
        if args.event:
            title, body = event_title_body(args.event)
        commits, findings = load_commits(Path(args.repo), args.base, args.head)
        if findings and not commits:
            return report(findings)
        findings.extend(squash_findings(commits, title, body, args.title_mode, args.message_mode))
        return report(findings)
    if args.cmd == "controls":
        return report(live_controls(Path(args.repo)))
    if args.cmd == "configure-git":
        return report(configure_git(Path(args.git_config)))
    if args.cmd == "merge-via":
        return report(merge_via_findings(args.via, args.method))
    if args.cmd == "stale":
        return report(stale_findings(args.expected, args.current))
    if args.cmd == "plan":
        plan = status_plan(_snapshot(args.before), _snapshot(args.after), _checks_ok(args.checks_ok))
        match = "yes" if plan.in_run_match else "no"
        print(f"clear={plan.clear} final={plan.final} in_run_match={match} reason={plan.reason}")
        # An in-run match is not a recorded success. Exit 0 only so a caller
        # can see the match; the final state is still failure.
        return 0 if plan.in_run_match else 1
    return 2


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.stderr.write("commit-identity: FAIL internal\n")
        sys.exit(1)
