#!/usr/bin/env python3
"""Run every multiplayer test scenario N times headless and print a table.

A multiplayer scenario is a `_test_*` function in tests/run_tests.gd or a
tests/**/test_*.gd file that opens an ENet peer or starts another Godot
process, directly or through a helper (tests/helpers/test_helpers.gd, or any
other function in those files). Each run is `run_tests.gd -- --only=<name>` in a fresh Godot
process with its own XDG dirs. Runs go JOBS at a time (default 4); each
parallel slot gets its own block of UDP ports through FLAGORIA_TEST_PORTS, so
two runs never pick the same port. A run passes when it exits 0, prints
"All tests passed." and logs no script error. The process group of each run
is killed afterwards, so servers a test started cannot outlive it.

A scenario in KNOWN_FLAKY gets one retry after a failed run; the run counts
as failed only if the retry fails too. The table still reports first-attempt
failures in its "retried" column.

The first run that fails (after that retry, when there is one) stops the job.
Remaining runs of that scenario are not started, in-flight runs are killed,
and later scenarios are not started. The table covers the runs that finished.
Each run is killed after --timeout seconds (default 60) so one hang cannot
hold the job. Passing runs on a full matrix have stayed under 20 s.

Usage:
  python3 tools/stress_netcode.py                  # N=20
  python3 tools/stress_netcode.py -n 3 --only=mob_chase_two_players
  python3 tools/stress_netcode.py -j 1             # one run at a time
  python3 tools/stress_netcode.py --list
  python3 tools/stress_netcode.py --self-test
  GODOT=/path/to/godot python3 tools/stress_netcode.py

Exit 1 if any finished run failed (after its retry, if it had one). Failed run logs go to artifacts/out/stress/.
"""
from __future__ import annotations

import argparse
import os
import queue
import re
import signal
import subprocess
import sys
import tempfile
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TESTS = ROOT / "tests"
RUNNER = TESTS / "run_tests.gd"
LOG_DIR = ROOT / "artifacts" / "out" / "stress"
NET_MARKERS = ("ENetMultiplayerPeer", "OS.create_process(")
ERROR_RE = re.compile(r"SCRIPT ERROR:|Parse [Ee]rror|Failed to load script|Failed loading resource")
FUNC_RE = re.compile(r"^func (\w+)\(", re.M)
# Split into one block per parallel slot. Below 32768, the start of the Linux
# ephemeral range, so a client socket the kernel binds can't land in a block.
PORT_LO, PORT_HI = 20000, 32767
# Scenarios that may fail once per run for a known reason. Remove an entry when
# its issue is fixed.
KNOWN_FLAKY: dict[str, str] = {}  # e.g. {"test_name": "#123"}


def test_sources() -> list[str]:
    """The runner, then every tests/**/test_*.gd file, in the runner's order
    (sorted by path). The shared helpers file matches the pattern too."""
    paths = sorted(set(TESTS.rglob("test_*.gd")) | {RUNNER},
                   key=lambda p: p.relative_to(TESTS).as_posix())
    return [p.read_text() for p in paths]


def net_scenarios(sources: list[str]) -> list[str]:
    """Test names (without the leading underscore), in run order."""
    bodies: dict[str, str] = {}
    for source in sources:
        starts = list(FUNC_RE.finditer(source))
        for i, m in enumerate(starts):
            end = starts[i + 1].start() if i + 1 < len(starts) else len(source)
            # A runner forwarder and the helper it calls share a name.
            bodies[m.group(1)] = bodies.get(m.group(1), "") + source[m.end():end]
    net = {name for name, body in bodies.items() if any(k in body for k in NET_MARKERS)}
    changed = True
    while changed:  # a function that calls a net helper is net too
        changed = False
        for name, body in bodies.items():
            if name not in net and any(re.search(r"\b%s\(" % h, body) for h in net):
                net.add(name)
                changed = True
    return [n[1:] for n in bodies if n.startswith("_test_") and n in net]


def port_block(slot: int, jobs: int) -> str:
    """The "LO-HI" UDP port range of one parallel slot."""
    size = (PORT_HI - PORT_LO + 1) // jobs
    lo = PORT_LO + slot * size
    return "%d-%d" % (lo, lo + size - 1)


