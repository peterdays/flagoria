# Player save

Drive: drives/player_save.gd

A world save keeps the host's own progress in `player`: position, health, wood, score and charted ground. Loading that file and hosting it puts the host back there. An older save with no player section, or `{}`, starts a default player at the spawn with full health, no wood, no score and nothing charted. Format: [World saves](../../../docs/world-saves.md).

## Sub-features

- `player-round-trip` `PlayerSave` (`Scripts/player_save.gd`) writes the section from the in-game menu's Save and applies it when the host body is placed. Health is half-hearts, wood is the inventory, score is the point total, charted ground is the explored-map bitset.
- `player-score-chunks` chunks that already paid discovery points are stored with the score, so a load does not pay them again.
- `player-legacy` a version 1, 2 or 3 file with an empty or missing `player` object loads as the default player. A bad value on one key uses that key's default.
- `player-join` a joining peer is not this section. They start fresh. The host's health and score still sync as in a live match.

## How to get to it (user POV)

- Host, walk, take a hit or chop a plant, open Menu, Save. Main menu, Worlds, Load. The hero is back at that spot, with the same hearts, wood, score and chart.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: the two tests add about 2 s to `tools/verify.sh`. The live drive is about 25 s with `--display`.

- **Run.** `./tools/verify.sh`, or `godot --headless --path . --script res://tests/run_tests.gd -- --only=player_save_round_trip,player_save_legacy_defaults`.
- **Proof.** `-- test_player_save_round_trip` and `-- test_player_save_legacy_defaults` with no `FAIL` after them. The round trip is the hit, the wood, the score and the charted cell. The legacy test is the default player for fixtures `world_save_v1.json`, `world_save_v2.json` and `world_save_v3.json`.
- **Drive (live).** `bin/launch.sh drives/player_save.gd --seed 49 --display`. Host, walk, chop the nearest plant, Save, Main menu, Worlds, Load. Shots `before_save` and `loaded` show the hero on the same ground with the same wood. `saved` shows the menu line `Saved:`.

## Gotchas

- Files live under `user://`. A verify run uses its own user dir.
- The drive does not wait for a mob hit. Health at a value other than full is `test_player_save_round_trip` (half-hearts set to 4, then loaded).
- Discovery can add a point about half a second after standing in a new chunk. The saved chunks are restored so that point is not awarded twice. Flag-tower points keep ticking every 5 s after the load; that is new play, not a second copy of the saved total.
- Held items are not in the section. There are none yet.
