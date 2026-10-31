#!/usr/bin/env python3
"""Does a change touch gameplay? Decides the `needs-play-review` label.

Gameplay means player, mobs, scenes, HUD and menus, touch input, netcode,
map generation parameters, and the input map in project.godot. A
project.godot change counts only when its [input] section differs; with no
before/after copies given, any project.godot change counts.

Also picks the netcode stress tier (runs per scenario): 20 on a push to main
or when netcode changes (see NETCODE and NETCODE_MIXED), 5 for other gameplay
changes. Without --diff, any NETCODE_MIXED file counts as netcode.

Reads changed paths, one per line, from --files (or stdin). Prints the
matching paths and the tier, and writes `gameplay=true|false` and
`stress_runs=N` to $GITHUB_OUTPUT when set.
It only reads its inputs and never runs project code, so the label workflow
can run it from the base branch on any pull request.

  git diff --name-only origin/main...HEAD | python3 tools/play_review_paths.py \
      --base-project <(git show origin/main:project.godot) --head-project project.godot
Self-test: python3 tools/play_review_paths.py --self-test
"""
from __future__ import annotations

import argparse
import fnmatch
import os
import re
import sys

# fnmatch's "*" also matches "/", so "Player/*" covers the whole folder.
GAMEPLAY = [
    "Player/*", "Mobs/*", "*.tscn",
    "flagoria_main.gd",  # host, join, spawn and sync
    "TouchScreenButton.gd", "addons/virtual_joystick/*",  # touch input
    "Scripts/player.gd", "Scripts/player_health.gd",
    "Scripts/mob.gd", "Scripts/mob_spawner.gd", "Scripts/mob_catalog.gd",
    "Scripts/TileMap.gd",  # chunk loading, collision, ground sync
    "Scripts/map_gen.gd",  # session map parameters applied to the world map
    "Scripts/MapGenParams.gd",  # map generation defaults and value ranges
    "Scripts/map_save.gd",  # saved worlds: which parameters a world loads with
    "Scripts/hearts_hud.gd", "Scripts/map_zoom.gd",
    "Scripts/MainMenu.gd", "Scripts/MapAdminPanel.gd",
]

# Netcode files: spawners, RPC-only scripts, the multiplayer test probes and
# the stress runner. Any change to them gets the full stress tier.
NETCODE = [
    "Scripts/mob_spawner.gd", "Scripts/points.gd", "Scripts/discovery_points.gd",
    "tilemap_dynamic.tscn", "tests/late_join_probe.gd", "tests/ingame_menu_probe.gd",
    "tools/stress_netcode.py",
]
# Files that mix netcode with other gameplay. They get the full tier only when
# a changed line names netcode (RPCs, peers, authority, synchronizers).
NETCODE_MIXED = [
    "flagoria_main.gd", "flagoria_main.tscn",
    "Player/character_body_2d.tscn", "Mobs/mob.tscn",
    "Scripts/player.gd", "Scripts/player_health.gd", "Scripts/mob.gd", "Scripts/TileMap.gd",
]
NET_LINE = re.compile(r"rpc|multiplayer|peer|authority|replicat|synchroniz|spawner|is_server|enet", re.I)
FULL_RUNS, LIGHT_RUNS = 20, 5


def net_lines(diff: str) -> dict[str, int]:
    """Changed lines that name netcode, per NETCODE_MIXED file, from `git diff -U0`."""
    hits: dict[str, int] = {}
    path = None
    for line in diff.splitlines():
        if line.startswith("diff --git "):
            path = None
        elif line.startswith(("--- a/", "+++ b/")):
            if line[6:] in NETCODE_MIXED:
                path = line[6:]
        elif path and line[:1] in "+-" and not line.startswith(("+++", "---")) \
                and NET_LINE.search(line[1:]):
            hits[path] = hits.get(path, 0) + 1
    return hits


def stress_tier(event: str, paths: list[str], diff: str | None) -> tuple[int, str]:
    """(runs per scenario, reason) for a gameplay change. diff=None: no diff, assume netcode."""
    if event == "push":
        return FULL_RUNS, "push to main"
    net = [p for p in paths if p in NETCODE]
    if diff is None:
        net += [p for p in paths if p in NETCODE_MIXED]
    else:
        net += ["%s (%d netcode lines)" % (p, n) for p, n in net_lines(diff).items()]
    if net:
        return FULL_RUNS, "netcode changed: " + ", ".join(net)
    return LIGHT_RUNS, "gameplay change without netcode"


def input_section(text: str) -> str:
    lines, inside = [], False
    for line in text.splitlines():
        if line.startswith("["):
            inside = line.strip() == "[input]"
        if inside:
            lines.append(line)
    return "\n".join(lines)


def gameplay_paths(paths: list[str], base_project: str | None, head_project: str | None) -> list[str]:
    hits = []
    for path in paths:
        if path == "project.godot":
            if base_project is None or head_project is None or \
                    input_section(base_project) != input_section(head_project):
                hits.append(path)
        elif any(fnmatch.fnmatchcase(path, g) for g in GAMEPLAY):
            hits.append(path)
    return hits