# One hung run must not sit for minutes. Full-matrix passes on main have
# stayed under 20 s; 60 s is the per-run budget above that.
DEFAULT_TIMEOUT = 60.0


def run_command(cmd: list[str], timeout: float, stop: threading.Event,
                env: dict | None = None) -> tuple[str, float, str]:
    """Run cmd. Returns (kind, seconds, output). kind is pass, fail, timeout, or abort.

    pass/fail are the process's own result. timeout means it was killed at
    `timeout`. abort means `stop` was set and the process was killed.
    """
    start = time.monotonic()
    proc = subprocess.Popen(cmd, env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, start_new_session=True)
    out = ""
    reason = ""
    try:
        while True:
            try:
                out, _ = proc.communicate(timeout=0.2)
                break
            except subprocess.TimeoutExpired:
                if stop.is_set():
                    reason = "abort"
                    break
                if time.monotonic() - start >= timeout:
                    reason = "timeout"
                    break
        if reason:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            drained, _ = proc.communicate()
            body = drained or ""
            elapsed = time.monotonic() - start
            if reason == "abort":
                return "abort", elapsed, "ABORTED\n" + body
            return "timeout", elapsed, "TIMEOUT after %.0f s\n%s" % (timeout, body)
    finally:
        try:  # servers and peers the test started share the group
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    elapsed = time.monotonic() - start
    ok = (proc.returncode == 0 and "All tests passed." in (out or "")
          and not ERROR_RE.search(out or ""))
    return ("pass" if ok else "fail"), elapsed, out or ""


def run_once(godot: str, name: str, timeout: float, ports: str,
             stop: threading.Event) -> tuple[str, float, str]:
    with tempfile.TemporaryDirectory(prefix="stress-") as tmp:
        env = dict(os.environ, FLAGORIA_TEST_PORTS=ports)
        for var in ("XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME"):
            env[var] = os.path.join(tmp, var.lower())
        cmd = [godot, "--headless", "--path", str(ROOT), "--script",
               "res://tests/run_tests.gd", "--", "--only=" + name]
        return run_command(cmd, timeout, stop, env)


def run_plan(names: list[str], runs: int, jobs: int, timeout: float, invoke, known_flaky: dict,
             announce, on_bad=None) -> tuple[list, str]:
    """Run scenarios in order, `jobs` at a time.

    invoke(name, index, timeout, ports, stop) -> (kind, elapsed, output).
    Stops at the first run whose final attempt fails or times out. Returns
    (rows, failure message). A row is
    (name, passed, finished, planned, retried, worst, stopped_early).
    """
    stop = threading.Event()
    failure = [""]
    fail_lock = threading.Lock()
    slots: queue.Queue[int] = queue.Queue()
    for slot in range(jobs):
        slots.put(slot)

    def claim(msg: str) -> bool:
        with fail_lock:
            if failure[0]:
                return False
            failure[0] = msg
            stop.set()
            return True

    def one_run(name: str, i: int) -> tuple[str, int, float]:
        """(status, retried, worst). status is pass, fail, or skip."""
        if stop.is_set():
            return "skip", 0, 0.0
        slot = slots.get()
        try:
            if stop.is_set():
                return "skip", 0, 0.0
            ports = port_block(slot, jobs)
            attempts = 2 if name in known_flaky else 1
            retried, worst = 0, 0.0
            for attempt in range(attempts):
                if stop.is_set():
                    return "skip", retried, worst
                kind, elapsed, out = invoke(name, i, timeout, ports, stop)
                worst = max(worst, elapsed)
                if kind == "abort":
                    return "skip", retried, worst
                if kind == "pass":
                    return "pass", retried, worst
                if on_bad:
                    on_bad(name, i, attempt, out)
                if attempt + 1 < attempts:
                    retried += 1
                    announce("  %s run %d failed, retrying once (known flaky, %s)"
                             % (name, i + 1, known_flaky[name]))
                    continue
                verb = "timed out after" if kind == "timeout" else "failed in"
                msg = "FAIL %s run %d %s %.1f s; stopping the stress job" % (name, i + 1, verb, elapsed)
                if claim(msg):
                    announce(msg)
                return "fail", retried, worst
            return "fail", retried, worst
        finally:
            slots.put(slot)

    rows = []
    with ThreadPoolExecutor(max_workers=jobs) as pool:
        for name in names:
            if stop.is_set():
                break
            futures = [pool.submit(one_run, name, i) for i in range(runs)]
            results = [f.result() for f in futures]
            finished = [r for r in results if r[0] != "skip"]
            if not finished:
                break
            passed = sum(1 for r in finished if r[0] == "pass")
            retried = sum(r[1] for r in finished)
            worst = max(r[2] for r in finished)
            stopped_early = len(finished) < runs
            rows.append((name, passed, len(finished), runs, retried, worst, stopped_early))
            note = " (stopped)" if stopped_early else ""
            announce("  %s: %d/%d, %d retried, worst %.1f s%s"
                     % (name, passed, len(finished), retried, worst, note))
            if stop.is_set():
                break
    return rows, failure[0]


