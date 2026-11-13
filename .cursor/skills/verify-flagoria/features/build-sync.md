# Build sync (plank bridges, two-player)

Drive: not player-facing

In a two-player game a plank bridge placed by any player appears on every peer
(#297), is walkable on every peer, and spends wood only for the player who
placed it. The placer asks the host, the host decides and tells everyone, and
only the placer is charged. A player joining later gets the host's exact bridge
set with the map params. Offline and host-alone placement is unchanged
([Build placement](./build-placement.md), [Construction placement](./construction-placement.md)).
Walls and towers are requested from the host
([Walls and cities sync](./walls-cities-sync.md), [Conquest sync](./conquest-sync.md)).

## Sub-features

- `build-request` a client's Plank commit ends in `Interaction.place_planks`,
  which sends `request_place_planks(cells)` to the host
  (`Scripts/mechanics/interact/interaction.gd`).
- `build-decide` the host checks the placer is alive and within
  `REACH` + `REACH_SLACK` of every cell, writes through
  `ConstructionPlacer.write_plank` (geometry only; no floating planks), sends
  `apply_bridge(from, to)` to every other peer and `receive_charge(wood)` to
  the placer. A host placing with peers connected spends through
  `ConstructionPlacer.place` then broadcasts `apply_bridge`.
- `build-apply` peers lay the same run with `TileMap.build_bridge`. Applying a
  run that is already there does nothing useful (writer returns false).
- `build-join` a joining peer gets the bridge list with the map params and
  replaces its bridges with it (`world.replace_bridges` /
  `BridgeBuilder.replace_from_host`). Live places after that arrive on the same
  reliable channel.
- `build-mode` interact mode shows Plank, Tower and Wall in multiplayer.

## How to get to it (user POV)

1. Host a game, join from a second peer.
2. Gather wood (cut trees/bushes).
3. Enter interact mode, pick Plank, drag a run on water that touches land or an
   existing plank; lift to place. Both peers see the bridge.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost:
`test_build_sync_two_players` about 8–15 s alone with `--only=` (three Godot
peers); in the Netcode stress job it is one scenario × 20 runs.

- **Run (headless).** `godot --headless --path . --script res://tests/run_tests.gd -- --only=build_sync_two_players`, or the Netcode stress job / full `tools/verify.sh`.
- **Proof.** Header `-- test_build_sync_two_players` in the log with
  `PASS test_build_sync_two_players (...)` and no `FAIL` after it.

## Gotchas

- Inventories stay local per peer; the host charges the placer with
  `receive_charge`, it does not spend the host's wood for a client's place.
- Do not lift the Wall multiplayer gate here; towers already use StructureRequests (#497).
- Bridge join list is a flat `[x, y, atlas_x, atlas_y]` array, not the cut
  changes dictionary.
