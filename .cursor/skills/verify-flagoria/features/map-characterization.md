# Map characterization

Map characterization pins procedural tile output for fixed seeds so parameter changes show up as failing atlas expectations.

## Sub-features

- `map-fixed-seeds` applies fixed `MapGenParams` seeds to `World/worldMap`.
- `map-generate-chunk` calls `generate_chunk` at a fixed position.
- `map-atlas-assert` compares layer 0 and layer 1 atlas coords at sampled cells.

## How to get to it (user POV)

- Indirect: run `./tools/verify.sh` (or `bin/drive-verify.sh`). When this checkout includes the characterization test in `tests/run_tests.gd`, the runner prints `PASS test_map_characterization`.
- There is no separate in-game menu for the golden check; it is CI/agent facing.

## Driving it with verify-flagoria helpers

Preconditions:

- `doctor.sh` exits `0`.
- Prefer a checkout where `tests/run_tests.gd` contains `test_map_characterization` (merged map golden). If doctor reports smoke-only, record that the golden assert is not in this tree and do not claim atlas pinning.

- **Run verify.** `./.cursor/skills/verify-flagoria/bin/drive-verify.sh`.
- **Observe.** Log line `PASS test_map_characterization` (and cell count) when the test is present; otherwise only `PASS test_smoke_true`.
- **Mutation proof (optional, revert after).** Temporarily change a terrain threshold default (for example `water_max_alt` on `MapGenParams`), re-run the test script, expect a `FAIL cell=...` line and non-zero exit, then revert the edit and confirm verify passes again.
- **Proof.** Excerpt of PASS/FAIL lines in `artifacts/verify.log` or `artifacts/e2e-summary.txt`.

## Gotchas

- Seeds must be non-zero before `ensure_seeds` / `apply_map_params`, or random seeds replace zeros and the golden drifts.
- Characterization instances the main scene; first-frame `add_child` timing issues belong in product code, not in weakening the assert.
- Do not update expected atlas values without an intentional generator change and a why/what note.
