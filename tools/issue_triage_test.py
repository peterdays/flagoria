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
BLAST = ("saves/world data", "netcode/multiplayer sync", "release/signing/CI", "security/privacy")
FAILED = 0


def check(name, ok, detail=""):
    global FAILED
    FAILED += not ok
    if not ok:
        print(f"FAIL {name}: {detail}")


def form(reach="5", impact="1", confidence="80", effort="1", risk=("none",), severity="low",
         preface=True, boxes=True):
    parts = []
    if preface:
        parts.append("### What it does\n\nAdd a thing.\n\n### Scope\n\nIncluded.\n\n### Done when\n\n- [ ] A test passes.\n")
    for label, value in (("Reach", reach), ("Impact", impact), ("Confidence", confidence), ("Effort", effort)):
        if value is not None:
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


def colon_form(**kw):
    fields = {"reach": "5", "impact": "1", "confidence": "80", "effort": "1", "severity": "low"}
    risk = kw.pop("risk", ("none",))
    fields.update(kw)
    return (
        f"Reach: {fields['reach']}\nImpact: {fields['impact']}\nConfidence: {fields['confidence']}\n"
        f"Effort: {fields['effort']}\nRisk area: {', '.join(risk)}\nSeverity: {fields['severity']}\n"
    )


def expect(body, **want):
    decision = it.score_body(body)
    bad = [f"{k}: got {getattr(decision, k)!r} want {v!r}" for k, v in want.items() if getattr(decision, k) != v]
    return bad, decision


