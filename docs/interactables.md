# Adding an interactable type

A choppable plant (tree, pine and bush today) is one `InteractableType` resource (`Scripts/mechanics/interactables/interactable_type.gd`) in `data/interactables/`. Chopping, stumps, yields, sounds and regrowth all read the type, so a new kind that chops like the others needs a data file and assets, not new code (#264, #266). Follow the seven steps below in one pull request. The bush (#267, PR #293) is the worked example.

## 1. Data

Add `data/interactables/<id>.tres`, with `script_class="InteractableType"`. Start from `tree.tres`, `pine.tres` or `bush.tres`. Then add it to `TYPES` in `Scripts/mechanics/interactables/interactable_catalog.gd`.

The catalog is a fixed `preload` list. It does not scan `data/interactables/`, because exported builds keep only `.remap` files in that folder. A missing file in the list also fails when the script is parsed, so the mistake shows up in `tools/verify.sh`, not in play. A tile name may belong to only one type: `InteractableCatalog.type_at(atlas)` maps each foliage tile to its type.

| Field | Meaning | tree / pine / bush today |
|---|---|---|
| `id` | Type name, also used by `InteractableCatalog.by_id` | `tree`, `pine`, `bush` |
| `tiles` | `TileCatalog.TILES` names of the foliage-layer (layer 1) tiles it is | `TREE`, `TREE_BUSHY` / `TREE_PINE_SMALL` / `BUSH` |
| `hits` | Chop impacts until it falls (`ChopAction` times each hit) | 2 / 2 / 2 |
| `yields` | Resources given when it falls (step 4) | `{&"wood": 3}` / `{&"wood": 3}` / `{&"wood": 1}` |
| `leaves` | `TileCatalog.TILES` name of the walkable decor it leaves on `GROUND_DECOR_LAYER` | `STUMP` / `STUMP` / `BUSH_STUMP` |
| `regrow_delay` | Seconds of play before what it left turns back into it. 0 means never | 300 (default) for all three |
| `save_key` | Key for this type in world saves (step 5). Not read yet | `tree` / `pine` / `bush` |
| `hit_sounds`, `hit_layer_sounds`, `last_hit_sounds`, `fell_sounds`, `pickup_sounds`, `hit_no_repeat`, `fell_own_player` | Sound slots (step 3) | see `docs/audio.md`, Chop sounds |
| `hit_sheet` | 16x16 frames drawn in place of the tile after each impact | none / none / `art/flagoria/fx/bush_hit.png` |
| `fx_sheet` | 4 frames over the cell: 0-1 after each impact, 2-3 once it falls | none / none / `art/flagoria/fx/fx_leaves.png` |
| `fell_puff` | Play the puff cloud over the cell when it falls | true / true / false |

**`regrow_delay`.** `TreeCuts` (`Scripts/mechanics/trees/tree_cuts.gd`) records each cut's type, and `TileMap.regrow_due` regrows a stump once its type's `regrow_delay` has passed. The stump waits while a player stands on it. `TileMap.regrow_delay` (forwarded to `TreeCuts.regrow_delay`) is a map-wide override:
- -1, the default, uses each type's value;
- any other value applies to every type (the tests set 30).

0 changed meaning in #266 (PR #324). It used to mean "regrow at once"; it now means "never regrows", for both the type field and the override.

## 2. Art

- **Tiles:** add them to `art/flagoria/flagoria_tiles_v3.png` (16x16 cells), and name them in `Scripts/tile_catalog.gd`: a constant and an entry in `TILES`.
- **Collision:** set it in the TileSet `art/flagoria/flagoria_tiles_v3.tres`.
- **Hit sheet:** a type with a `hit_sheet` also needs alternative tile `ChopAction.HIDDEN_ALT` (1) in the TileSet: invisible, with the same collision. Otherwise the hit frames draw over the tile.
- **Tile table:** add a row to `docs/tiles.md`, for the plant and for what it leaves.
- **Credits:** credit new art in `art/flagoria/CREDITS.md`.
- **Generation:** to have the generator place the type, change `plant_tile` in `Scripts/TileMap.gd`. Where it grows is a separate decision from adding the type; `docs/biomes.md` lists each biome's plant chances.

## 3. Sound

- **Files:** put clips in `art/audio/sfx/world/<group>/<name>_NN.wav`. The groups today are `trees/` (also used by the pine) and `bushes/`. Format: 22,050 Hz, mono, 16-bit, like the tree and bush clips. Commit the generated `.import` files.
- **Credits:** add the clips to `art/audio/CREDITS.md`. Generated clips come from a script under `tools/audio/` (`gen_trees.py`, `gen_bushes.py`).
- **Slots:** fill them in the `.tres`, as #323 set them up:
  - `hit_sounds`: one picked per impact; `hit_no_repeat` avoids repeating the previous one;
  - `hit_layer_sounds`: with each hit;
  - `last_hit_sounds`: with the last impact;
  - `fell_sounds`: when it falls;
  - `pickup_sounds`: when the yields are added.
  Each slot plays on its own `AudioStreamPlayer2D`, and an empty slot plays nothing.
- **`fell_own_player`:** the fall comes 0.1 s after the last hit. With `fell_own_player` set, the fall gets its own player. Without it, the fall replaces the last hit sound on the same player. The tree and pine set it, and the bush does not.
- **Audio check:** add a step to `TIMELINE` in `tools/audio_check.gd` when the type's sounds need a mixer-level check. Only `chop_tree` exists today. See `docs/audio.md`, "Adding a sound and its check".

## 4. Yield

- **The amount** is set in `yields` in the `.tres`. `Interaction` adds each entry to `Scripts/inventory.gd` when the plant falls.
- **Wood** (`Inventory.WOOD`) is the only resource today. It is also the only one `Scripts/resource_hud.gd` shows. A new resource needs its constant in `Inventory`, plus a HUD change.

## 5. Save and sync

- **Save:** give the type a unique `save_key`. It is meant for `world.object_changes` in world saves (`Scripts/world_save.gd`, `docs/world-saves.md`). Nothing reads it until #198, and cuts are not saved yet.
- **Sync:** cuts and regrowth are not synced (#223, sync pending in #298). `Interaction.interact_allowed` is false while multiplayer is active (`Interaction.multiplayer_on`: a client, or a host with a peer). So interact mode is off in two-player games, and `regrow_due` does nothing there. A new type needs no sync work until #298.

## 6. Tests

Add `tests/mechanics/interactables/test_<id>s.gd`, like `test_bushes.gd`. The runner (`tests/run_tests.gd`) finds every `func _test_*() -> int` by itself. The tests should cover:
- **the chop:** hits and timing, hit frames, collision kept until it falls;
- **the yield:** the inventory rises by the type's `yields` once;
- **what it leaves:** the leftover on `GROUND_DECOR_LAYER` is walkable and stays when the chunk is drawn again;
- **regrowth.**

Also extend `_test_catalog_resolves_cells` in `test_interactable_catalog.gd` with the new tile. State each test's time cost in the pull request.

## 7. Verification feature file

Per #291 and the format from #287:
- **Same chop:** when the type chops the same way, add a sub-feature to `.cursor/skills/verify-flagoria/features/chop-trees-and-bushes.md` (or `chop-trees.md` for the live drive).
- **Different chop:** otherwise, add `.cursor/skills/verify-flagoria/features/<id>.md` with its index line in `.cursor/skills/verify-flagoria/features/README.md`.

The file covers:
- what the type is;
- how a player reaches it;
- how to drive it;
- the end state that proves it;
- gotchas;
- its time cost.

When a player can reach the type in a running game, add or extend a drive under `.cursor/skills/verify-flagoria/drives/` (`chop_trees.gd` picks the nearest tree or pine). Give it a `## launch: --seed N` line for `.github/workflows/verify-drive.yml`. Add the `needs-drive` label so CI runs it.
