#!/usr/bin/env python3
"""Does a change touch gameplay? Decides the `needs-play-review` label.

Gameplay means player, combat and aim, mobs, scenes, HUD and menus, touch
input, netcode, map generation parameters, tiles and biomes, scores,
inventory, saved worlds, choppable types, and the input map in project.godot.
Audio scripts are not gameplay. A
project.godot change counts only when its [input] section differs; with no
before/after copies given, any project.godot change counts.

Also picks the netcode stress tier (runs per scenario): skipped when the
change is not gameplay and does not touch the stress matrix (STRESS_MATRIX);
otherwise see FULL_RUNS, LIGHT_RUNS and stress_tier() below and
.cursor/skills/verify-flagoria/ci-netcode-stress.md. Without --diff, any
NETCODE_MIXED file counts as netcode.

Reads changed paths, one per line, from --files (or stdin). Prints the
matching paths and the tier, and writes `gameplay=true|false`,
`stress_runs=N`, and `run_stress=true|false` to $GITHUB_OUTPUT when set.
`run_stress` is what play-review.yml uses to start the matrix. It is true
for a gameplay change and also for a stress-matrix path that is not
player-facing gameplay (the runner, the lint, tests/net, and probes).

CI runs this at most once per job via the composite
`.github/actions/classify-change` (play-review.yml, verify-drive.yml,
pr-debug-apk.yml, play-review-label.yml). Job outputs: `gameplay`, `stress_runs`, `run_stress`,
and `paths_file` (the path list file used). Rules stay in this file only.

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
NOT_GAMEPLAY = [
    "debug/*",  # editor-only layouts, not reachable in play
]

GAMEPLAY = [
    "Player/*", "Mobs/*", "*.tscn",
    "flagoria_main.gd",  # host, join, spawn and sync
    "TouchScreenButton.gd", "addons/virtual_joystick/*",  # touch input
    "Scripts/player.gd", "Scripts/player_health.gd",
    "Scripts/mob.gd", "Scripts/mob_spawner.gd", "Scripts/mob_catalog.gd",
    "Scripts/TileMap.gd",  # chunk loading, collision, ground sync
    "Scripts/world/*.gd",  # terrain shape and spawn search for the world map
    "Scripts/mechanics/*.gd",  # cuts, bridges, walls, structures, choppable types (all subfolders)
    "Scripts/map_gen.gd",  # session map parameters applied to the world map
    "Scripts/MapGenParams.gd",  # map generation defaults and value ranges
    "Scripts/map_save.gd",  # saved worlds: which parameters a world loads with
    "Scripts/hearts_hud.gd", "Scripts/map_zoom.gd",
    "Scripts/MainMenu.gd", "Scripts/MapAdminPanel.gd", "Scripts/world_save_preview.gd",
    "Scripts/attack_aim.gd", "Scripts/aim_cone_style.gd",  # aimed attacks and the cone's reach
    "Scripts/points.gd", "Scripts/discovery_points.gd",  # score awards
    "Scripts/inventory.gd",  # gathered wood
    "Scripts/game_settings.gd",  # mob spawn rate
    "Scripts/tile_catalog.gd", "Scripts/BiomeCatalog.gd",  # tiles and biome tables of the world map
    "Scripts/world_save.gd",  # what a saved world keeps
    "Scripts/player_save.gd",  # player position, health, wood, score, charted ground
    "Scripts/explored_map.gd", "Scripts/minimap_panel.gd",  # explored map and its HUD panel
    "Scripts/parchment_map.gd", "Scripts/map_wood_button.gd",  # parchment full map and its wood controls
    "Scripts/resource_hud.gd", "Scripts/score_hud.gd", "Scripts/scoreboard_toggle.gd",
    "Scripts/scoreboard_panel.gd",
    "Scripts/ingame_menu.gd", "Scripts/hud_layout.gd", "Scripts/hud_layout_edit.gd",
    "Scripts/quit_prompt.gd", "Scripts/number_pad.gd", "hud_layout_edit.tscn",
    "data/interactables/*.tres",  # choppable types: hits, yields, regrowth, art and sounds
]

# Not player-facing gameplay (no drive evidence, no debug APK, no
# needs-play-review). They still start the full stress matrix. A broken
# runner, lint, probe, or net scenario would otherwise show up only on the
# next gameplay pull request. fnmatch "*" matches "/".
STRESS_MATRIX = [
    "tests/net/*",  # multiplayer scenarios the stress job runs
    "tests/*_probe.gd",  # headless peer processes those scenarios start
    "tools/stress_netcode.py",
    "tools/stress_scenario_lint.py",
    "tools/stress_scenario_lint_allow.txt",
]
# Netcode files: spawners, RPC-only scripts, and the stress matrix above.
# Any change to them gets the full stress tier.
NETCODE = [
    "Scripts/mob_spawner.gd", "Scripts/points.gd", "Scripts/discovery_points.gd",
    "tilemap_dynamic.tscn",
    *STRESS_MATRIX,
]
# Files that mix netcode with other gameplay. They get the full tier only when
# a changed line names netcode (RPCs, peers, authority, synchronizers).
NETCODE_MIXED = [
    "flagoria_main.gd", "flagoria_main.tscn",
    "Player/character_body_2d.tscn", "Mobs/mob.tscn",
    "Scripts/player.gd", "Scripts/player_health.gd", "Scripts/mob.gd", "Scripts/TileMap.gd",
]
NET_LINE = re.compile(r"rpc|multiplayer|peer|authority|replicat|synchroniz|spawner|is_server|enet", re.I)

# Netcode stress tier (runs per scenario in CI and on main pushes). Authoritative
# rules for agents and workflows: change tiers here only; see the table in
# .cursor/skills/verify-flagoria/ci-netcode-stress.md (do not duplicate those
# rules in workflow YAML comments except a pointer to this file).
#
# Skipped (~seconds): not a gameplay change and no STRESS_MATRIX path (no
# paths in GAMEPLAY, no needs-play-review label, and no runner, lint, probe,
# or tests/net file). play-review.yml still runs --self-test and
# classification; it skips Godot and stress_netcode.py.
#
# LIGHT_RUNS (5): pull_request + gameplay paths, but stress_tier() picks the
# light tier — no NETCODE file changed, and no netcode-tagged line in a changed
# NETCODE_MIXED file (git diff -U0). Roughly 3–10 minutes for the job.
#
# FULL_RUNS (20): event push (when the matrix runs), or any NETCODE path
# changed (including STRESS_MATRIX: the runner, the lint, tests/net, and
# tests/*_probe.gd), or any NETCODE_MIXED path whose changed lines match
# NET_LINE, or (when --diff is omitted) any NETCODE_MIXED path in the path
# list. Up to ~25 minutes.
FULL_RUNS, LIGHT_RUNS = 20, 5


def _match(path: str, patterns: list[str]) -> bool:
    return any(fnmatch.fnmatchcase(path, pat) for pat in patterns)


def matrix_paths(paths: list[str]) -> list[str]:
    """Changed paths that start the full stress matrix on their own."""
    return [p for p in paths if _match(p, STRESS_MATRIX)]


def runs_stress(gameplay: bool, paths: list[str]) -> bool:
    """True when play-review.yml should run the scenario matrix."""
    return gameplay or bool(matrix_paths(paths))


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
    net = [p for p in paths if _match(p, NETCODE)]
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
        if any(fnmatch.fnmatchcase(path, g) for g in NOT_GAMEPLAY):
            continue
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
        (["Scripts/world/spawn_finder.gd"], None, None, True),
        (["Scripts/world/terrain_shape.gd.uid"], None, None, False),
        (["debug/building_block_pieces.tscn"], None, None, False),
        (["Scripts/mechanics/trees/tree_cuts.gd"], None, None, True),
        (["Scripts/mechanics/bridges/bridge_builder.gd"], None, None, True),
        (["Scripts/mechanics/interact/interaction.gd"], None, None, True),
        (["Scripts/mechanics/trees/chop_action.gd"], None, None, True),
        (["Scripts/mechanics/walls/wall_solver.gd.uid"], None, None, False),
        (["Scripts/player.gd.uid", "tests/run_tests.gd"], None, None, False),
        (["tests/ui/test_map_zoom.gd", "tests/helpers/test_helpers.gd"], None, None, False),
        # Stress tooling is not player-facing gameplay. runs_stress() still
        # starts the full matrix for these paths; see the matrix cases below.
        (["tools/stress_netcode.py", "tools/stress_scenario_lint.py"], None, None, False),
        (["tools/stress_scenario_lint_allow.txt"], None, None, False),
        (["tests/wall_sync_probe.gd", "tests/net/test_wall_sync.gd"], None, None, False),
        (["tests/docker_publish_probe.gd"], None, None, False),
        (["Scripts/attack_aim.gd"], None, None, True),
        (["Scripts/aim_cone_style.gd"], None, None, True),
        (["Scripts/points.gd"], None, None, True),
        (["Scripts/world_save.gd"], None, None, True),
        (["Scripts/player_save.gd"], None, None, True),
        (["Scripts/ingame_menu.gd"], None, None, True),
        (["Scripts/hud_layout.gd", "Scripts/hud_layout_edit.gd", "hud_layout_edit.tscn"], None, None, True),
        (["data/interactables/tree.tres"], None, None, True),
        (["Scripts/attack_aim.gd.uid", "data/interactables/tree.tres.uid"], None, None, False),
        (["Scripts/combat_sfx.gd", "Scripts/music_player.gd", "tools/render_biomes.gd"], None, None, False),
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
        ("pull_request", ["tools/stress_scenario_lint.py"], "", FULL_RUNS),
        ("pull_request", ["tests/late_join_probe.gd"], "", FULL_RUNS),
        ("pull_request", ["tests/wall_sync_probe.gd"], "", FULL_RUNS),
        ("pull_request", ["tests/net/test_wall_sync.gd"], "", FULL_RUNS),
        ("pull_request", ["tests/net/test_wall_sync.gd.uid"], "", FULL_RUNS),
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
    # Workflows that pass --diff (play-review, verify-drive) vs those that omit it
    # (pr-debug-apk, play-review-label) must agree on gameplay for the same paths.
    parity = [
        (["docs/ci-required-checks.md", "tools/required_checks.py"], "", False, LIGHT_RUNS),
        (["docs/ci-required-checks.md", "tools/required_checks.py"], None, False, LIGHT_RUNS),
        (["Scripts/hearts_hud.gd"], play, True, LIGHT_RUNS),
        (["Scripts/hearts_hud.gd"], None, True, LIGHT_RUNS),
        (["Scripts/player.gd"], play, True, LIGHT_RUNS),
        (["Scripts/player.gd"], None, True, FULL_RUNS),
    ]
    for paths, diff, want_play, want_runs in parity:
        got_play, got_runs = classify(paths, diff=diff)
        if got_play != want_play or got_runs != want_runs:
            print(
                "FAIL workflow parity %s diff=%s: got play=%s runs=%d, want %s %d"
                % (paths, diff is not None, got_play, got_runs, want_play, want_runs),
                file=sys.stderr,
            )
            fail += 1
    # These paths are not player-facing, but each one starts the full matrix
    # with or without a diff. A UI test and a verify script do not.
    matrix_cases = [
        ["tools/stress_netcode.py"],
        ["tools/stress_scenario_lint.py"],
        ["tools/stress_scenario_lint_allow.txt"],
        ["tests/wall_sync_probe.gd"],
        ["tests/late_join_probe.gd"],
        ["tests/net/test_wall_sync.gd"],
        ["tests/docker_publish_probe.gd"],
    ]
    for paths in matrix_cases:
        for text in ("", None):
            got_play, got_runs = classify(paths, diff=text)
            if got_play or got_runs != FULL_RUNS or not runs_stress(got_play, paths):
                print(
                    "FAIL stress matrix %s diff=%s: play=%s runs=%d stress=%s"
                    % (paths, text is not None, got_play, got_runs,
                       runs_stress(got_play, paths)),
                    file=sys.stderr,
                )
                fail += 1
    for paths in (["tests/ui/test_map_zoom.gd"], ["tools/verify.sh"], ["README.md"]):
        got_play, _runs = classify(paths, diff="")
        if runs_stress(got_play, paths):
            print("FAIL stress matrix should skip %s" % paths, file=sys.stderr)
            fail += 1
    if not runs_stress(True, ["Scripts/hearts_hud.gd"]):
        print("FAIL gameplay change should run stress", file=sys.stderr)
        fail += 1
    docs = ["docs/architecture.md", "README.md"]
    hud = ["Scripts/hearts_hud.gd"]
    for paths in (docs, hud):
        with_diff = classify(paths, diff="")
        without = classify(paths, diff=None)
        if with_diff != without:
            print(
                "FAIL workflow parity mismatch for %s: with_diff=%s without=%s"
                % (paths, with_diff, without),
                file=sys.stderr,
            )
            fail += 1
    total = len(cases) + len(tiers) + len(parity) + 2 + len(matrix_cases) * 2 + 4
    print("play_review_paths self-test: %d/%d ok" % (total - fail, total))
    return 1 if fail else 0


def classify(
    paths: list[str],
    *,
    base_project: str | None = None,
    head_project: str | None = None,
    diff: str | None = None,
    event: str = "pull_request",
    labeled: bool = False,
) -> tuple[bool, int]:
    """(gameplay, stress_runs) — same outputs CI workflows read from GITHUB_OUTPUT."""
    hits = gameplay_paths(paths, base_project, head_project)
    gameplay = bool(hits) or labeled
    runs, _reason = stress_tier(event, paths, diff)
    return gameplay, runs


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
    matrix = matrix_paths(paths)
    for path in matrix:
        print("stress matrix: " + path)
    do_stress = runs_stress(gameplay, paths)
    print("gameplay=%s (%d of %d paths%s)" % (str(gameplay).lower(), len(hits), len(paths),
                                             ", labeled" if args.labeled else ""))
    runs, reason = stress_tier(args.event, paths, read_opt(args.diff) if args.diff else None)
    if do_stress:
        print("stress tier: %d runs per scenario (%s)" % (runs, reason))
    print("run_stress=%s" % str(do_stress).lower())
    out = os.environ.get("GITHUB_OUTPUT")
    if out:
        with open(out, "a") as fh:
            fh.write("gameplay=%s\nstress_runs=%d\nrun_stress=%s\n" % (
                str(gameplay).lower(), runs, str(do_stress).lower()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