def run_scores():
    low = dict(parsed=True, path=it.PATH_AUTO, bucket=it.RICE_LOW, score_text="4", reason="auto-merge")
    cases = [
        ("auto low none", form(), {**low, "severity": "low", "risk": ("none",)}),
        ("auto med core", form(severity="med", risk=("core input",)), dict(parsed=True, path=it.PATH_AUTO, reason="auto-merge", risk=("core input",))),
        ("auto med none", form(severity="med"), dict(parsed=True, path=it.PATH_AUTO, reason="auto-merge")),
        ("auto med core and none", form(severity="med", risk=("core input", "none")), dict(parsed=True, path=it.PATH_AUTO, risk=("core input", "none"))),
        ("auto low all blast", form(risk=BLAST), dict(parsed=True, path=it.PATH_AUTO, reason="auto-merge")),
        ("escalate high none", form(severity="high"), dict(parsed=True, path=it.PATH_ESCALATE, reason="severity high", bucket=it.RICE_LOW)),
        ("escalate high core", form(severity="high", risk=("core input",)), dict(parsed=True, path=it.PATH_ESCALATE, reason="severity high")),
        ("escalate high plus blast", form(severity="high", risk=("security/privacy",)), dict(parsed=True, path=it.PATH_ESCALATE, reason="severity high", risk=("security/privacy",))),
        ("empty", "", dict(parsed=False, path=it.PATH_ESCALATE, bucket=None, reason="missing reach")),
        ("preface only", form(reach=None, impact=None, confidence=None, effort=None, risk=None, severity=None), dict(parsed=False, reason="missing reach", bucket=None)),
        ("severity alone", "### Severity\n\nhigh\n", dict(parsed=False, path=it.PATH_ESCALATE, bucket=None, reason="missing reach")),
        ("missing effort", form(effort=None), dict(parsed=False, reason="missing effort", bucket=None)),
        ("blank effort", form(effort=""), dict(parsed=False, reason="missing effort")),
        ("first bad field", form(reach="nope", impact="nope"), dict(parsed=False, reason="unparseable reach")),
        ("unknown risk", form(risk=("graphics",), boxes=False), dict(parsed=False, reason="unparseable risk area")),
        ("unchecked", form(risk=()), dict(parsed=False, reason="missing risk area")),
        ("empty box", "### Reach\n\n5\n\n### Impact\n\n1\n\n### Confidence\n\n80\n\n### Effort\n\n1\n\n### Risk area\n\n- [x]\n\n### Severity\n\nlow\n", dict(parsed=False, reason="unparseable risk area")),
        ("missing risk", form(risk=None), dict(parsed=False, reason="missing risk area")),
        ("severity case", form(severity="HIGH"), dict(parsed=True, path=it.PATH_ESCALATE, severity="high", reason="severity high")),
        ("low case", form(severity="Low"), dict(parsed=True, path=it.PATH_AUTO, severity="low")),
        ("strip", form(reach="  5  "), dict(parsed=True, reach="5", score_text="4")),
        ("wrapped", form(reach="`5`"), dict(parsed=True, reach="5")),
        ("bold", form(impact="**1**"), dict(parsed=True, impact="1")),
        ("upper checkbox", form().replace("- [x] none", "- [X] none"), dict(parsed=True, risk=("none",))),
        ("risk case", form(severity="med", risk=("security/privacy",)).replace("security/privacy", "Security/Privacy"), dict(parsed=True, path=it.PATH_ESCALATE, reason="high-blast risk with severity med", risk=("security/privacy",))),
        ("comma auto", form(severity="med", risk=("core input", "none"), boxes=False), dict(parsed=True, path=it.PATH_AUTO, risk=("core input", "none"))),
        ("comma blast", form(severity="med", risk=("none", "saves/world data"), boxes=False), dict(parsed=True, path=it.PATH_ESCALATE, reason="high-blast risk with severity med", risk=("saves/world data", "none"))),
        ("crlf", form().replace("\n", "\r\n"), dict(parsed=True, score_text="4", bucket=it.RICE_LOW)),
        ("heading case", form().replace("### Reach", "### rEaCh"), dict(parsed=True, reach="5")),
        ("colon", colon_form(), dict(parsed=True, path=it.PATH_AUTO, score_text="4", risk=("none",))),
        ("colon blast", colon_form(severity="med", risk=("release/signing/CI",)), dict(parsed=True, path=it.PATH_ESCALATE, reason="high-blast risk with severity med")),
        ("fence", "```\n### Reach\n\n5\n### Impact\n\n1\n### Confidence\n\n80\n### Effort\n\n1\n### Risk area\n\n- [x] none\n### Severity\n\nlow\n```\n", dict(parsed=False, reason="missing reach")),
        ("heading beats colon", "### Scope\n\nReach: 1\n\n" + form(reach="10", impact="1", confidence="100", effort="1"), dict(parsed=True, reach="10", score_text="10", bucket=it.RICE_MED)),
        ("first heading", form(reach="1", impact="1", confidence="100", effort="1") + "\n### Reach\n\n10\n", dict(parsed=True, reach="1", score_text="1", bucket=it.RICE_LOW)),
        ("done-when is not risk", form(), dict(parsed=True, risk=("none",))),
    ]
    for field, tokens in {
        "reach": ("11", "0", "01", "many"), "impact": ("4", "1.0", "0.50"),
        "confidence": ("0.8", "90", "80%"), "effort": ("3", "8"), "severity": ("medium", "critical"),
    }.items():
        for token in tokens:
            cases.append((f"bad {field} {token}", form(**{field: token}), dict(parsed=False, bucket=None, reason=f"unparseable {field}")))
    for area in BLAST:
        cases.append((f"auto low {area}", form(risk=(area,)), dict(parsed=True, path=it.PATH_AUTO, reason="auto-merge", risk=(area,))))
        cases.append((f"escalate med {area}", form(severity="med", risk=(area,)), dict(parsed=True, path=it.PATH_ESCALATE, reason="high-blast risk with severity med", risk=(area,))))
        decision = it.score_body(form(severity="med", risk=(area,)))
        check(f"label med {area}", it.desired_labels(decision, "issue", set()) == {it.PATH_ESCALATE, decision.bucket})
    # Edges: 6 is med, 12 is high. Confidence 50/80/100 becomes 0.5/0.8/1.
    for nums, score, bucket in (
        (("1", "0.25", "50", "4"), "0.03125", it.RICE_LOW),
        (("10", "1", "50", "1"), "5", it.RICE_LOW),
        (("5", "0.5", "80", "2"), "1", it.RICE_LOW),
        (("2", "2", "50", "0.5"), "4", it.RICE_LOW),
        (("4", "1", "80", "1"), "3.2", it.RICE_LOW),
        (("5", "3", "80", "2"), "6", it.RICE_MED),
        (("7", "2", "80", "1"), "11.2", it.RICE_MED),
        (("10", "1", "100", "1"), "10", it.RICE_MED),
        (("10", "3", "80", "2"), "12", it.RICE_HIGH),
        (("10", "3", "100", "0.25"), "120", it.RICE_HIGH),
    ):
        reach, impact, confidence, effort = nums
        cases.append((f"bucket {score}", form(reach=reach, impact=impact, confidence=confidence, effort=effort), dict(
            parsed=True, path=it.PATH_AUTO, score_text=score, bucket=bucket, reach=reach, impact=impact, confidence=confidence, effort=effort)))
    for name, body, want in cases:
        bad, _decision = expect(body, **want)
        check(name, not bad, "; ".join(bad))
    for n in range(1, 11):
        decision = it.score_body(form(reach=str(n)))
        check(f"reach {n}", decision.parsed and decision.reach == str(n))


