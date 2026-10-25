#!/usr/bin/env python3
"""Does a change touch gameplay? Decides the `needs-play-review` label.

Gameplay means player, mobs, scenes, HUD and menus, touch input, netcode,
map generation parameters, and the input map in project.godot. A
project.godot change counts only when its [input] section differs; with no
before/after copies given, any project.godot change counts.

Reads changed paths, one per line, from --files (or stdin). Prints the
matching paths and writes `gameplay=true|false` to $GITHUB_OUTPUT when set.
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
    "Scripts/hearts_hud.gd", "Scripts/map_zoom.gd",
    "Scripts/MainMenu.gd", "Scripts/MapAdminPanel.gd",
]


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
        (["Scripts/player.gd.uid", "tests/run_tests.gd"], None, None, False),
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
    print("play_review_paths self-test: %d/%d ok" % (len(cases) - fail, len(cases)))
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
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()
    if args.self_test:
        return self_test()
    text = read_opt(args.files) if args.files else sys.stdin.read()
    paths = [p.strip() for p in (text or "").splitlines() if p.strip()]
    hits = gameplay_paths(paths, read_opt(args.base_project), read_opt(args.head_project))
    for path in hits:
        print("gameplay: " + path)
    print("gameplay=%s (%d of %d paths)" % (str(bool(hits)).lower(), len(hits), len(paths)))
    out = os.environ.get("GITHUB_OUTPUT")
    if out:
        with open(out, "a") as fh:
            fh.write("gameplay=%s\n" % str(bool(hits)).lower())
    return 0


if __name__ == "__main__":
    sys.exit(main())
