#!/usr/bin/env python3
"""Run every multiplayer test scenario N times headless and print a table.

A multiplayer scenario is a `_test_*` function in tests/run_tests.gd that opens
an ENet peer or starts another Godot process, directly or through a helper in
the same file. Each run is `run_tests.gd -- --only=<name>` in a fresh Godot
process with its own XDG dirs. Runs go JOBS at a time (default 4); each
parallel slot gets its own block of UDP ports through FLAGORIA_TEST_PORTS, so
two runs never pick the same port. A run passes when it exits 0, prints
"All tests passed." and logs no script error. The process group of each run
is killed afterwards, so servers a test started cannot outlive it.

A scenario in KNOWN_FLAKY gets one retry after a failed run; the run counts
as failed only if the retry fails too. The table still reports first-attempt
failures in its "retried" column.

Usage:
  python3 tools/stress_netcode.py                  # N=20
  python3 tools/stress_netcode.py -n 3 --only=mob_chase_two_players
  python3 tools/stress_netcode.py -j 1             # one run at a time
  python3 tools/stress_netcode.py --list
  GODOT=/path/to/godot python3 tools/stress_netcode.py

Exit 1 if any run failed (after its retry, if it had one). Failed run logs go to artifacts/out/stress/.
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
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TESTS = ROOT / "tests" / "run_tests.gd"
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


def net_scenarios(source: str) -> list[str]:
    """Test names (without the leading underscore), in source order."""
    starts = list(FUNC_RE.finditer(source))
    bodies = {}
    for i, m in enumerate(starts):
        end = starts[i + 1].start() if i + 1 < len(starts) else len(source)
        bodies[m.group(1)] = source[m.end():end]
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


def run_once(godot: str, name: str, timeout: float, ports: str) -> tuple[bool, float, str]:
    with tempfile.TemporaryDirectory(prefix="stress-") as tmp:
        env = dict(os.environ, FLAGORIA_TEST_PORTS=ports)
        for var in ("XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME"):
            env[var] = os.path.join(tmp, var.lower())
        cmd = [godot, "--headless", "--path", str(ROOT), "--script",
               "res://tests/run_tests.gd", "--", "--only=" + name]
        start = time.monotonic()
        proc = subprocess.Popen(cmd, env=env, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True, start_new_session=True)
        try:
            out, _ = proc.communicate(timeout=timeout)
            timed_out = False
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            out, _ = proc.communicate()
            out = "TIMEOUT after %.0f s\n%s" % (timeout, out)
            timed_out = True
        elapsed = time.monotonic() - start
        try:  # servers and peers the test started share the group
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    ok = (not timed_out and proc.returncode == 0 and "All tests passed." in out
          and not ERROR_RE.search(out))
    return ok, elapsed, out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("-n", "--runs", type=int, default=int(os.environ.get("STRESS_RUNS", 20)))
    ap.add_argument("--only", default="", help="comma-separated scenario names")
    ap.add_argument("--timeout", type=float, default=300.0, help="seconds per run")
    ap.add_argument("-j", "--jobs", type=int, default=int(os.environ.get("STRESS_JOBS", 4)),
                    help="runs at a time")
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()

    names = net_scenarios(TESTS.read_text())
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
    print("Godot %s, %d runs x %d scenarios, %d at a time"
          % (version, args.runs, len(names), args.jobs), flush=True)
    with tempfile.TemporaryDirectory(prefix="stress-import-") as tmp:
        env = dict(os.environ, XDG_CONFIG_HOME=tmp + "/c", XDG_DATA_HOME=tmp + "/d", XDG_CACHE_HOME=tmp + "/k")
        subprocess.run([godot, "--headless", "--path", str(ROOT), "--import"], env=env,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=600)

    slots: queue.Queue[int] = queue.Queue()
    for slot in range(args.jobs):
        slots.put(slot)

    def one_run(name: str, i: int) -> tuple[bool, int, float]:
        """Run i of a scenario, with its retry; returns (passed, retried, worst)."""
        slot = slots.get()
        try:
            ports = port_block(slot, args.jobs)
            attempts = 2 if name in KNOWN_FLAKY else 1
            retried, worst = 0, 0.0
            for attempt in range(attempts):
                ok, elapsed, out = run_once(godot, name, args.timeout, ports)
                worst = max(worst, elapsed)
                if ok:
                    return True, retried, worst
                LOG_DIR.mkdir(parents=True, exist_ok=True)
                suffix = "_retry" if attempt else ""
                (LOG_DIR / ("%s_run%02d%s.log" % (name, i + 1, suffix))).write_text(out)
                if attempt + 1 < attempts:
                    retried += 1
                    print("  %s run %d failed, retrying once (known flaky, %s)"
                          % (name, i + 1, KNOWN_FLAKY[name]), flush=True)
            return False, retried, worst
        finally:
            slots.put(slot)

    rows = []
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = {name: [pool.submit(one_run, name, i) for i in range(args.runs)] for name in names}
        for name in names:  # source order; later scenarios keep running meanwhile
            results = [f.result() for f in futures[name]]
            passed = sum(1 for r in results if r[0])
            retried = sum(r[1] for r in results)
            worst = max(r[2] for r in results)
            rows.append((name, passed, args.runs, retried, worst))
            print("  %s: %d/%d, %d retried, worst %.1f s" % (name, passed, args.runs, retried, worst),
                  flush=True)

    label = {r[0]: r[0] + (" (%s)" % KNOWN_FLAKY[r[0]] if r[0] in KNOWN_FLAKY else "") for r in rows}
    width = max(len("scenario"), *(len(v) for v in label.values()))
    table = ["| %s |  pass | rate | retried | worst s |" % "scenario".ljust(width),
             "|%s|-------|------|---------|---------|" % ("-" * (width + 2))]
    for name, passed, runs, retried, worst in rows:
        table.append("| %s | %5s | %3.0f%% | %7s | %7.1f |" % (
            label[name].ljust(width), "%d/%d" % (passed, runs), 100.0 * passed / runs,
            "%d" % retried if name in KNOWN_FLAKY else "-", worst))
    print("\n".join(table))
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as fh:
            fh.write("### Netcode stress, %d runs each, %d at a time\n\n%s\n\nA scenario with an issue number "
                     "gets one retry per failed run until that issue is fixed; \"retried\" counts "
                     "its first-attempt failures.\n" % (args.runs, args.jobs, "\n".join(table)))
    return 0 if all(r[1] == r[2] for r in rows) else 1


if __name__ == "__main__":
    sys.exit(main())
