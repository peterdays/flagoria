#!/usr/bin/env python3
"""Deterministic agent context budget: briefs, receipts, and PR check lines.

Replaces long free-form agent prompts and "trust me" Ready claims with fixed
fields a script can reject. See AGENTS.md (Agent context budget).

Brief (key: value lines, then optional Done when: block):
  Issue: #N | none
  Feature: .cursor/skills/verify-flagoria/features/<name>.md | not player-facing
  Drive: drives/<name>.gd | not player-facing
  Pinned: <repo-relative paths, comma-separated> | none
  Phase: implement | ready
  Max discovery reads: <int 1..10>
  Done when:
  - <observable check>

Receipt (key: value lines written after Ready checks):
  doctor: pass | fail
  ensure_godot: pass | skip | fail
  verify: pass once | fail once
  drive: pass once drives/<name>.gd | skip not-player-facing | fail once
  discovery_reads: <int>

PR "## How it was checked" must include:
  Verify: once
  Drive: once drives/<name>.gd
  or Drive: not player-facing

Commands:
  python3 tools/agent_budget.py emit-brief
  python3 tools/agent_budget.py check-brief FILE
  python3 tools/agent_budget.py check-receipt FILE [--brief FILE]
  python3 tools/agent_budget.py check-pr-how FILE
  python3 tools/agent_budget.py --self-test
"""
from __future__ import annotations

import argparse
import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FEATURE_ROOT = ROOT / ".cursor" / "skills" / "verify-flagoria" / "features"
DRIVE_ROOT = ROOT / ".cursor" / "skills" / "verify-flagoria" / "drives"
TEMPLATE_PATH = ROOT / ".cursor" / "skills" / "verify-flagoria" / "brief.template.md"

BRIEF_KEYS = (
    "Issue",
    "Feature",
    "Drive",
    "Pinned",
    "Phase",
    "Max discovery reads",
)
MAX_BRIEF_CHARS = 1200
MAX_DONE_CHARS = 400
MAX_DISCOVERY = 10

ISSUE_RE = re.compile(r"^(#\d+|none)$", re.I)
FEATURE_RE = re.compile(
    r"^(\.cursor/skills/verify-flagoria/features/[A-Za-z0-9_-]+\.md|not player-facing)$"
)
DRIVE_RE = re.compile(r"^(drives/[A-Za-z0-9_./-]+\.gd|not player-facing)$")
PHASE_RE = re.compile(r"^(implement|ready)$", re.I)
PINNED_ITEM_RE = re.compile(r"^[A-Za-z0-9_./-]+$")

VERIFY_PR_RE = re.compile(r"^[ \t]*Verify[ \t]*:[ \t]*once[ \t]*$", re.I | re.M)
DRIVE_PR_RE = re.compile(
    r"^[ \t]*Drive[ \t]*:[ \t]*(?:once[ \t]+drives/[A-Za-z0-9_./-]+\.gd|not player-facing)[ \t]*$",
    re.I | re.M,
)

RECEIPT_DOCTOR = re.compile(r"^(pass|fail)$", re.I)
RECEIPT_ENSURE = re.compile(r"^(pass|skip|fail)$", re.I)
RECEIPT_VERIFY = re.compile(r"^(pass once|fail once)$", re.I)
RECEIPT_DRIVE = re.compile(
    r"^(pass once drives/[A-Za-z0-9_./-]+\.gd|skip not-player-facing|fail once)$",
    re.I,
)

BRIEF_TEMPLATE = """Issue: none
Feature: not player-facing
Drive: not player-facing
Pinned: none
Phase: implement
Max discovery reads: 10
Done when:
- name the observable pass condition
"""