def self_test() -> int:
    inp = "[input]\n\nattack={}\n"
    cases = [
        (["Player/sword.tscn"], None, None, True),
        (["Scripts/mob.gd", "README.md"], None, None, True),
        (["map_admin_panel.tscn"], None, None, True),
        (["Scripts/map_gen.gd"], None, None, True),
        (["Scripts/map_gen.gd.uid", "docs/audio.md", "tools/verify.sh"], None, None, False),
        (["Scripts/MapGenParams.gd"], None, None, True),
        (["Scripts/map_save.gd"], None, None, True),
        (["Scripts/MapGenParams.gd.uid", "Scripts/map_save.gd.uid"], None, None, False),
        (["Scripts/player.gd.uid", "tests/run_tests.gd"], None, None, False),
        (["tests/ui/test_map_zoom.gd", "tests/helpers/test_helpers.gd"], None, None, False),
        (["project.godot"], None, None, True),
        (["project.godot"], "[application]\nname=1\n" + inp, "[application]\nname=2\n" + inp, False),
        (["project.godot"], inp + "[physics]\n", inp + "jump={}\n[physics]\n", True),
    ]
    fail = 0
    for paths, base, head, want in cases:
        got = bool(gameplay_paths(paths, base, head))
        if got != want:
            print("FAIL %s: got %s, want %s" % (paths, got, want), file=sys.stderr)
            fail += 1
    def diff(path: str, *lines: str) -> str:
        return "diff --git a/%s b/%s\n--- a/%s\n+++ b/%s\n@@ -1 +1 @@\n%s\n" % (
            path, path, path, path, "\n".join(lines))
    play = diff("Scripts/player.gd", "-\tvar speed = 1", "+\tvar speed = 2")
    play_net = diff("Scripts/player.gd", "+@rpc(\"any_peer\")", "+func hit():")
    scene_net = diff("flagoria_main.tscn", "+[node name=\"MultiplayerSpawner\" type=\"MultiplayerSpawner\"]")
    tiers = [
        ("pull_request", ["Scripts/mob_spawner.gd", "README.md"], "", FULL_RUNS),
        ("pull_request", ["tools/stress_netcode.py"], "", FULL_RUNS),
        ("pull_request", ["tests/late_join_probe.gd"], "", FULL_RUNS),
        ("pull_request", ["Scripts/player.gd"], play_net, FULL_RUNS),
        ("pull_request", ["flagoria_main.tscn"], scene_net, FULL_RUNS),
        ("pull_request", ["Scripts/player.gd"], None, FULL_RUNS),
        ("pull_request", ["Scripts/player.gd", "Player/sword.tscn"], play, LIGHT_RUNS),
        ("pull_request", ["Scripts/hearts_hud.gd"], diff("Scripts/hearts_hud.gd", "+rpc()"), LIGHT_RUNS),
        ("push", ["Scripts/hearts_hud.gd"], "", FULL_RUNS),
    ]
    for event, paths, text, want in tiers:
        got = stress_tier(event, paths, text)[0]
        if got != want:
            print("FAIL tier %s %s: got %d, want %d" % (event, paths, got, want), file=sys.stderr)
            fail += 1
    total = len(cases) + len(tiers)
    print("play_review_paths self-test: %d/%d ok" % (total - fail, total))
    return 1 if fail else 0


def read_opt(path: str | None) -> str | None:
    if not path or not os.path.exists(path):
        return None
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--files", help="changed paths, one per line (default: stdin)")
    ap.add_argument("--base-project", help="project.godot before the change")
    ap.add_argument("--head-project", help="project.godot after the change")
    ap.add_argument("--diff", help="`git diff -U0` of the change, for NETCODE_MIXED files")
    ap.add_argument("--event", default="pull_request", choices=["pull_request", "push"])
    ap.add_argument("--labeled", action="store_true", help="has needs-play-review: gameplay=true")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()
    if args.self_test:
        return self_test()
    text = read_opt(args.files) if args.files else sys.stdin.read()
    paths = [p.strip() for p in (text or "").splitlines() if p.strip()]
    hits = gameplay_paths(paths, read_opt(args.base_project), read_opt(args.head_project))
    for path in hits:
        print("gameplay: " + path)
    gameplay = bool(hits) or args.labeled
    print("gameplay=%s (%d of %d paths%s)" % (str(gameplay).lower(), len(hits), len(paths),
                                             ", labeled" if args.labeled else ""))
    runs, reason = stress_tier(args.event, paths, read_opt(args.diff) if args.diff else None)
    if gameplay:
        print("stress tier: %d runs per scenario (%s)" % (runs, reason))
    out = os.environ.get("GITHUB_OUTPUT")
    if out:
        with open(out, "a") as fh:
            fh.write("gameplay=%s\nstress_runs=%d\n" % (str(gameplay).lower(), runs))
    return 0


if __name__ == "__main__":
    sys.exit(main())
