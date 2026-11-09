#!/usr/bin/env python3
"""Deterministic issue triage labels from the task form. No model, no external service.

RICE = reach * impact * confidence / effort
Reach is 1..10, impact is 0.25, 0.5, 1, 2 or 3, confidence is 50, 80 or 100,
and effort is 0.25, 0.5, 1, 2 or 4 person-weeks.

  rice: under-100    score < 100
  rice: 100-399      100 <= score < 400
  rice: 400-999      400 <= score < 1000
  rice: 1000-plus    score >= 1000

Escalate when a high-blast risk area (saves/world data, netcode/multiplayer
sync, release/signing/CI, security/privacy) is selected and severity is med
or high, when severity is high (decided first, including core input or none),
or when a field is missing or not a form value. Otherwise triage: auto-merge.
Low severity does not escalate on its own. core input and none are not
high-blast.

Labels are a routing hint, not an approval record. Approvals are tracked
outside this repository. workflow_dispatch backfill adds triage: needs-fields
when the fields do not parse. A value that fails to parse is not copied into
the workflow comment.

  python3 tools/issue_triage.py --body-file BODY.md
  python3 tools/issue_triage.py --event "$GITHUB_EVENT_PATH"
  python3 tools/issue_triage.py --self-test
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.parse
from dataclasses import dataclass
from decimal import Decimal
from pathlib import Path

# Login whose issues this scorer labels. Every other author is ignored.
SCORED_AUTHOR = "peterdays"
COMMENT_LOGIN = "github-actions[bot]"
MARKER = "<!-- flagoria-issue-triage -->"

PATH_AUTO = "triage: auto-merge"
PATH_ESCALATE = "triage: escalate"
NEEDS_FIELDS = "triage: needs-fields"
PATH_LABELS = frozenset({PATH_AUTO, PATH_ESCALATE})

RICE_UNDER_100 = "rice: under-100"
RICE_100_399 = "rice: 100-399"
RICE_400_999 = "rice: 400-999"
RICE_1000_PLUS = "rice: 1000-plus"
RICE_LABELS = frozenset({RICE_UNDER_100, RICE_100_399, RICE_400_999, RICE_1000_PLUS})

HIGH_BLAST = frozenset({
    "saves/world data",
    "netcode/multiplayer sync",
    "release/signing/CI",
    "security/privacy",
})
RISK_ORDER = (
    "saves/world data",
    "netcode/multiplayer sync",
    "release/signing/CI",
    "security/privacy",
    "core input",
    "none",
)
RISK_LOOKUP = {name.lower(): name for name in RISK_ORDER}
MANAGED_LABELS = PATH_LABELS | RICE_LABELS | frozenset({NEEDS_FIELDS})

REACH = frozenset(str(n) for n in range(1, 11))
IMPACT = frozenset({"0.25", "0.5", "1", "2", "3"})
CONFIDENCE = frozenset({"50", "80", "100"})
EFFORT = frozenset({"0.25", "0.5", "1", "2", "4"})
SEVERITY = frozenset({"low", "med", "high"})

# name, color (no hash), description (GitHub's limit is 100 characters).
LABEL_SPECS = (
    (PATH_AUTO, "1D76DB", "Routing hint: auto-merge on green required checks. Not an approval."),
    (PATH_ESCALATE, "D93F0B", "Routing hint: owner decision before merge. Not an approval."),
    (NEEDS_FIELDS, "FBCA04", "Backfill: triage fields are missing or unparseable."),
    (RICE_UNDER_100, "D4E5F7", "RICE score under 100. Routing hint only, not an approval."),
    (RICE_100_399, "A9CBF0", "RICE score from 100 up to but not including 400."),
    (RICE_400_999, "6FA0E0", "RICE score from 400 up to but not including 1000."),
    (RICE_1000_PLUS, "2F6FBB", "RICE score 1000 or more. Routing hint only, not an approval."),
)

HEADINGS = {
    "reach": "reach",
    "impact": "impact",
    "confidence": "confidence",
    "effort": "effort",
    "risk area": "risk",
    "severity": "severity",
}
FIELD_LABEL = {
    "reach": "reach",
    "impact": "impact",
    "confidence": "confidence",
    "effort": "effort",
    "risk": "risk area",
    "severity": "severity",
}
HEADING_RE = re.compile(r"^#{1,6}[ \t]+(.+?)[ \t]*$")
COLON_RE = re.compile(r"^(reach|impact|confidence|effort|risk area|severity)[ \t]*:[ \t]*(.*)$", re.I)
CHECKBOX_RE = re.compile(r"^[ \t]*-[ \t]+\[([ xX])\][ \t]*(.*)$")
FENCE_RE = re.compile(r"^[ \t]*```")
HTML_COMMENT_RE = re.compile(r"<!--.*?-->", re.S)
REPO_RE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")


@dataclass(frozen=True)
class Decision:
    parsed: bool
    path: str
    bucket: str | None
    score_text: str | None
    reach: str | None
    impact: str | None
    confidence: str | None
    effort: str | None
    severity: str | None
    risk: tuple[str, ...]
    reason: str


def _unwrap(text: str) -> str:
    text = text.strip()
    if len(text) >= 2 and text[0] == text[-1] == "`":
        text = text[1:-1].strip()
    if len(text) >= 4 and text.startswith("**") and text.endswith("**"):
        text = text[2:-2].strip()
    return text


def _visible_body(text: str) -> str:
    """Drop HTML comments and fenced blocks so quoted examples are not fields."""
    stripped = HTML_COMMENT_RE.sub("", text or "")
    kept: list[str] = []
    fenced = False
    for line in stripped.splitlines():
        if FENCE_RE.match(line):
            fenced = not fenced
            continue
        if not fenced:
            kept.append(line)
    return "\n".join(kept)


def _sections(text: str) -> dict[str, str]:
    """First ATX heading of each field name, through the next heading."""
    found: dict[str, list[str]] = {}
    current: str | None = None
    for line in text.splitlines():
        heading = HEADING_RE.match(line)
        if heading:
            key = HEADINGS.get(heading.group(1).strip().lower())
            if key is None or key in found:
                current = None
            else:
                found[key] = []
                current = key
            continue
        if current is not None:
            found[current].append(line)
    return {key: "\n".join(lines) for key, lines in found.items()}


def _colon_fields(text: str) -> dict[str, str]:
    found: dict[str, str] = {}
    for line in text.splitlines():
        match = COLON_RE.match(line.strip())
        if not match:
            continue
        key = HEADINGS[match.group(1).lower()]
        if key not in found:
            found[key] = match.group(2).strip()
    return found


def _first_line(section: str) -> str | None:
    for line in section.splitlines():
        line = line.strip()
        if not line or line.startswith("<!--"):
            continue
        return _unwrap(line)
    return None


def _parse_risk(section: str | None) -> tuple[tuple[str, ...] | None, str]:
    if section is None:
        return None, "missing risk area"
    checked: list[str] = []
    saw_box = False
    for line in section.splitlines():
        match = CHECKBOX_RE.match(line)
        if not match:
            continue
        saw_box = True
        if match.group(1).lower() == "x":
            checked.append(_unwrap(match.group(2)))
    names = checked
    if not saw_box:
        line = _first_line(section)
        if line is None:
            return None, "missing risk area"
        names = [_unwrap(part) for part in line.split(",")]
    if not names:
        return None, "missing risk area"
    if any(not name for name in names):
        return None, "unparseable risk area"
    chosen: list[str] = []
    for name in names:
        canon = RISK_LOOKUP.get(name.strip().lower())
        if canon is None:
            return None, "unparseable risk area"
        chosen.append(canon)
    ordered = tuple(name for name in RISK_ORDER if name in set(chosen))
    return ordered, ""


def _parse_token(section: str | None, allowed: frozenset[str], field: str, *, lower: bool) -> tuple[str | None, str]:
    label = FIELD_LABEL[field]
    if section is None:
        return None, f"missing {label}"
    raw = _first_line(section)
    if raw is None:
        return None, f"missing {label}"
    token = raw.lower() if lower else raw
    if token not in allowed:
        return None, f"unparseable {label}"
    return token, ""


def _format_score(score: Decimal) -> str:
    text = format(score, "f")
    if "." in text:
        text = text.rstrip("0").rstrip(".")
    return text


def bucket_for(score: Decimal) -> str:
    """rice: under-100 / 100-399 / 400-999 / 1000-plus. See the module doc."""
    if score < 100:
        return RICE_UNDER_100
    if score < 400:
        return RICE_100_399
    if score < 1000:
        return RICE_400_999
    return RICE_1000_PLUS


def _path_for(severity: str, risk: tuple[str, ...]) -> tuple[str, str]:
    if severity == "high":
        return PATH_ESCALATE, "severity high"
    if severity in {"med", "high"} and HIGH_BLAST.intersection(risk):
        return PATH_ESCALATE, "high-blast risk with severity med"
    return PATH_AUTO, "auto-merge"


def _field(sections: dict[str, str], colons: dict[str, str], key: str) -> str | None:
    if key in sections:
        return sections[key]
    if key in colons:
        return colons[key]
    return None


def _unparsed(reason: str) -> Decision:
    return Decision(
        parsed=False, path=PATH_ESCALATE, bucket=None, score_text=None,
        reach=None, impact=None, confidence=None, effort=None, severity=None,
        risk=(), reason=reason,
    )


def score_body(body: str) -> Decision:
    """Parse one issue body. Unparseable input escalates and has no bucket.

    The first failing field wins, in the order reach, impact, confidence,
    effort, risk area, severity. A heading is used before a `Field:` line.
    """
    text = _visible_body(body or "")
    sections = _sections(text)
    colons = _colon_fields(text)

    reach, err = _parse_token(_field(sections, colons, "reach"), REACH, "reach", lower=False)
    if err or reach is None:
        return _unparsed(err or "missing reach")
    impact, err = _parse_token(_field(sections, colons, "impact"), IMPACT, "impact", lower=False)
    if err or impact is None:
        return _unparsed(err or "missing impact")
    confidence, err = _parse_token(_field(sections, colons, "confidence"), CONFIDENCE, "confidence", lower=False)
    if err or confidence is None:
        return _unparsed(err or "missing confidence")
    effort, err = _parse_token(_field(sections, colons, "effort"), EFFORT, "effort", lower=False)
    if err or effort is None:
        return _unparsed(err or "missing effort")
    risk, err = _parse_risk(_field(sections, colons, "risk"))
    if err or risk is None:
        return _unparsed(err or "missing risk area")
    severity, err = _parse_token(_field(sections, colons, "severity"), SEVERITY, "severity", lower=True)
    if err or severity is None:
        return _unparsed(err or "missing severity")

    score = Decimal(reach) * Decimal(impact) * Decimal(confidence) / Decimal(effort)
    path, path_reason = _path_for(severity, risk)
    return Decision(
        parsed=True,
        path=path,
        bucket=bucket_for(score),
        score_text=_format_score(score),
        reach=reach,
        impact=impact,
        confidence=confidence,
        effort=effort,
        severity=severity,
        risk=risk,
        reason=path_reason,
    )


def desired_labels(decision: Decision, mode: str, current: set[str]) -> set[str]:
    """Labels this run should leave on the issue. Other labels are untouched.

    mode "issue" is an opened or edited event. mode "backfill" is workflow_dispatch.
    needs-fields is added only while backfilling an unparseable body, and kept
    on a later unparseable edit until a parsed run removes it.
    """
    if mode not in {"issue", "backfill"}:
        raise ValueError(f"unknown mode: {mode}")
    labels = {decision.path}
    if decision.parsed and decision.bucket:
        labels.add(decision.bucket)
    if not decision.parsed and (mode == "backfill" or NEEDS_FIELDS in current):
        labels.add(NEEDS_FIELDS)
    return labels


def label_delta(desired: set[str], current: set[str]) -> tuple[list[str], list[str]]:
    add = sorted(desired - current)
    remove = sorted((current & MANAGED_LABELS) - desired)
    return add, remove


def comment_body(decision: Decision) -> str:
    """One bot comment. Built only from parsed tokens and fixed sentences."""
    if decision.parsed:
        score_line = (
            f"RICE score: {decision.score_text} "
            f"(reach {decision.reach} * impact {decision.impact} "
            f"* confidence {decision.confidence} / effort {decision.effort})."
        )
        bucket_line = f"Bucket: `{decision.bucket}`."
        risk_line = f"Risk: {', '.join(decision.risk)}. Severity: {decision.severity}."
    else:
        score_line = f"RICE score: not parsed ({decision.reason})."
        bucket_line = "Bucket: none."
        risk_line = "Risk: not parsed."
    lines = [
        MARKER,
        "",
        score_line,
        bucket_line,
        risk_line,
        f"Path: `{decision.path}`.",
        f"Reason: {decision.reason}.",
        "",
        "Routing hint only. This is not an approval record. "
        "Approvals are tracked outside this repository.",
        "",
        "Escalate when a high-blast risk area is selected and severity is med or high, "
        "when severity is high, or when a form field is missing or unparseable. "
        "Otherwise the path is auto-merge.",
        "",
    ]
    return "\n".join(lines)


def select_comment(comments: list[dict]) -> dict | None:
    """Oldest workflow comment that carries the marker. Human comments are left alone."""
    matches = []
    for comment in comments:
        user = comment.get("user") or {}
        if user.get("login") != COMMENT_LOGIN:
            continue
        if MARKER not in (comment.get("body") or ""):
            continue
        matches.append(comment)
    if not matches:
        return None
    matches.sort(key=lambda comment: int(comment.get("id") or 0))
    return matches[0]


def label_names(labels: list | None) -> set[str]:
    names: set[str] = set()
    for item in labels or []:
        if isinstance(item, str):
            names.add(item)
        elif isinstance(item, dict) and item.get("name"):
            names.add(str(item["name"]))
    return names


def sync_comment(client, number: int, body: str) -> str:
    chosen = select_comment(client.list_comments(number))
    if chosen is None:
        client.create_comment(number, body)
        return "created"
    if (chosen.get("body") or "").strip() == body.strip():
        return "unchanged"
    client.update_comment(int(chosen["id"]), body)
    return "updated"


def apply_issue(client, number: int, body: str, current: set[str], mode: str) -> Decision:
    """Set the managed labels and the one bot comment. Returns the decision."""
    decision = score_body(body)
    add, remove = label_delta(desired_labels(decision, mode, current), current)
    if add or remove:
        client.edit_labels(number, add, remove)
    action = sync_comment(client, number, comment_body(decision))
    rice = decision.bucket or "-"
    parsed = "yes" if decision.parsed else "no"
    print(f"issue #{number} path={decision.path} rice={rice} parsed={parsed} comment={action}")
    return decision


class Gh:
    """Issue reads and writes through `gh`. The body is never a shell argument."""

    def __init__(self, repo: str):
        if not REPO_RE.fullmatch(repo or ""):
            raise RuntimeError("repository must look like owner/name")
        self.repo = repo

    def _run(self, cmd: list[str], payload: dict | None = None):
        proc = subprocess.run(
            cmd,
            input=None if payload is None else json.dumps(payload),
            text=True,
            capture_output=True,
        )
        if proc.returncode != 0:
            detail = (proc.stderr or proc.stdout or "").strip().splitlines()
            tail = detail[-1] if detail else "unknown error"
            raise RuntimeError(f"{cmd[0]} {cmd[1]} failed: {tail}")
        return proc.stdout

    def _api(self, method: str, path: str, payload: dict | None = None):
        cmd = ["gh", "api", "--method", method, path]
        if payload is not None:
            cmd.extend(["--input", "-"])
        text = self._run(cmd, payload).strip()
        if not text:
            return None
        return json.loads(text)

    def _pages(self, path: str) -> list:
        items: list = []
        page = 1
        while page <= 20:
            sep = "&" if "?" in path else "?"
            batch = self._api("GET", f"{path}{sep}per_page=100&page={page}")
            if not isinstance(batch, list) or not batch:
                return items
            items.extend(batch)
            if len(batch) < 100:
                return items
            page += 1
        raise RuntimeError(f"page cap exceeded for {path.split('?', 1)[0]}")

    def ensure_labels(self) -> None:
        existing = {item.get("name") for item in self._pages(f"repos/{self.repo}/labels")}
        for name, color, description in LABEL_SPECS:
            if name in existing:
                continue
            self._api("POST", f"repos/{self.repo}/labels", {
                "name": name, "color": color, "description": description,
            })

    def list_open_issues(self, author: str) -> list[dict]:
        creator = urllib.parse.quote(author, safe="")
        issues = self._pages(f"repos/{self.repo}/issues?state=open&creator={creator}")
        kept = []
        for issue in issues:
            login = ((issue.get("user") or {}).get("login")) or ""
            if login != author or "pull_request" in issue:
                continue
            kept.append(issue)
        kept.sort(key=lambda issue: int(issue.get("number") or 0))
        return kept

    def edit_labels(self, number: int, add: list[str], remove: list[str]) -> None:
        if not add and not remove:
            return
        cmd = ["gh", "issue", "edit", str(int(number)), "--repo", self.repo]
        for label in add:
            cmd.extend(["--add-label", label])
        for label in remove:
            cmd.extend(["--remove-label", label])
        self._run(cmd)

    def list_comments(self, number: int) -> list[dict]:
        return self._pages(f"repos/{self.repo}/issues/{int(number)}/comments")

    def create_comment(self, number: int, body: str) -> None:
        self._api("POST", f"repos/{self.repo}/issues/{int(number)}/comments", {"body": body})

    def update_comment(self, comment_id: int, body: str) -> None:
        self._api("PATCH", f"repos/{self.repo}/issues/comments/{int(comment_id)}", {"body": body})


def _issue_from_event(event: dict) -> tuple[int, str, set[str]] | None:
    issue = event.get("issue") or {}
    login = ((issue.get("user") or {}).get("login")) or ""
    if login != SCORED_AUTHOR:
        print("skip: issue author is not the scored login")
        return None
    if "pull_request" in issue:
        print("skip: event is a pull request")
        return None
    if "number" not in issue:
        raise RuntimeError("event issue has no number")
    number = issue.get("number")
    if not isinstance(number, int) or isinstance(number, bool) or number < 1:
        raise RuntimeError("event issue number is not a positive integer")
    return number, issue.get("body") or "", label_names(issue.get("labels"))


def apply_event(event: dict, event_name: str, client, dry_run: bool) -> int:
    if event_name == "workflow_dispatch":
        if dry_run:
            print("dry-run: backfill would score open issues by the scored login")
            return 0
        client.ensure_labels()
        for issue in client.list_open_issues(SCORED_AUTHOR):
            apply_issue(
                client,
                int(issue["number"]),
                issue.get("body") or "",
                label_names(issue.get("labels")),
                "backfill",
            )
        return 0
    if event_name != "issues":
        print("skip: event is not issues or workflow_dispatch")
        return 0
    action = event.get("action") or ""
    if action not in {"opened", "edited"}:
        print("skip: action is not opened or edited")
        return 0
    picked = _issue_from_event(event)
    if picked is None:
        return 0
    number, body, current = picked
    decision = score_body(body)
    add, remove = label_delta(desired_labels(decision, "issue", current), current)
    if dry_run:
        added = ",".join(add) or "-"
        removed = ",".join(remove) or "-"
        rice = decision.bucket or "-"
        print(f"dry-run issue #{number} path={decision.path} rice={rice} add={added} remove={removed}")
        return 0
    client.ensure_labels()
    apply_issue(client, number, body, current, "issue")
    return 0


def print_decision(decision: Decision) -> None:
    print(f"parsed: {'yes' if decision.parsed else 'no'}")
    print(f"path: {decision.path}")
    print(f"rice: {decision.bucket or '-'}")
    print(f"score: {decision.score_text or '-'}")
    print(f"reason: {decision.reason}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Score issue triage fields and apply routing labels.")
    parser.add_argument("--self-test", action="store_true", help="Run tools/issue_triage_test.py")
    parser.add_argument("--body-file", help="Score one body and print the decision. No GitHub calls.")
    parser.add_argument("--event", help="Path to a GitHub event JSON file.")
    parser.add_argument("--event-name", default=os.environ.get("GITHUB_EVENT_NAME", ""))
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", ""))
    parser.add_argument("--dry-run", action="store_true", help="Print the label plan. No GitHub calls.")
    args = parser.parse_args(argv)

    if args.self_test:
        test = Path(__file__).with_name("issue_triage_test.py")
        proc = subprocess.run([sys.executable, str(test)])
        return proc.returncode
    if args.body_file and args.event:
        print("error: pass only one of --body-file and --event", file=sys.stderr)
        return 2
    if args.body_file:
        body = Path(args.body_file).read_text(encoding="utf-8")
        print_decision(score_body(body))
        return 0
    if not args.event:
        print("error: pass --body-file, --event, or --self-test", file=sys.stderr)
        return 2
    try:
        event = json.loads(Path(args.event).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"error: cannot read event JSON: {exc.__class__.__name__}", file=sys.stderr)
        return 1
    client = None
    if not args.dry_run:
        if not args.repo or not REPO_RE.fullmatch(args.repo):
            print("error: repository must look like owner/name", file=sys.stderr)
            return 1
        client = Gh(args.repo)
    try:
        return apply_event(event, args.event_name, client, args.dry_run)
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
