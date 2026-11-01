# Explored map

The wood minimap panel `CanvasLayer1/MinimapPanel` (`Scripts/minimap_panel.gd`) shows the ground the hero has explored. `ExploredMap` (`Scripts/explored_map.gd`) marks every cell within `REVEAL_RADIUS` (10 cells, Euclidean) of the hero as explored as it moves, in 32 x 32 cell chunks.

## Sub-features

- `explored-reveal` cells within 10 cells of the hero become explored; the count only grows.
- `explored-panel` the minimap panel is in the main scene and draws the explored cells.
- `explored-incremental` the panel paints only newly revealed cells (and the ring around them), pixel for pixel the same as drawing each chunk from scratch.

## How to get to it (user POV)

- Host a world and walk; the panel at the top right fills in around the path.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: each test below is under 0.5 s in `tools/verify.sh` (~1.1-1.5 s alone with `--only`); a live drive is ~5-6 s.

- **Run (headless).** `godot --headless --path . --script res://tests/run_tests.gd -- --only=explored_map,minimap_panel_in_scene,minimap_incremental_render`, or the full `tools/verify.sh`.
- **Drive (live).** `start_game()`, `snapshot()`, `hold("ui_right", N)`, `snapshot()`, then walk back part of the way over the same cells and `snapshot()` again.
- **Proof.** End state: `explored_cells` in the snapshot JSON (`MinimapPanel.explored.explored_count()`) goes up while walking and stays the same on the second pass over ground already walked; a PNG of the window under `--display` shows the panel top right with the explored path.

## Gotchas

- Explored state is not in world saves yet (`Scripts/map_save.gd` has no explored data).
- `explored_cells` is 0 until the first reveal after spawn, so take the start count after a few frames.
- `hold()` moves the hero only until something blocks it. If the first pass was cut short, walking back can reach new ground and the count rises; compare hero cells, not frame counts, before claiming "same ground".
- `snapshot()` PNGs show the whole window, not only the panel.
- Headless tests: `-- test_explored_map`, `-- test_minimap_panel_in_scene`, `-- test_minimap_incremental_render`.