def run_labels():
    auto, missing = it.score_body(form()), it.score_body("")

    def labels(name, decision, mode, current, exact):
        got = it.desired_labels(decision, mode, current)
        check(name, got == exact and len(got & it.PATH_LABELS) == 1, sorted(got))

    labels("parsed", auto, "issue", set(), {it.PATH_AUTO, it.RICE_LOW})
    stale = {it.PATH_ESCALATE, it.RICE_HIGH, it.NEEDS_FIELDS, "bug"}
    labels("clears stale", auto, "issue", stale, {it.PATH_AUTO, it.RICE_LOW})
    _add, remove = it.label_delta(it.desired_labels(auto, "issue", stale), stale)
    check("bug stays", "bug" not in _add and "bug" not in remove)
    check("stale removed", set(remove) == {it.PATH_ESCALATE, it.RICE_HIGH, it.NEEDS_FIELDS}, remove)
    labels("live missing", missing, "issue", set(), {it.PATH_ESCALATE})
    labels("keeps needs", missing, "issue", {it.NEEDS_FIELDS}, {it.PATH_ESCALATE, it.NEEDS_FIELDS})
    labels("backfill missing", missing, "backfill", set(), {it.PATH_ESCALATE, it.NEEDS_FIELDS})
    check("no rice when unparsed", not (it.desired_labels(missing, "backfill", set()) & it.RICE_LABELS))
    planted = "not-a-reach-value-zz"
    text, good = it.comment_body(it.score_body(form(reach=planted))), it.comment_body(auto)
    check("comment", planted not in text and text.startswith(it.MARKER + "\n") and "not an approval record" in text
          and "outside this repository" in text and "confidence 0.8 / effort 1" in good and "`triage: auto-merge`" in good)
    human = {"id": 1, "user": {"login": "someone"}, "body": it.MARKER + "\nhuman"}
    older = {"id": 2, "user": {"login": it.COMMENT_LOGIN}, "body": it.MARKER + "\nold"}
    newer = {"id": 9, "user": {"login": it.COMMENT_LOGIN}, "body": it.MARKER + "\nnew"}
    chosen = it.select_comment([newer, human, {"id": 3, "user": {"login": it.COMMENT_LOGIN}, "body": "no"}, older])
    check("oldest bot", chosen is not None and chosen["id"] == 2 and it.select_comment([human]) is None)

    class Fake:
        def __init__(self, comments=None):
            self.edits, self.created, self.updated, self.comments = [], [], [], list(comments or [])

        def edit_labels(self, number, add, remove):
            self.edits.append((number, list(add), list(remove)))

        def list_comments(self, _n):
            return list(self.comments)

        def create_comment(self, _n, body):
            self.created.append(body)
            self.comments.append({"id": 100 + len(self.comments), "user": {"login": it.COMMENT_LOGIN}, "body": body})

        def update_comment(self, cid, body):
            self.updated.append((cid, body))

    fake = Fake(comments=[human])
    it.apply_issue(fake, 12, form(), {"bug"}, "issue")
    check("apply add", fake.edits == [(12, [it.RICE_LOW, it.PATH_AUTO], [])] and len(fake.created) == 1, fake.edits)
    it.apply_issue(fake, 12, form(), {it.RICE_LOW, it.PATH_AUTO, "bug"}, "issue")
    check("apply noop", len(fake.edits) == 1 and len(fake.created) == 1 and fake.updated == [])
    it.apply_issue(fake, 12, form(severity="high"), {it.RICE_LOW, it.PATH_AUTO, "bug"}, "issue")
    check("path change", fake.edits[-1] == (12, [it.PATH_ESCALATE], [it.PATH_AUTO]) and "`triage: escalate`" in fake.updated[0][1])
    backfill = Fake()
    it.apply_issue(backfill, 3, "", set(), "backfill")
    check("backfill", backfill.edits == [(3, [it.PATH_ESCALATE, it.NEEDS_FIELDS], [])] and backfill.created == [it.comment_body(missing)])