def _parse_kv_block(text: str) -> tuple[dict[str, str], list[str], list[str]]:
    """Parse leading KEY: value lines, then optional Done when: bullet block."""
    fields: dict[str, str] = {}
    done: list[str] = []
    errors: list[str] = []
    lines = text.replace("\r\n", "\n").split("\n")
    i = 0
    while i < len(lines):
        raw = lines[i]
        if not raw.strip() or raw.strip().startswith("#"):
            i += 1
            continue
        if re.match(r"^Done when[ \t]*:", raw, re.I):
            i += 1
            while i < len(lines):
                bullet = lines[i]
                if not bullet.strip():
                    i += 1
                    continue
                if re.match(r"^[A-Za-z].*:", bullet) and not bullet.lstrip().startswith("-"):
                    break
                m = re.match(r"^[ \t]*[-*][ \t]+(.+)$", bullet)
                if not m:
                    errors.append(f"Done when: expected bullet, got: {bullet.strip()}")
                    i += 1
                    continue
                done.append(m.group(1).strip())
                i += 1
            break
        m = re.match(r"^([A-Za-z][A-Za-z0-9_ ]*)[ \t]*:[ \t]*(.*)$", raw)
        if not m:
            errors.append(f"expected 'Key: value', got: {raw.strip()}")
            i += 1
            continue
        key, value = m.group(1).strip(), m.group(2).strip()
        if key in fields:
            errors.append(f"duplicate key: {key}")
        fields[key] = value
        i += 1
    return fields, done, errors


def check_brief(text: str, root: Path = ROOT) -> list[str]:
    errors: list[str] = []
    if len(text) > MAX_BRIEF_CHARS:
        errors.append(f"brief is {len(text)} chars, over the {MAX_BRIEF_CHARS} cap")
    fields, done, parse_errors = _parse_kv_block(text)
    errors.extend(parse_errors)
    for key in BRIEF_KEYS:
        if key not in fields or not fields[key]:
            errors.append(f"missing '{key}:'")
    for key in fields:
        if key not in BRIEF_KEYS:
            errors.append(f"unknown brief key: {key}")

    issue = fields.get("Issue", "")
    if issue and not ISSUE_RE.match(issue):
        errors.append("Issue: must be '#N' or 'none'")

    feature = fields.get("Feature", "")
    if feature and not FEATURE_RE.match(feature):
        errors.append(
            "Feature: must be '.cursor/skills/verify-flagoria/features/<name>.md' "
            "or 'not player-facing'"
        )
    elif feature.endswith(".md"):
        path = root / feature
        if not path.is_file():
            errors.append(f"Feature: file missing: {feature}")

    drive = fields.get("Drive", "")
    if drive and not DRIVE_RE.match(drive):
        errors.append("Drive: must be 'drives/<name>.gd' or 'not player-facing'")
    elif drive.startswith("drives/"):
        if not (root / ".cursor/skills/verify-flagoria" / drive).is_file():
            errors.append(f"Drive: file missing: {drive}")

    if feature.endswith(".md") and drive:
        feat_path = root / feature
        if feat_path.is_file():
            want = ""
            for line in feat_path.read_text(encoding="utf-8", errors="replace").splitlines():
                if line.startswith("Drive:"):
                    want = line.split(":", 1)[1].strip()
                    break
            if want and drive != want:
                errors.append(f"Drive: '{drive}' does not match feature Drive: '{want}'")

    if feature == "not player-facing" and drive != "not player-facing":
        errors.append("Feature: not player-facing requires Drive: not player-facing")

    pinned = fields.get("Pinned", "")
    if pinned:
        if pinned.lower() != "none":
            for item in [p.strip() for p in pinned.split(",")]:
                if not item or not PINNED_ITEM_RE.match(item):
                    errors.append(f"Pinned: bad path '{item}'")
                elif not (root / item).exists():
                    errors.append(f"Pinned: missing path '{item}'")

    phase = fields.get("Phase", "")
    if phase and not PHASE_RE.match(phase):
        errors.append("Phase: must be 'implement' or 'ready'")

    max_reads = fields.get("Max discovery reads", "")
    if max_reads:
        if not max_reads.isdigit() or not (1 <= int(max_reads) <= MAX_DISCOVERY):
            errors.append(f"Max discovery reads: must be an integer 1..{MAX_DISCOVERY}")

    done_text = "\n".join(done)
    if len(done_text) > MAX_DONE_CHARS:
        errors.append(f"Done when: is {len(done_text)} chars, over the {MAX_DONE_CHARS} cap")
    if not done:
        errors.append("Done when: needs at least one bullet")
    return errors


