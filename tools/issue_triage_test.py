#!/usr/bin/env python3
"""Fixture bodies for tools/issue_triage.py. Run: python3 tools/issue_triage_test.py"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import issue_triage as it  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
BLAST = (
    "saves/world data",
    "netcode/multiplayer sync",
    "release/signing/CI",
    "security/privacy",
)
FAILED = 0


def check(name, ok, detail=""):
    global FAILED
    FAILED += not ok
    if not ok:
        print(f"FAIL {name}: {detail}")


def form(reach="5", impact="1", confidence="80", effort="1", risk=("none",), severity="low",
         preface=True, boxes=True):
    """Markdown the task form writes, plus the three required issue sections."""
    parts = []
    if preface:
        parts.append(
            "### What it does\n\nAdd a thing.\n\n### Scope\n\nIncluded.\n\n"
            "### Done when\n\n- [ ] A test passes.\n\n"
            "Triage scores are a routing hint for bots. They are not an approval.\n"
        )
    chunks = (
        ("Reach", reach), ("Impact", impact), ("Confidence", confidence),
        ("Effort", effort), ("Severity", severity),
    )
    for label, value in chunks:
        if value is not None and label != "Severity":
            parts.append(f"### {label}\n\n{value}\n")
    if risk is not None:
        if boxes:
            lines = [f"- [{'x' if name in risk else ' '}] {name}" for name in it.RISK_ORDER]
            parts.append("### Risk area\n\n" + "\n".join(lines) + "\n")
        else:
            parts.append("### Risk area\n\n" + ", ".join(risk) + "\n")
    if severity is not None:
        parts.append(f"### Severity\n\n{severity}\n")
    return "\n".join(parts)


def colon_form(reach="5", impact="1", confidence="80", effort="1", risk=("none",), severity="low"):
    return (
        "### What it does\n\nAdd a thing.\n\n"
        f"Reach: {reach}\nImpact: {impact}\nConfidence: {confidence}\n"
        f"Effort: {effort}\nRisk area: {', '.join(risk)}\nSeverity: {severity}\n"
    )


def expect(body, **want):
    decision = it.score_body(body)
    problems = [
        f"{key}: got {getattr(decision, key)!r} want {value!r}"
        for key, value in want.items() if getattr(decision, key) != value
    ]
    return problems, decision


def run_scores():
    cases = [
        ("auto low none", form(), dict(
            parsed=True, path=it.PATH_AUTO, bucket=it.RICE_400_999, score_text="400",
            severity="low", risk=("none",), reason="auto-merge")),
        ("auto med core input", form(severity="med", risk=("core input",)), dict(
            parsed=True, path=it.PATH_AUTO, reason="auto-merge", severity="med", risk=("core input",))),
        ("auto med none", form(severity="med"), dict(parsed=True, path=it.PATH_AUTO, reason="auto-merge")),
        ("auto med core and none", form(severity="med", risk=("core input", "none")), dict(
            parsed=True, path=it.PATH_AUTO, risk=("core input", "none"))),
        ("auto low all high-blast", form(risk=BLAST), dict(parsed=True, path=it.PATH_AUTO, reason="auto-merge")),
        ("escalate high none", form(severity="high"), dict(
            parsed=True, path=it.PATH_ESCALATE, reason="severity high", bucket=it.RICE_400_999)),
        ("escalate high core input", form(severity="high", risk=("core input",)), dict(
            parsed=True, path=it.PATH_ESCALATE, reason="severity high")),
        ("escalate high plus high-blast", form(severity="high", risk=("security/privacy",)), dict(
            parsed=True, path=it.PATH_ESCALATE, reason="severity high", risk=("security/privacy",))),
        ("empty body", "", dict(parsed=False, path=it.PATH_ESCALATE, bucket=None, reason="missing reach")),
        ("preface only", form(reach=None, impact=None, confidence=None, effort=None, risk=None, severity=None),
         dict(parsed=False, reason="missing reach", bucket=None)),
        ("severity alone", "### Severity\n\nhigh\n", dict(
            parsed=False, path=it.PATH_ESCALATE, bucket=None, reason="missing reach")),
        ("missing effort", form(effort=None), dict(parsed=False, reason="missing effort", bucket=None)),
        ("blank effort", form(effort=""), dict(parsed=False, reason="missing effort")),
        ("first bad field wins", form(reach="nope", impact="nope"), dict(parsed=False, reason="unparseable reach")),
        ("unknown risk", form(risk=("graphics",), boxes=False), dict(parsed=False, reason="unparseable risk area")),
        ("all boxes unchecked", form(risk=()), dict(parsed=False, reason="missing risk area")),
        ("empty checked box",
         "### Reach\n\n5\n\n### Impact\n\n1\n\n### Confidence\n\n80\n\n### Effort\n\n1\n\n"
         "### Risk area\n\n- [x]\n\n### Severity\n\nlow\n",
         dict(parsed=False, reason="unparseable risk area")),
        ("missing risk section", form(risk=None), dict(parsed=False, reason="missing risk area")),
        ("severity case", form(severity="HIGH"), dict(
            parsed=True, path=it.PATH_ESCALATE, severity="high", reason="severity high")),
        ("low and med case", form(severity="Low"), dict(parsed=True, path=it.PATH_AUTO, severity="low")),
        ("med case", form(severity="Med"), dict(parsed=True, path=it.PATH_AUTO, severity="med")),
        ("reach strips whitespace", form(reach="  5  "), dict(parsed=True, reach="5", score_text="400")),
        ("wrapped token", form(reach="`5`"), dict(parsed=True, reach="5")),
        ("bold token", form(impact="**1**"), dict(parsed=True, impact="1")),
        ("uppercase checkbox", form().replace("- [x] none", "- [X] none"), dict(
            parsed=True, risk=("none",), path=it.PATH_AUTO)),
        ("risk label case", form(severity="med", risk=("security/privacy",)).replace(
            "security/privacy", "Security/Privacy"), dict(
            parsed=True, path=it.PATH_ESCALATE, reason="high-blast risk with severity med",
            risk=("security/privacy",))),
        ("comma line", form(severity="med", risk=("core input", "none"), boxes=False), dict(
            parsed=True, path=it.PATH_AUTO, risk=("core input", "none"))),
        ("comma line high-blast", form(severity="med", risk=("none", "saves/world data"), boxes=False), dict(
            parsed=True, path=it.PATH_ESCALATE, reason="high-blast risk with severity med",
            risk=("saves/world data", "none"))),
        ("windows newlines", form().replace("\n", "\r\n"), dict(parsed=True, path=it.PATH_AUTO, score_text="400")),
        ("heading case", form().replace("### Reach", "### rEaCh"), dict(parsed=True, reach="5")),
        ("colon form", colon_form(), dict(parsed=True, path=it.PATH_AUTO, score_text="400", risk=("none",))),
        ("colon form med high-blast", colon_form(severity="med", risk=("release/signing/CI",)), dict(
            parsed=True, path=it.PATH_ESCALATE, reason="high-blast risk with severity med")),
        ("fenced fields ignored",
         "```\n### Reach\n\n5\n### Impact\n\n1\n### Confidence\n\n80\n### Effort\n\n1\n"
         "### Risk area\n\n- [x] none\n### Severity\n\nlow\n```\n",
         dict(parsed=False, reason="missing reach")),
        ("heading beats colon",
         "### Scope\n\nReach: 1\n\n" + form(reach="10", impact="1", confidence="100", effort="1"),
         dict(parsed=True, reach="10", score_text="1000", bucket=it.RICE_1000_PLUS)),
        ("first heading wins",
         form(reach="1", impact="1", confidence="100", effort="1") + "\n### Reach\n\n10\n",
         dict(parsed=True, reach="1", score_text="100", bucket=it.RICE_100_399)),
        ("done-when checkbox is not risk", form(), dict(parsed=True, risk=("none",))),
    ]
    bad = {
        "reach": ("11", "0", "01", "many"),
        "impact": ("4", "1.0", "0.50"),
        "confidence": ("0.8", "90", "80%"),
        "effort": ("3", "8"),
        "severity": ("medium", "critical"),
    }
    for field, tokens in bad.items():
        for token in tokens:
            cases.append((f"bad {field} {token}", form(**{field: token}), dict(
                parsed=False, bucket=None, reason=f"unparseable {field if field != 'severity' else 'severity'}")))
    # severity's label in the reason is "severity"; reach/impact/confidence/effort match the field name.
    for area in BLAST:
        cases.append((f"auto low {area}", form(risk=(area,)), dict(
            parsed=True, path=it.PATH_AUTO, reason="auto-merge", risk=(area,))))
        cases.append((f"escalate med {area}", form(severity="med", risk=(area,)), dict(
            parsed=True, path=it.PATH_ESCALATE, reason="high-blast risk with severity med", risk=(area,))))
        decision = it.score_body(form(severity="med", risk=(area,)))
        got = it.desired_labels(decision, "issue", set())
        check(f"med {area} label", got == {it.PATH_ESCALATE, decision.bucket}, sorted(got))
    boundaries = [
        (("1", "0.25", "50", "4"), "3.125", it.RICE_UNDER_100),
        (("3", "1", "50", "2"), "75", it.RICE_UNDER_100),
        (("5", "0.5", "80", "2"), "100", it.RICE_100_399),
        (("4", "1", "80", "1"), "320", it.RICE_100_399),
        (("2", "2", "50", "1"), "200", it.RICE_100_399),
        (("5", "1", "80", "1"), "400", it.RICE_400_999),
        (("2", "1", "50", "0.5"), "200", it.RICE_100_399),
        (("1", "3", "50", "0.25"), "600", it.RICE_400_999),
        (("9", "1", "100", "1"), "900", it.RICE_400_999),
        (("10", "1", "100", "1"), "1000", it.RICE_1000_PLUS),
        (("10", "3", "100", "0.25"), "12000", it.RICE_1000_PLUS),
    ]
    for (reach, impact, confidence, effort), score, bucket in boundaries:
        cases.append((f"bucket {reach} {impact} {confidence} {effort}", form(
            reach=reach, impact=impact, confidence=confidence, effort=effort), dict(
            parsed=True, path=it.PATH_AUTO, score_text=score, bucket=bucket,
            reach=reach, impact=impact, confidence=confidence, effort=effort)))
    for name, body, want in cases:
        problems, _decision = expect(body, **want)
        check(name, not problems, "; ".join(problems))
    for n in range(1, 11):
        decision = it.score_body(form(reach=str(n)))
        check(f"reach {n}", decision.parsed and decision.reach == str(n))


def run_labels():
    auto = it.score_body(form())
    missing = it.score_body("")

    def labels(name, decision, mode, current, exact):
        got = it.desired_labels(decision, mode, current)
        check(name, got == exact and len(got & it.PATH_LABELS) == 1, sorted(got))

    labels("parsed issue", auto, "issue", set(), {it.PATH_AUTO, it.RICE_400_999})
    stale = {it.PATH_ESCALATE, it.RICE_UNDER_100, it.NEEDS_FIELDS, "bug"}
    labels("parsed clears stale", auto, "issue", stale, {it.PATH_AUTO, it.RICE_400_999})
    add, remove = it.label_delta(it.desired_labels(auto, "issue", stale), stale)
    check("bug stays", "bug" not in add and "bug" not in remove, f"{add} {remove}")
    check("stale removed", set(remove) == {it.PATH_ESCALATE, it.RICE_UNDER_100, it.NEEDS_FIELDS}, remove)
    labels("live missing", missing, "issue", set(), {it.PATH_ESCALATE})
    labels("live keeps needs-fields", missing, "issue", {it.NEEDS_FIELDS}, {it.PATH_ESCALATE, it.NEEDS_FIELDS})
    labels("backfill missing", missing, "backfill", set(), {it.PATH_ESCALATE, it.NEEDS_FIELDS})
    check("unparsed has no rice", not (it.desired_labels(missing, "backfill", set()) & it.RICE_LABELS))

    planted = "not-a-reach-value-zz"
    bad = it.score_body(form(reach=planted))
    text = it.comment_body(bad)
    check("comment hides raw value", planted not in text and "unparseable reach" in text)
    good = it.comment_body(auto)
    check("comment contract",
          text.startswith(it.MARKER + "\n") and "not an approval record" in text
          and "outside this repository" in text
          and "reach 5 * impact 1 * confidence 80 / effort 1" in good
          and "`triage: auto-merge`" in good)

    human = {"id": 1, "user": {"login": "someone"}, "body": it.MARKER + "\nhuman"}
    older = {"id": 2, "user": {"login": it.COMMENT_LOGIN}, "body": it.MARKER + "\nold"}
    newer = {"id": 9, "user": {"login": it.COMMENT_LOGIN}, "body": it.MARKER + "\nnew"}
    other = {"id": 3, "user": {"login": it.COMMENT_LOGIN}, "body": "no marker"}
    chosen = it.select_comment([newer, human, other, older])
    check("oldest bot comment", chosen is not None and chosen["id"] == 2)
    check("human marker ignored", it.select_comment([human]) is None)

    class Fake:
        def __init__(self, comments=None):
            self.edits, self.created, self.updated = [], [], []
            self.comments = list(comments or [])

        def edit_labels(self, number, add, remove):
            self.edits.append((number, list(add), list(remove)))

        def list_comments(self, _number):
            return list(self.comments)

        def create_comment(self, _number, body):
            self.created.append(body)
            self.comments.append({"id": 100 + len(self.comments), "user": {"login": it.COMMENT_LOGIN}, "body": body})

        def update_comment(self, comment_id, body):
            self.updated.append((comment_id, body))

    fake = Fake(comments=[human])
    it.apply_issue(fake, 12, form(), {"bug"}, "issue")
    check("apply adds labels", fake.edits == [(12, [it.RICE_400_999, it.PATH_AUTO], [])], fake.edits)
    check("apply creates one comment", len(fake.created) == 1 and human["body"].endswith("human"))
    it.apply_issue(fake, 12, form(), {it.RICE_400_999, it.PATH_AUTO, "bug"}, "issue")
    check("second apply is a no-op", len(fake.edits) == 1 and len(fake.created) == 1 and fake.updated == [])
    it.apply_issue(fake, 12, form(severity="high"), {it.RICE_400_999, it.PATH_AUTO, "bug"}, "issue")
    check("path change", fake.edits[-1] == (12, [it.PATH_ESCALATE], [it.PATH_AUTO]) and fake.updated
          and "`triage: escalate`" in fake.updated[0][1], fake.edits[-1])
    backfill = Fake()
    it.apply_issue(backfill, 3, "", set(), "backfill")
    check("backfill labels", backfill.edits == [(3, [it.PATH_ESCALATE, it.NEEDS_FIELDS], [])], backfill.edits)
    check("backfill comment", backfill.created == [it.comment_body(missing)])


def run_contract():
    script = ROOT / "tools" / "issue_triage.py"
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        body_path = tmp_path / "body.md"
        body_path.write_text(form(severity="med", risk=("netcode/multiplayer sync",)), encoding="utf-8")
        proc = subprocess.run([sys.executable, str(script), "--body-file", str(body_path)],
                              text=True, capture_output=True, check=False)
        check("score cli", proc.returncode == 0 and "path: triage: escalate" in proc.stdout
              and "reason: high-blast risk with severity med" in proc.stdout, proc.stderr or proc.stdout)
        event = {"action": "opened", "issue": {
            "number": 7, "body": form(), "user": {"login": it.SCORED_AUTHOR}, "labels": [{"name": "bug"}]}}
        event_path = tmp_path / "event.json"
        event_path.write_text(json.dumps(event), encoding="utf-8")
        env = {**os.environ, "PATH": str(tmp_path)}
        dry = subprocess.run(
            [sys.executable, str(script), "--event", str(event_path), "--event-name", "issues", "--dry-run"],
            text=True, capture_output=True, check=False, env=env)
        check("dry-run", dry.returncode == 0 and "add=rice: 400-999,triage: auto-merge" in dry.stdout, dry.stdout)
        event["issue"]["user"]["login"] = "someone-else"
        event_path.write_text(json.dumps(event), encoding="utf-8")
        skipped = subprocess.run(
            [sys.executable, str(script), "--event", str(event_path), "--event-name", "issues", "--dry-run"],
            text=True, capture_output=True, check=False, env=env)
        check("other author", skipped.returncode == 0
              and skipped.stdout.strip() == "skip: issue author is not the scored login", skipped.stdout)
        event["issue"]["user"]["login"] = it.SCORED_AUTHOR
        event["action"] = "labeled"
        event_path.write_text(json.dumps(event), encoding="utf-8")
        labeled = subprocess.run(
            [sys.executable, str(script), "--event", str(event_path), "--event-name", "issues", "--dry-run"],
            text=True, capture_output=True, check=False)
        check("labeled ignored", labeled.returncode == 0 and "not opened or edited" in labeled.stdout, labeled.stdout)
        backfill = subprocess.run(
            [sys.executable, str(script), "--event", str(event_path), "--event-name", "workflow_dispatch", "--dry-run"],
            text=True, capture_output=True, check=False, env=env)
        check("dispatch dry-run", backfill.returncode == 0 and "backfill would score" in backfill.stdout, backfill.stderr)
        event_path.write_text(json.dumps(
            {"action": "opened", "issue": {"user": {"login": it.SCORED_AUTHOR}, "body": "x"}}), encoding="utf-8")
        bad_event = subprocess.run(
            [sys.executable, str(script), "--event", str(event_path), "--event-name", "issues"],
            text=True, capture_output=True, check=False,
            env={**env, "GITHUB_REPOSITORY": "example/flagoria"})
        check("missing number", bad_event.returncode == 1 and "no number" in bad_event.stderr, bad_event.stderr)

    workflow = (ROOT / ".github" / "workflows" / "issue-triage.yml").read_text(encoding="utf-8")
    perms = workflow.split("permissions:", 1)[1].split("concurrency:", 1)[0]
    check("workflow", (
        f"github.event.issue.user.login == '{it.SCORED_AUTHOR}'" in workflow
        and "types: [opened, edited]" in workflow and "workflow_dispatch:" in workflow
        and "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1" in workflow
        and "persist-credentials: false" in workflow
        and "secrets." not in workflow and "github.event.issue.body" not in workflow
        and "github.event.issue.title" not in workflow and "pull_request_target" not in workflow
        and "contents: read" in perms and "issues: write" in perms
        and "contents: write" not in perms and "pull-requests:" not in perms
        and "id-token:" not in perms and "actions:" not in perms
        and 'python3 tools/issue_triage.py --event "$GITHUB_EVENT_PATH"' in workflow
    ))
    form_text = (ROOT / ".github" / "ISSUE_TEMPLATE" / "task.yml").read_text(encoding="utf-8")
    tokens = ["0.25", "0.5", "1", "2", "3", "4", "50", "80", "100", "low", "med", "high"]
    tokens += [str(n) for n in range(1, 11)]
    check("form", (
        all(f'"{token}"' in form_text for token in tokens)
        and all(f'label: "{name}"' in form_text for name in it.RISK_ORDER)
        and all(f"id: {fid}" in form_text for fid in
                ("reach", "impact", "confidence", "effort", "risk-area", "severity"))
        and form_text.count("required: true") >= 9 and form_text.count("type: dropdown") == 5
        and "type: checkboxes" in form_text and "not an approval" in form_text
    ))
    check("label specs", all(len(desc) <= 100 and len(color) == 6 for _n, color, desc in it.LABEL_SPECS)
          and {spec[0] for spec in it.LABEL_SPECS} == set(it.MANAGED_LABELS))
    check("high-blast set", it.HIGH_BLAST == frozenset(BLAST)
          and "core input" not in it.HIGH_BLAST and "none" not in it.HIGH_BLAST)
    doc = it.__doc__ or ""
    check("doc formula", all(phrase in doc for phrase in (
        "reach * impact * confidence / effort", "score < 100", "100 <= score < 400",
        "400 <= score < 1000", "score >= 1000")))
    agents = (ROOT / "AGENTS.md").read_text(encoding="utf-8")
    needed = [
        "triage: auto-merge", "triage: escalate", "triage: needs-fields",
        "rice: under-100", "rice: 100-399", "rice: 400-999", "rice: 1000-plus",
        "not an approval record", "outside this repository",
        "reach * impact * confidence / effort", *BLAST, "core input",
    ]
    check("AGENTS.md", all(phrase in agents for phrase in needed),
          ", ".join(phrase for phrase in needed if phrase not in agents))


def main() -> int:
    run_scores()
    run_labels()
    run_contract()
    print(f"issue triage tests: {FAILED} failed" if FAILED else "issue triage tests: ok")
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main())