def format_table(rows: list, known_flaky: dict) -> list[str]:
    def shown(row) -> str:
        name = row[0]
        label = name + (" (%s)" % known_flaky[name] if name in known_flaky else "")
        if row[6]:
            label += " (stopped)"
        return label

    labels = [shown(r) for r in rows] or ["scenario"]
    width = max(len("scenario"), *(len(v) for v in labels))
    table = ["| %s |  pass | rate | retried | worst s |" % "scenario".ljust(width),
             "|%s|-------|------|---------|---------|" % ("-" * (width + 2))]
    for row, label in zip(rows, labels):
        name, passed, finished, _planned, retried, worst, _stopped = row
        rate = 100.0 * passed / finished if finished else 0.0
        table.append("| %s | %5s | %3.0f%% | %7s | %7.1f |" % (
            label.ljust(width), "%d/%d" % (passed, finished), rate,
            "%d" % retried if name in known_flaky else "-", worst))
    return table


def self_test() -> int:
    """Fail-fast scheduling and the per-run timeout. No Godot."""
    fail = 0

    def check(cond: bool, detail: str) -> None:
        nonlocal fail
        if not cond:
            fail += 1
            print("FAIL " + detail, file=sys.stderr)

    calls: list[tuple[str, int]] = []

    def invoke(name, index, _timeout, _ports, stop):
        calls.append((name, index))
        if name == "b" and index == 0:
            return "fail", 1.5, "bad"
        if name == "b" and index == 1:
            while not stop.is_set():
                time.sleep(0.01)
            return "abort", 0.2, ""
        if name == "c":
            return "fail", 9.0, "should not run"
        return "pass", 0.05, "All tests passed."

    rows, msg = run_plan(["a", "b", "c"], 4, 2, 5, invoke, {}, lambda _line: None)
    check(msg.startswith("FAIL b run 1 failed in 1.5 s;"), "fail-fast message: %r" % msg)
    check(all(name != "c" for name, _i in calls), "later scenario ran: %s" % calls)
    check(not any(name == "b" and index > 1 for name, index in calls),
          "later runs of the failed scenario started: %s" % calls)
    check(len(rows) == 2 and rows[1][0] == "b" and rows[1][1] < rows[1][2],
          "table did not record the failed scenario: %s" % rows)

    retries: list[int] = []

    def flaky(_name, index, _timeout, _ports, _stop):
        retries.append(index)
        if len(retries) == 1:
            return "fail", 0.2, "once"
        return "pass", 0.1, "All tests passed."

    rows, msg = run_plan(["k"], 1, 1, 5, flaky, {"k": "#1"}, lambda _line: None)
    check(msg == "" and rows[0][1] == 1 and rows[0][4] == 1, "known-flaky retry: %s %r" % (rows, msg))

    kind, elapsed, out = run_command(["sleep", "30"], 0.4, threading.Event())
    check(kind == "timeout" and elapsed < 2 and out.startswith("TIMEOUT"),
          "per-run timeout: %s %.2f %r" % (kind, elapsed, out[:40]))

    stop = threading.Event()

    def trip() -> None:
        time.sleep(0.25)
        stop.set()

    threading.Thread(target=trip, daemon=True).start()
    kind, elapsed, out = run_command(["sleep", "30"], 10, stop)
    check(kind == "abort" and elapsed < 2 and out.startswith("ABORTED"),
          "abort on stop: %s %.2f" % (kind, elapsed))

    print("stress_netcode self-test: %s" % ("ok" if fail == 0 else "%d failed" % fail))
    return 1 if fail else 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("-n", "--runs", type=int, default=int(os.environ.get("STRESS_RUNS", 20)))
    ap.add_argument("--only", default="", help="comma-separated scenario names")
    ap.add_argument("--timeout", type=float, default=float(os.environ.get("STRESS_TIMEOUT", DEFAULT_TIMEOUT)),
                    help="seconds per run before it is killed (default %s)" % DEFAULT_TIMEOUT)
    ap.add_argument("-j", "--jobs", type=int, default=int(os.environ.get("STRESS_JOBS", 4)),
                    help="runs at a time")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()
    if args.self_test:
        return self_test()

    names = net_scenarios(test_sources())
    if args.only:
        wanted = ["test_" + w.strip().removeprefix("test_") for w in args.only.split(",") if w.strip()]
        unknown = [w for w in wanted if w not in names]
        if unknown:
            print("Not a multiplayer scenario: %s. Known: %s" % (", ".join(unknown), ", ".join(names)),
                  file=sys.stderr)
            return 1
        names = [n for n in names if n in wanted]
    if args.list:
        print("\n".join(names))
        return 0
    if args.runs < 1 or args.jobs < 1:
        print("-n and -j must be at least 1", file=sys.stderr)
        return 1

    godot = os.environ.get("GODOT", "godot")
    version = subprocess.run([godot, "--version"], capture_output=True, text=True).stdout.strip()
    print("Godot %s, %d runs x %d scenarios, %d at a time, %.0f s per run"
          % (version, args.runs, len(names), args.jobs, args.timeout), flush=True)
    with tempfile.TemporaryDirectory(prefix="stress-import-") as tmp:
        env = dict(os.environ, XDG_CONFIG_HOME=tmp + "/c", XDG_DATA_HOME=tmp + "/d", XDG_CACHE_HOME=tmp + "/k")
        subprocess.run([godot, "--headless", "--path", str(ROOT), "--import"], env=env,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=600)

    def announce(line: str) -> None:
        print(line, flush=True)

    def on_bad(name: str, index: int, attempt: int, out: str) -> None:
        LOG_DIR.mkdir(parents=True, exist_ok=True)
        suffix = "_retry" if attempt else ""
        (LOG_DIR / ("%s_run%02d%s.log" % (name, index + 1, suffix))).write_text(out)

    def invoke(name: str, index: int, timeout: float, ports: str, stop: threading.Event):
        return run_once(godot, name, timeout, ports, stop)

    rows, failure = run_plan(names, args.runs, args.jobs, args.timeout, invoke, KNOWN_FLAKY,
                             announce, on_bad)
    started = {row[0] for row in rows}
    skipped = [name for name in names if name not in started]
    if skipped:
        announce("Not started (%d): %s" % (len(skipped), ", ".join(skipped)))
    table = format_table(rows, KNOWN_FLAKY)
    print("\n".join(table))
    if failure and os.environ.get("GITHUB_ACTIONS"):
        print("::error::%s" % failure, flush=True)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as fh:
            note = failure + "\n\n" if failure else ""
            fh.write("### Netcode stress, %d runs each, %d at a time\n\n%s%s\n\nThe first failed run stops "
                     "the job. A scenario with an issue number gets one retry per failed run until that "
                     "issue is fixed; \"retried\" counts its first-attempt failures. Each run is killed "
                     "after %.0f s.\n" % (args.runs, args.jobs, note, "\n".join(table), args.timeout))
    if failure:
        return 1
    return 0 if all(row[1] == row[2] == row[3] for row in rows) else 1


if __name__ == "__main__":
    sys.exit(main())
