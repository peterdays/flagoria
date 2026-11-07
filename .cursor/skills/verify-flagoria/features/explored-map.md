# Explored map

Drive: drives/explored_map.gd

The wood minimap panel `CanvasLayer1/MinimapPanel` (`Scripts/minimap_panel.gd`) shows the ground the hero has explored. `ExploredMap` (`Scripts/explored_map.gd`) marks every cell within `REVEAL_RADIUS` (10 cells, Euclidean) of the hero as explored as it moves, in 32 x 32 cell chunks.

The panel header has two wood controls, drawn in the frame's own colours: collapse (a minus) and maximize (a square). Collapse hides the window and leaves a wood chip, `CanvasLayer1/MapReopen`, in the same corner; tapping the chip opens the panel again. M does the same toggle. Maximize, or Shift+M, opens `CanvasLayer1/ParchmentMap` (`Scripts/parchment_map.gd`): the explored ground on an old parchment sheet, with paper fog instead of the panel's blue mist. The world is not paused. While the sheet is open the local hero cannot move or attack, wheel and pinch zoom are used up, and a drag pans the sheet. The cross recentres on the hero. Close, Esc, or a hit on the hero puts the wood panel back as it was.

## Sub-features

- `explored-reveal` cells within 10 cells of the hero become explored; the count only grows.
- `explored-panel` the minimap panel is in the main scene and draws the explored cells.
- `explored-incremental` the panel paints only newly revealed cells (and the ring around them), pixel for pixel the same as drawing each chunk from scratch.

## How to get to it (user POV)

- Host a world. The wood panel is at the top right. Collapse hides it behind the corner chip; the chip opens it again. Maximize opens the parchment. Drag to pan, then Close to return to the panel.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: each test below is under 0.5 s in `tools/verify.sh` (~1.1-1.5 s alone with `--only`); a live drive is ~5-6 s.

- **Run (headless).** `godot --headless --path . --script res://tests/run_tests.gd -- --only=explored_map,minimap_panel_in_scene,minimap_incremental_render,parchment_map`, or the full `tools/verify.sh`. `test_parchment_map` is under 1 s.
- **Drive (live).** `bin/launch.sh drives/explored_map.gd --display --seed 42` (under xvfb). About 20 s. Steps `open`, `collapse`, `reopen`, `parchment`, `pan`, `input-blocked`, `close`, `input-restored`, `phone-landscape` (854x480), `phone-portrait` (360x640, a tall window that fits a 1280x720 display).
- **Proof.** End state: collapse hides the panel and shows the chip; the chip shows the panel; maximize shows the parchment and hides the panel; a drag changes `pan`; walking and attacking do nothing while it is open and walking works again after Close; the same controls stay inside the viewport at 854x480 and 360x640. Screenshots: `open-landscape`, `collapsed-landscape`, `reopened-landscape`, `parchment-landscape`, `panned-landscape`, `closed-landscape`, `collapsed-phone-landscape`, `parchment-phone-landscape`, `open-phone-portrait`, `collapsed-phone-portrait`, `parchment-phone-portrait`.

## Gotchas

- Explored state is not in world saves yet (`Scripts/map_save.gd` has no explored data).
- `explored_cells` is 0 until the first reveal after spawn, so take the start count after a few frames.
- `hold()` moves the hero only until something blocks it. If the first pass was cut short, walking back can reach new ground and the count rises; compare hero cells, not frame counts, before claiming "same ground".
- `snapshot()` PNGs show the whole window, not only the panel.
- Headless tests: `-- test_explored_map`, `-- test_minimap_panel_in_scene`, `-- test_minimap_incremental_render`, `-- test_parchment_map`.
- The parchment does not pause the tree. Only the local hero's movement and attacks are ignored, and only while the sheet is open.
