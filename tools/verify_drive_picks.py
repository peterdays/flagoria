#!/usr/bin/env python3
"""Pick gameplay drives for verify-drive.yml (Gameplay drives job).

On pull_request, after tools/play_review_paths.py marks gameplay, read changed
paths and collect Drive: drives/<name>.gd from changed feature files under
.cursor/skills/verify-flagoria/features/*.md (README skipped). Skip
drives/two_player/* and nested drives/<folder>/*.gd. When gameplay is true and
no drive names were collected, use the default smoke drive (same as
workflow_dispatch with empty inputs: smoke).

Writes drives=<space-separated names> and optional reason= to $GITHUB_OUTPUT
when set. Does not set gameplay=; play_review_paths does that on PRs.

  python3 tools/verify_drive_picks.py --files paths.txt --gameplay true
  python3 tools/verify_drive_picks.py --dispatch-drives "wait smoke"

Self-test: python3 tools/verify_drive_picks.py --self-test
"""
from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

DEFAULT_SMOKE = "smoke"
FEATURE_PREFIX = ".cursor/skills/verify-flagoria/features/"
DRIVE_LINE = re.compile(r"^Drive:\s+(\S+)\s*$", re.MULTILINE)


def drive_names_from_feature(path: Path) -> list[str]:
    """Return launch names (no drives/ prefix, no .gd) for one feature file."""
    if not path.is_file():
        return []
    text = path.read_text(encoding="utf-8", errors="replace")
    m = DRIVE_LINE.search(text)
    if not m:
        return []
    value = m.group(1).strip()
    if value == "not player-facing":
        return []
    if not value.startswith("drives/") or not value.endswith(".gd"):
        return []
    if value.startswith("drives/two_player/"):
        return []
    rel = value[len("drives/") : -len(".gd")]
    if "/" in rel:
        return []
    if not rel.replace("_", "").isalnum():
        return []
    return [rel]


def collect_from_paths(paths: list[str], root: Path) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for rel in paths:
        if not rel.startswith(FEATURE_PREFIX) or rel.endswith("/README.md"):
            continue
        if not rel.endswith(".md"):
            continue
        for name in drive_names_from_feature(root / rel):
            if name not in seen:
                seen.add(name)
                out.append(name)
    return out


def dedupe(names: list[str]) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for n in names:
        if not n or n in seen:
            continue
        seen.add(n)
        out.append(n)
    return out


def finalize(gameplay: bool, names: list[str], *, dispatch: bool) -> list[str]:
    names = dedupe(names)
    if dispatch:
        return names if names else [DEFAULT_SMOKE]
    if not gameplay:
        return []
    if names:
        return names
    return [DEFAULT_SMOKE]


def write_output(drives: list[str], reason: str) -> None:
    joined = " ".join(drives)
    print("Selected drives: '%s'" % joined)
    out = os.environ.get("GITHUB_OUTPUT")
    if out:
        with open(out, "a", encoding="utf-8") as fh:
            fh.write("drives=%s\nreason=%s\n" % (joined, reason))


def self_test() -> int:
    root = Path(__file__).resolve().parent.parent
    fail = 0

    def check(label: str, got: list[str], want: list[str]) -> None:
        nonlocal fail
        if got != want:
            fail += 1
            print("FAIL %s: got %r, want %r" % (label, got, want), file=sys.stderr)

    feat = FEATURE_PREFIX
    with_tmp = [
        (feat + "chop-trees.md", "Drive: drives/chop_trees.gd\n"),
        (feat + "combat.md", "Drive: drives/combat_hud.gd\n"),
        (feat + "two-player.md", "Drive: drives/two_player/two_player_host.gd\n"),
        (feat + "nested.md", "Drive: drives/dedicated_play/play_server.gd\n"),
        (feat + "npf.md", "Drive: not player-facing\n"),
        (feat + "nodrive.md", "No drive here\n"),
    ]
    import tempfile

    with tempfile.TemporaryDirectory() as td:
        tmproot = Path(td)
        for rel, body in with_tmp:
            p = tmproot / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(body, encoding="utf-8")

        paths_gameplay_only = ["Scripts/player.gd"]
        check(
            "gameplay no features",
            finalize(True, collect_from_paths(paths_gameplay_only, tmproot), dispatch=False),
            [DEFAULT_SMOKE],
        )
        paths_chop = [feat + "chop-trees.md", "Scripts/player.gd"]
        check(
            "feature drive",
            finalize(True, collect_from_paths(paths_chop, tmproot), dispatch=False),
            ["chop_trees"],
        )
        paths_two = [feat + "two-player.md"]
        check(
            "skip two_player",
            finalize(True, collect_from_paths(paths_two, tmproot), dispatch=False),
            [DEFAULT_SMOKE],
        )
        paths_nested = [feat + "nested.md"]
        check(
            "skip nested",
            finalize(True, collect_from_paths(paths_nested, tmproot), dispatch=False),
            [DEFAULT_SMOKE],
        )
        paths_npf = [feat + "npf.md", "Scripts/mob.gd"]
        check(
            "not player-facing feature",
            finalize(True, collect_from_paths(paths_npf, tmproot), dispatch=False),
            [DEFAULT_SMOKE],
        )
        paths_both = [feat + "chop-trees.md", feat + "combat.md"]
        check(
            "two features",
            finalize(True, collect_from_paths(paths_both, tmproot), dispatch=False),
            ["chop_trees", "combat_hud"],
        )
        paths_dup = [feat + "chop-trees.md", feat + "chop-trees.md"]
        check(
            "dedupe",
            finalize(True, collect_from_paths(paths_dup, tmproot), dispatch=False),
            ["chop_trees"],
        )

    check("non-gameplay", finalize(False, [], dispatch=False), [])
    check("dispatch empty", finalize(True, [], dispatch=True), [DEFAULT_SMOKE])
    check("dispatch named", finalize(True, ["wait", "smoke", "wait"], dispatch=True), ["wait", "smoke"])

    # Real repo: default smoke drive file exists
    smoke = root / ".cursor/skills/verify-flagoria/drives/smoke.gd"
    if not smoke.is_file():
        fail += 1
        print("FAIL smoke.gd missing", file=sys.stderr)

    cases = 10
    print("verify_drive_picks self-test: %d/%d ok" % (cases - fail, cases))
    return 1 if fail else 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--files", help="changed paths, one per line (default: stdin)")
    ap.add_argument("--gameplay", choices=["true", "false"], help="pull_request gameplay flag")
    ap.add_argument(
        "--dispatch-drives",
        help="workflow_dispatch drive names (space-separated; empty uses default smoke)",
    )
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()
    if args.self_test:
        return self_test()

    root = Path(__file__).resolve().parent.parent
    if args.dispatch_drives is not None:
        raw = [p for p in args.dispatch_drives.split() if p]
        drives = finalize(True, raw, dispatch=True)
        write_output(drives, "workflow_dispatch")
        return 0

    text = ""
    if args.files:
        text = Path(args.files).read_text(encoding="utf-8", errors="replace")
    else:
        text = sys.stdin.read()
    paths = [p.strip() for p in text.splitlines() if p.strip()]
    gameplay = args.gameplay == "true"
    collected = collect_from_paths(paths, root)
    drives = finalize(gameplay, collected, dispatch=False)
    reason = "gameplay PR" if gameplay else "not gameplay"
    if gameplay and not collected:
        reason = "gameplay PR (default %s)" % DEFAULT_SMOKE
    write_output(drives, reason)
    return 0


if __name__ == "__main__":
    sys.exit(main())