def check_receipt(text: str, brief_text: str | None = None) -> list[str]:
    errors: list[str] = []
    fields, _done, parse_errors = _parse_kv_block(text)
    errors.extend(parse_errors)
    required = ("doctor", "ensure_godot", "verify", "drive", "discovery_reads")
    for key in required:
        # receipts use lowercase keys
        pass
    # normalize: accept Title Case from parser
    norm = {k.lower(): v for k, v in fields.items()}
    for key in required:
        if key not in norm or not norm[key]:
            errors.append(f"missing '{key}:'")

    if "doctor" in norm and not RECEIPT_DOCTOR.match(norm["doctor"]):
        errors.append("doctor: must be 'pass' or 'fail'")
    if "ensure_godot" in norm and not RECEIPT_ENSURE.match(norm["ensure_godot"]):
        errors.append("ensure_godot: must be 'pass', 'skip', or 'fail'")
    if "verify" in norm and not RECEIPT_VERIFY.match(norm["verify"]):
        errors.append("verify: must be 'pass once' or 'fail once'")
    if "drive" in norm and not RECEIPT_DRIVE.match(norm["drive"]):
        errors.append(
            "drive: must be 'pass once drives/<name>.gd', "
            "'skip not-player-facing', or 'fail once'"
        )
    if "discovery_reads" in norm:
        raw = norm["discovery_reads"]
        if not raw.isdigit() or int(raw) < 0 or int(raw) > MAX_DISCOVERY:
            errors.append(f"discovery_reads: must be an integer 0..{MAX_DISCOVERY}")

    if brief_text:
        bfields, _, _ = _parse_kv_block(brief_text)
        phase = bfields.get("Phase", "").lower()
        if phase == "ready":
            if norm.get("doctor", "").lower() != "pass":
                errors.append("ready phase requires doctor: pass")
            if norm.get("verify", "").lower() != "pass once":
                errors.append("ready phase requires verify: pass once")
            brief_drive = bfields.get("Drive", "")
            if brief_drive == "not player-facing":
                if norm.get("drive", "").lower() != "skip not-player-facing":
                    errors.append("ready phase with non-player feature requires drive: skip not-player-facing")
            elif brief_drive.startswith("drives/"):
                want = f"pass once {brief_drive}"
                if norm.get("drive", "").lower() != want.lower():
                    errors.append(f"ready phase requires drive: {want}")
    return errors


def check_pr_how(text: str) -> list[str]:
    errors: list[str] = []
    # Strip HTML comments like the PR template.
    body = re.sub(r"<!--.*?-->", "", text or "", flags=re.S)
    how = None
    m = re.search(r"^[ \t]*#{1,6}[ \t]+How it was checked[ \t]*$", body, re.I | re.M)
    if m:
        rest = body[m.end():]
        nxt = re.search(r"^[ \t]*#{1,6}[ \t]+\S", rest, re.M)
        chunk = rest[: nxt.start() if nxt else len(rest)]
        ff = re.search(r"^[ \t]*Feature file[ \t]*:", chunk, re.I | re.M)
        if ff:
            chunk = chunk[: ff.start()]
        how = chunk
    if how is None or not how.strip():
        return ["empty or missing '## How it was checked' section"]
    if not VERIFY_PR_RE.search(how):
        errors.append("How it was checked needs a 'Verify: once' line")
    if not DRIVE_PR_RE.search(how):
        errors.append(
            "How it was checked needs 'Drive: once drives/<name>.gd' "
            "or 'Drive: not player-facing'"
        )
    return errors


def emit_brief() -> str:
    return BRIEF_TEMPLATE


