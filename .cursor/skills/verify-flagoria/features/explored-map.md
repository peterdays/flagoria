# Explored map

Drive: drives/explored_map.gd

The wood minimap panel `CanvasLayer1/MinimapPanel` (`Scripts/minimap_panel.gd`) shows the ground the hero has explored. `ExploredMap` (`Scripts/explored_map.gd`) marks every cell within `REVEAL_RADIUS` (10 cells, Euclidean) of the hero as explored as it moves, in 32 x 32 cell chunks.

The panel starts closed. The round minimap button in the HUD row (`CanvasLayer1/MinimapButton`) opens it; collapse and M hide it again. There is no reopen chip. The panel header has two wood controls, drawn in the frame's own colours: collapse (a minus) and maximize (a square). Maximize, or Shift+M, opens `CanvasLayer1/ParchmentMap` (`Scripts/parchment_map.gd`): the explored ground on an old parchment sheet, with paper fog instead of the panel's blue mist. The world is not paused. While the sheet is open the local hero cannot move or attack; wheel and two-finger pinch on the parchment zoom the sheet in integer pixel steps from a minimum that fits the whole explored chart up to 16 pixels per cell, centred on the wheel or pinch midpoint, without changing the play camera. One-finger drag still pans at any zoom. The cross recentres on the hero without changing zoom; closing and reopening returns to the default scale. Close, Esc, or a hit on the hero puts the wood panel back as it was.

## Sub-features

- `explored-reveal` cells within 10 cells of the hero become explored; the count only grows.
- `explored-panel` the minimap panel is in the main scene and draws the explored cells.
- `explored-incremental` the panel paints only newly revealed cells (and the ring around them), pixel for pixel the same as drawing each chunk from scratch.

## How to get to it (user POV)

- Host a world. The wood panel stays closed until the minimap button. It opens at the top right. Collapse hides it; the button opens it again. Maximize opens the parchment. Wheel or pinch to zoom (default, minimum, maximum on a phone-sized window), drag to pan, recentre, then Close to return to the panel.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: each test below is under 0.5 s in `tools/verify.sh` (~1.1-1.5 s alone with `--only`); a live drive is ~5-6 s.

- **Run (headless).** `godot --headless --path . --script res://tests/run_tests.gd -- --only=explored_map,minimap_panel_in_scene,minimap_incremental_render,parchment_map`, or the full `tools/verify.sh`. `test_parchment_map` is under 1 s.
- **Drive (live).** `bin/launch.sh drives/explored_map.gd --display --seed 42` (under xvfb). About 25 s. Steps `open`, `collapse`, `reopen`, `parchment`, `pan`, `parchment-zoom` (1080x2400 portrait window for zoom evidence), `input-blocked`, `close`, `input-restored`, `phone-landscape` (854x480), `phone-portrait` (360x640, a tall window that fits a 1280x720 display).
- **Proof.** End state: the minimap button shows the panel; collapse hides it and does not show a chip; the button shows the panel again; maximize shows the parchment and hides the panel; a drag changes `pan`; wheel zoom on the parchment changes `cell_px` at default, minimum and maximum on a phone-sized window and recentre clears `pan` without resetting zoom; walking and attacking do nothing while it is open and walking works again after Close; the same controls stay inside the viewport at 854x480 and 360x640. Screenshots: `open-landscape`, `collapsed-landscape`, `reopened-landscape`, `parchment-landscape`, `panned-landscape`, `parchment-zoom-default-phone`, `parchment-zoom-min-phone`, `parchment-zoom-max-phone`, `parchment-recentred-phone`, `closed-landscape`, `collapsed-phone-landscape`, `parchment-phone-landscape`, `open-phone-portrait`, `collapsed-phone-portrait`, `parchment-phone-portrait`.

## Gotchas

- Explored ground is the `player.charted` section of a world save (see [Player save](./player-save.md)). A new match still starts with nothing charted.
- `explored_cells` is 0 until the first reveal after spawn, so take the start count after a few frames.
- `hold()` moves the hero only until something blocks it. If the first pass was cut short, walking back can reach new ground and the count rises; compare hero cells, not frame counts, before claiming "same ground".
- `snapshot()` PNGs show the whole window, not only the panel.
- Headless tests: `-- test_explored_map`, `-- test_minimap_panel_in_scene`, `-- test_minimap_incremental_render`, `-- test_parchment_map`.
- The parchment does not pause the tree. Only the local hero's movement and attacks are ignored, and only while the sheet is open.
