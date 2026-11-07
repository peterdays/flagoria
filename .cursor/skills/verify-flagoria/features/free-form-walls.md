# Free-form walls

Drive: drives/free_form_walls.gd

Free-form wooden palisade walls as one connected chain (#276). Interact mode
shows a Wall icon next to Cut / Plank / Tower. The tool keeps a persistent tip
while selected: the first placement must 4-touch an existing tower, castle or
wall (otherwise refuse with feedback and spend nothing); after that a tap must
4-touch the tip, and a drag lays an H/V-snapped straight segment
starting on the neighbour of the tip toward the finger. Leaving the Wall tool
clears the tip. Gaps and diagonals are refused with feedback and spend no wood.
Each wall block costs 2 wood through `ConstructionPlacer` /
`BuildCosts.WALL_BLOCK` (spend before write, full refund on writer refusal).
Pieces come from `WallSolver` (`PALISADE_*`); no gates in this slice. A cell
that touches stone gets collar overlays ([Wall and tower junctions](./wall-junctions.md)). Length is
unlimited (reach still bounds a drag). Land only; refuse structures, existing
walls, players, mobs, trees and bushes. Collision stays when a chunk redraws.
While multiplayer is on, the Wall icon is hidden (same gate as Plank / Tower);
peer sync of walls is #278. Preview green cells and cost match exactly what
`commit` places and charges.

## Sub-features

- `build-wall-picker` Wall icon appears in interact mode with Cut / Plank /
  Tower, hides while multiplayer is on, and switches `BuildPlacement.tool` to
  Wall.
- `build-wall-tip` first block must 4-touch tower/castle/wall; tip persists
  while Wall is selected; tap must 4-touch tip; drag is H/V from the tip
  neighbour; leave tool clears tip; gap / diagonal / floating first block
  return "not adjacent" and spend nothing.
- `build-wall-preview` green cells and cost match what commit places and
  charges; red when refused.
- `construction-wall` a clear land cell or straight H/V run places palisade
  pieces for 2 wood each through ConstructionPlacer; water, occupied, bent,
  short wood and multiplayer on are refused and spend nothing; redraw keeps
  collision.
- `construction-wall-atomic` spend-fail stub leaves no wall; writer refusal
  after a real spend refunds the wood (#380).

## How to get to it (user POV)

1. Start a local game (Host alone or offline) with wood.
2. Tap the mode button to enter interact mode; the Cut / Plank / Tower / Wall
   picker appears.
3. Tap Wall, tap clear land that 4-touches the castle, a tower or a wall.
   The tip stays. Tap a 4-neighbour or drag a straight run next to the tip;
   green cells show the wood cost. Lift to place. Switch away from Wall to
   clear the tip.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: `test_construction_placer_wall`
about 0.7 s in `tools/verify.sh` (~2.5 s alone with `--only=`);
`test_construction_placer_wall_atomic_spend` about 0.3 s (~2.0 s alone);
`test_build_picker_includes_wall` about 0.35 s (~2.0 s alone);
`test_build_wall_segment_tip_and_gap` under 0.05 s (~1.8 s alone);
`test_build_wall_preview_matches_commit` about 0.6 s (~2.3 s alone);
`test_build_wall_first_must_touch_structure` about 0.5 s (~2.2 s alone). Drive
about 20 s under xvfb.

- **Run (headless).** `godot --headless --path . --script res://tests/run_tests.gd -- --only=construction_placer_wall,construction_placer_wall_atomic_spend,build_picker_includes_wall,build_wall_segment_tip_and_gap,build_wall_preview_matches_commit,build_wall_first_must_touch_structure`, or the full `tools/verify.sh`.
- **Drive (live).** `bin/launch.sh drives/free_form_walls.gd --display` (under xvfb). Steps `start`, `interact`, `first-block`, `chain`, `gap`: `start_game()`, settle, `snapshot("start")`, enter interact + Wall, give wood, place a first land block, `snapshot("first-block")`, place a short H chain off the tip, `snapshot("chain")`, try a gap (no spend), `snapshot("gap")`, `done(true)`.
- **Proof.** Headers `-- test_construction_placer_wall`,
  `-- test_construction_placer_wall_atomic_spend`,
  `-- test_build_picker_includes_wall`,
  `-- test_build_wall_segment_tip_and_gap` and
  `-- test_build_wall_preview_matches_commit` and
  `-- test_build_wall_first_must_touch_structure` in `artifacts/verify.log` with no
  `FAIL` after them. Drive snapshots `01-start`, `02-first-block`, `03-chain`,
  `04-gap` under `--display`.

## Gotchas

- Placement must go through `ConstructionPlacer`; do not paint palisade cells
  from the UI layer.
- Preview green cells and cost must match what `commit` places; a gap or
  diagonal off the tip spends nothing.
- Do not show the Wall icon while multiplayer is on; peer sync of walls is
  #278.
- No gates in this slice; plain `PALISADE_*` only via `WallSolver`.
- Drive evidence closes the default-open MinimapPanel (M in play) so the
  wall chain and gap tint are not covered by the mist panel.
