#!/usr/bin/env python3
"""Job times for one workflow run, compared with recent successful runs.

Runs as the last job of a workflow (see .github/workflows/job-times.yml) and
writes a table to the job summary: how long each job of this run took, the
median of the same job in recent successful runs of the same workflow, and
the change. The baseline comes from runs on main; workflows that only run on
pull requests fall back to recent successful runs from other branches.

Only runs that executed the same steps are compared, so a run whose gate
skipped the heavy steps is not measured against full runs (and the other way
round). When no such run exists, all recent runs of the job are used.

Time is reported and weighed, never capped: a job over WARN_MINUTES gets a
warning annotation, and this script always exits 0, also when the API is
unreachable (the summary then says the baseline is unavailable).

Reads the API through the gh CLI, with GH_TOKEN (actions: read) in CI.
Locally, with gh signed in:
  python3 tools/ci_job_times.py --repo OWNER/REPO --run-id RUN_ID
prints the summary to stdout (no job summary file outside CI).
"""
from __future__ import annotations

import argparse
import json
import os
import statistics
import sys
import subprocess
from datetime import datetime

WARN_MINUTES = 5.0  # soft threshold per job; a warning, never a failure
BASELINE_RUNS = 8  # recent successful runs to take the median from
SELF_JOB = "Job times"  # this job's name; left out of its own table


def api(path: str, token: str = "") -> dict:
    """GET one REST path through the gh CLI (preinstalled on GitHub runners)."""
    env = dict(os.environ, GH_TOKEN=token) if token else None
    out = subprocess.run(["gh", "api", path], capture_output=True, text=True,
                         timeout=30, env=env, check=False)
    if out.returncode != 0:
        raise RuntimeError(f"gh api {path.split('?')[0]}: {out.stderr.strip() or out.returncode}")
    return json.loads(out.stdout)


def seconds(start: str | None, end: str | None) -> float | None:
    if not start or not end:
        return None
    t0 = datetime.fromisoformat(start.replace("Z", "+00:00"))
    t1 = datetime.fromisoformat(end.replace("Z", "+00:00"))
    return max(0.0, (t1 - t0).total_seconds())


def job_name(name: str) -> str:
    # A job called from a reusable workflow is named "caller / callee".
    return name.split(" / ")[-1]


def steps_run(job: dict) -> tuple:
    """Numbers of the steps that ran, to match like with like."""
    return tuple(s["number"] for s in job.get("steps", [])
                 if s.get("conclusion") not in ("skipped", None))


def run_jobs(repo: str, run_id: int, token: str) -> list[dict]:
    jobs = api(f"repos/{repo}/actions/runs/{run_id}/jobs?per_page=100", token)["jobs"]
    return [j for j in jobs if job_name(j["name"]) != SELF_JOB]


def baseline(repo: str, run: dict, names: set[str], token: str) -> tuple[str, dict]:
    """Return (source label, {job name: [(seconds, steps_run), ...]})."""
    wf = run["workflow_id"]
    base = f"repos/{repo}/actions/workflows/{wf}/runs?status=success&per_page=30"
    candidates = [r for r in api(base + "&branch=main", token)["workflow_runs"]
                  if r["id"] != run["id"]]
    label = "main"
    if not candidates:
        candidates = [r for r in api(base, token)["workflow_runs"]
                      if r["id"] != run["id"] and r["head_branch"] != run["head_branch"]]
        label = "other branches (this workflow does not run on main)"
    samples: dict[str, list] = {n: [] for n in names}
    for r in candidates[:BASELINE_RUNS]:
        for j in run_jobs(repo, r["id"], token):
            n = job_name(j["name"])
            d = seconds(j.get("started_at"), j.get("completed_at"))
            if n in samples and d is not None and j.get("conclusion") == "success":
                samples[n].append((d, steps_run(j)))
    used = min(len(candidates), BASELINE_RUNS)
    return f"median of the last {used} successful runs on {label}", samples


def fmt(sec: float | None) -> str:
    if sec is None:
        return "–"
    m, s = divmod(int(round(sec)), 60)
    return f"{m}m {s:02d}s" if m else f"{s}s"


def delta(cur: float, ref: float) -> str:
    diff = cur - ref
    sign = "+" if diff >= 0 else "−"
    pct = f" ({sign}{abs(diff) / ref:.0%})" if ref > 0 else ""
    return f"{sign}{fmt(abs(diff))}{pct}"


def summarize(repo: str, run_id: int, token: str) -> tuple[str, list[str]]:
    run = api(f"repos/{repo}/actions/runs/{run_id}", token)
    jobs = run_jobs(repo, run_id, token)
    names = {job_name(j["name"]) for j in jobs}
    try:
        source, samples = baseline(repo, run, names, token)
    except Exception as exc:  # noqa: BLE001 - the report must not fail
        source, samples = f"unavailable ({type(exc).__name__}: {exc})", {}
    lines = [
        f"### Job times: {run['name']}",
        "",
        "| Job | Result | This run | Baseline | Change |",
        "|---|---|---|---|---|",
    ]
    warnings = []
    for j in jobs:
        n = job_name(j["name"])
        cur = seconds(j.get("started_at"), j.get("completed_at"))
        pool = samples.get(n, [])
        same = [d for d, st in pool if st == steps_run(j)]
        values, note = (same, "") if same else ([d for d, _ in pool], " (steps differ)" if pool else "")
        ref = statistics.median(values) if values else None
        change = delta(cur, ref) if cur is not None and ref is not None else "–"
        ref_text = f"{fmt(ref)}{note}" if ref is not None else "–"
        lines.append(f"| {n} | {j.get('conclusion') or j.get('status')} | {fmt(cur)} | {ref_text} | {change} |")
        if cur is not None and cur > WARN_MINUTES * 60:
            warnings.append(f"{n} took {fmt(cur)}, over the {WARN_MINUTES:g} min guide. "
                            "Costly checks are allowed; say why the time is worth it in the PR.")
    lines += ["", f"Baseline: {source}. Same-steps runs only where available.",
              f"Jobs over {WARN_MINUTES:g} min get a warning; time never fails a check."]
    return "\n".join(lines) + "\n", warnings


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY"))
    p.add_argument("--run-id", type=int, default=int(os.environ.get("GITHUB_RUN_ID") or 0))
    args = p.parse_args()
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN") or ""  # "" = gh login
    out = os.environ.get("GITHUB_STEP_SUMMARY")
    try:
        text, warnings = summarize(args.repo, args.run_id, token)
    except Exception as exc:  # noqa: BLE001 - the report must not fail
        text = f"### Job times\n\nJob times unavailable: {type(exc).__name__}: {exc}\n"
        warnings = []
        print(f"::warning::Job times unavailable: {exc}")
    for w in warnings:
        print(f"::warning::{w}")
    if out:
        with open(out, "a", encoding="utf-8") as f:
            f.write(text)
    print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
