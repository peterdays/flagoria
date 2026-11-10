#!/usr/bin/env python3
"""Compare required CI check display names to workflow job names.

The committed list in .github/required-checks.txt is the enforcement source.
Branch protection must be updated manually when a required job is renamed.

Usage:
  python3 tools/required_checks.py
  python3 tools/required_checks.py --self-test

Self-test: python3 tools/required_checks_test.py
"""
from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LIST_FILE = ROOT / ".github" / "required-checks.txt"
WORKFLOWS = ROOT / ".github" / "workflows"

_LINE = re.compile(r"^(\S+)\s+(\S+)\s+(.+?)\s*$")


@dataclass(frozen=True)
class RequiredJob:
    workflow: str
    job_id: str
    display_name: str


def parse_list(path: Path) -> list[RequiredJob]:
    jobs: list[RequiredJob] = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        match = _LINE.match(line)
        if not match:
            raise ValueError(f"required checks: bad line in {path.name}: {raw!r}")
        workflow, job_id, display_name = match.groups()
        jobs.append(RequiredJob(workflow, job_id, display_name))
    if not jobs:
        raise ValueError(f"required checks: {path.name} has no entries")
    return jobs


def job_display_name(workflow_path: Path, job_id: str) -> str | None:
    text = workflow_path.read_text(encoding="utf-8")
    in_jobs = False
    in_job = False
    for line in text.splitlines():
        if line.strip() == "jobs:":
            in_jobs = True
            continue
        if not in_jobs:
            continue
        if re.match(r"^  [^\s#].*:$", line) and not line.startswith("    "):
            key = line.strip().rstrip(":")
            in_job = key == job_id
            continue
        if in_job and line.startswith("    name:"):
            return line.split(":", 1)[1].strip()
        if in_job and re.match(r"^  [^\s#].*:$", line) and not line.startswith("    "):
            in_job = False
    return None


def check_tree(root: Path = ROOT) -> list[str]:
    list_path = root / ".github" / "required-checks.txt"
    workflows = root / ".github" / "workflows"
    errors: list[str] = []
    try:
        expected = parse_list(list_path)
    except (OSError, ValueError) as exc:
        return [str(exc)]
    for job in expected:
        workflow_path = workflows / job.workflow
        if not workflow_path.is_file():
            errors.append(
                f"required checks: missing workflow {job.workflow} for job {job.job_id!r}"
            )
            continue
        actual = job_display_name(workflow_path, job.job_id)
        if actual is None:
            errors.append(
                f"required checks: job {job.job_id!r} in {job.workflow} has no name:"
            )
            continue
        if actual != job.display_name:
            errors.append(
                "required checks: display name mismatch for "
                f"{job.workflow} job {job.job_id!r}\n"
                f"  committed list: {job.display_name!r}\n"
                f"  workflow YAML:  {actual!r}"
            )
    return errors


def self_test() -> int:
    from required_checks_test import run as run_tests  # noqa: WPS433

    return run_tests()


def main(argv: list[str]) -> int:
    if argv and argv[0] == "--self-test":
        return self_test()
    errors = check_tree()
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1
    print("required checks: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