def run_contract():
    script = ROOT / "tools" / "issue_triage.py"
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        body = tmp_path / "body.md"
        body.write_text(form(severity="med", risk=("netcode/multiplayer sync",)), encoding="utf-8")
        proc = subprocess.run([sys.executable, str(script), "--body-file", str(body)], text=True, capture_output=True)
        check("cli", proc.returncode == 0 and "path: triage: escalate" in proc.stdout and "high-blast risk with severity med" in proc.stdout, proc.stdout)
        event = {"action": "opened", "issue": {"number": 7, "body": form(), "user": {"login": it.SCORED_AUTHOR}, "labels": [{"name": "bug"}]}}
        path = tmp_path / "event.json"
        path.write_text(json.dumps(event), encoding="utf-8")
        env = {**os.environ, "PATH": str(tmp_path)}
        dry = subprocess.run([sys.executable, str(script), "--event", str(path), "--event-name", "issues", "--dry-run"], text=True, capture_output=True, env=env)
        check("dry-run", dry.returncode == 0 and "add=rice: low,triage: auto-merge" in dry.stdout, dry.stdout)
        event["issue"]["user"]["login"] = "someone-else"
        path.write_text(json.dumps(event), encoding="utf-8")
        skipped = subprocess.run([sys.executable, str(script), "--event", str(path), "--event-name", "issues", "--dry-run"], text=True, capture_output=True, env=env)
        check("other author", skipped.returncode == 0 and skipped.stdout.strip() == "skip: issue author is not the scored login")
        event["issue"]["user"]["login"] = it.SCORED_AUTHOR
        event["action"] = "labeled"
        path.write_text(json.dumps(event), encoding="utf-8")
        labeled = subprocess.run([sys.executable, str(script), "--event", str(path), "--event-name", "issues", "--dry-run"], text=True, capture_output=True)
        check("labeled", labeled.returncode == 0 and "not opened or edited" in labeled.stdout)
        backfill = subprocess.run([sys.executable, str(script), "--event", str(path), "--event-name", "workflow_dispatch", "--dry-run"], text=True, capture_output=True, env=env)
        check("dispatch", backfill.returncode == 0 and "backfill would score" in backfill.stdout, backfill.stderr)
        path.write_text(json.dumps({"action": "opened", "issue": {"user": {"login": it.SCORED_AUTHOR}, "body": "x"}}), encoding="utf-8")
        bad = subprocess.run([sys.executable, str(script), "--event", str(path), "--event-name", "issues"], text=True, capture_output=True, env={**env, "GITHUB_REPOSITORY": "example/flagoria"})
        check("missing number", bad.returncode == 1 and "no number" in bad.stderr, bad.stderr)
    workflow = (ROOT / ".github/workflows/issue-triage.yml").read_text(encoding="utf-8")
    perms = workflow.split("permissions:", 1)[1].split("concurrency:", 1)[0]
    check("workflow", all((
        f"github.event.issue.user.login == '{it.SCORED_AUTHOR}'" in workflow,
        "types: [opened, edited]" in workflow, "workflow_dispatch:" in workflow,
        "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1" in workflow,
        "persist-credentials: false" in workflow, "secrets." not in workflow,
        "github.event.issue.body" not in workflow, "pull_request_target" not in workflow,
        "contents: read" in perms, "issues: write" in perms, "contents: write" not in perms,
        "pull-requests:" not in perms, "id-token:" not in perms, "actions:" not in perms,
        'python3 tools/issue_triage.py --event "$GITHUB_EVENT_PATH"' in workflow,
    )))
    form_text = (ROOT / ".github/ISSUE_TEMPLATE/task.yml").read_text(encoding="utf-8")
    tokens = ["0.25", "0.5", "1", "2", "3", "4", "50", "80", "100", "low", "med", "high", *[str(n) for n in range(1, 11)]]
    check("form", all(f'"{t}"' in form_text for t in tokens) and all(f'label: "{n}"' in form_text for n in it.RISK_ORDER)
          and form_text.count("required: true") >= 9 and form_text.count("type: dropdown") == 5 and "not an approval" in form_text)
    check("specs", all(len(d) <= 100 and len(c) == 6 for _n, c, d in it.LABEL_SPECS) and {s[0] for s in it.LABEL_SPECS} == set(it.MANAGED_LABELS))
    check("blast set", it.HIGH_BLAST == frozenset(BLAST) and "core input" not in it.HIGH_BLAST and "none" not in it.HIGH_BLAST)
    doc = it.__doc__ or ""
    check("doc", all(p in doc for p in ("reach * impact * confidence / effort", "score < 6", "6 <= score < 12", "score >= 12", "0.5, 0.8 or 1")))
    agents = (ROOT / "AGENTS.md").read_text(encoding="utf-8")
    needed = ["triage: auto-merge", "triage: escalate", "triage: needs-fields", "rice: low", "rice: med", "rice: high",
              "not an approval record", "outside this repository", "reach * impact * confidence / effort", *BLAST, "core input", "0.5, 0.8 or 1"]
    check("docs", all(p in agents for p in needed) and "rice: under-100" not in agents, ", ".join(p for p in needed if p not in agents))


def main() -> int:
    run_scores()
    run_labels()
    run_contract()
    print("issue triage tests: ok" if not FAILED else f"issue triage tests: {FAILED} failed")
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main())
