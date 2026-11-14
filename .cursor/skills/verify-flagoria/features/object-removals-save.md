# Object removals save

Drive: drives/object_removals_save.gd

Picked ground flowers and stones destroyed by a sword swing are recorded in
`world.object_changes` as `{"removed": true}` on each cell (#198). They stay
gone when the player walks away and the chunk redraws, and after save and
reload. Trees and bushes still use the cut entries; defeated mobs are not
saved.

## Sub-features

- `object-removals-round-trip` `ObjectRemovals` on a seeded map with biomes on
  (seed 0 when both a flower and stones are needed near spawn):
  pick a flower and destroy stones, regenerate the chunk, save and load, and
  check the entries and the empty decor cells (`tests/saves/test_object_removals_save.gd`).
- `object-removals-in-game` the in-game Save button writes removals; loading
  the save and running `_restore_loaded_world` restores them before draw.

## How to get to it (user POV)

- Host alone with biomes on: interact mode, aim at a ground flower with the
  attack button and tap to pick it. Combat mode: swing at walkable stones to
  clear them.
- Menu → Save, then Worlds → Load to confirm they stay gone.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: the two new tests add about
0.4 s to `tools/verify.sh` with `--only=object_removals`.

- **Run.** `./tools/verify.sh` and read `artifacts/verify.log` for
  `-- test_object_removals_round_trip` and `-- test_object_removals_in_game`.
- **Drive (live).** `bin/launch.sh drives/object_removals_save.gd --display
  --seed 7` picks a nearby flower, saves, reloads the save, and checks the
  cell stays empty (`before_pick`, `picked`, `loaded`).

## Gotchas

- Flowers and stones need `biome_frequency > 0` on the params (the test and
  drive turn biomes on). With biomes off, flowers can still appear from Map
  Settings but stones do not generate.
- A removal entry is dropped on load when the generator no longer places decor
  on that cell.