def self_test() -> int:
    failed = 0

    def expect(ok: bool, label: str) -> None:
        nonlocal failed
        if not ok:
            print(f"FAIL {label}")
            failed += 1
        else:
            print(f"ok   {label}")

    good = emit_brief()
    expect(check_brief(good) == [], "template brief passes")

    bad_issue = good.replace("Issue: none", "Issue: please fix walls")
    expect(any("Issue:" in e for e in check_brief(bad_issue)), "rejects free-form Issue")

    huge = good + ("x" * (MAX_BRIEF_CHARS + 1))
    expect(any("cap" in e for e in check_brief(huge)), "rejects oversized brief")

    receipt_ok = """doctor: pass
ensure_godot: skip
verify: pass once
drive: skip not-player-facing
discovery_reads: 3
"""
    expect(check_receipt(receipt_ok, good.replace("Phase: implement", "Phase: ready")) == [], "ready receipt passes")

    receipt_twice = receipt_ok.replace("verify: pass once", "verify: pass twice")
    expect(any("verify:" in e for e in check_receipt(receipt_twice)), "rejects verify twice wording")

    pr_how = """## How it was checked

Verify: once
Drive: not player-facing

Feature file: not player-facing
"""
    expect(check_pr_how(pr_how) == [], "PR how-checked lines pass")
    expect(any("Verify:" in e for e in check_pr_how("## How it was checked\n\nran tests\n")), "PR how requires Verify once")

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        feat_dir = root / ".cursor/skills/verify-flagoria/features"
        drive_dir = root / ".cursor/skills/verify-flagoria/drives"
        feat_dir.mkdir(parents=True)
        drive_dir.mkdir(parents=True)
        (feat_dir / "demo.md").write_text("Drive: drives/demo.gd\n", encoding="utf-8")
        (drive_dir / "demo.gd").write_text("extends Node\n", encoding="utf-8")
        (root / "art").mkdir()
        (root / "art" / "x.png").write_text("x", encoding="utf-8")
        brief = """Issue: #1
Feature: .cursor/skills/verify-flagoria/features/demo.md
Drive: drives/demo.gd
Pinned: art/x.png
Phase: implement
Max discovery reads: 5
Done when:
- demo drive prints VERIFY_DONE ok
"""
        expect(check_brief(brief, root=root) == [], "feature brief with pin passes")
        mismatch = brief.replace("Drive: drives/demo.gd", "Drive: not player-facing")
        expect(any("does not match" in e or "requires Drive" in e for e in check_brief(mismatch, root=root)), "drive must match feature")

    return 1 if failed else 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--self-test", action="store_true")
    sub = p.add_subparsers(dest="cmd")

    sub.add_parser("emit-brief", help="print the brief template")

    cb = sub.add_parser("check-brief", help="validate a brief file")
    cb.add_argument("file")

    cr = sub.add_parser("check-receipt", help="validate a Ready receipt")
    cr.add_argument("file")
    cr.add_argument("--brief", default="")

    cp = sub.add_parser("check-pr-how", help="validate PR How-it-was-checked lines")
    cp.add_argument("file")

    args = p.parse_args(argv)
    if args.self_test:
        return self_test()
    if args.cmd == "emit-brief":
        sys.stdout.write(emit_brief())
        return 0
    if args.cmd == "check-brief":
        text = Path(args.file).read_text(encoding="utf-8")
        errs = check_brief(text)
        for e in errs:
            print(f"agent_budget: {e}", file=sys.stderr)
        return 1 if errs else 0
    if args.cmd == "check-receipt":
        text = Path(args.file).read_text(encoding="utf-8")
        brief = Path(args.brief).read_text(encoding="utf-8") if args.brief else None
        errs = check_receipt(text, brief)
        for e in errs:
            print(f"agent_budget: {e}", file=sys.stderr)
        return 1 if errs else 0
    if args.cmd == "check-pr-how":
        text = Path(args.file).read_text(encoding="utf-8")
        errs = check_pr_how(text)
        for e in errs:
            print(f"agent_budget: {e}", file=sys.stderr)
        return 1 if errs else 0
    p.print_help()
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
