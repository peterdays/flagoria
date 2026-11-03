# Structures (data format)

Small hand-drawn structures (guard post, wall piece, camp) are stored as plain text in the `flagoria-structure 1` format: a header, one legend, then a `ground` and an `object` layer, up to 16 x 16, with tiles named by `TileCatalog`. `structures/guard_post.txt` is the first one and `structures/castle.txt` the starting castle. Legend attributes: `auto` (wall pieces from `WallSolver`), `team` (the owner's flag colour) and `open` (the gate is drawn open). Placing a parsed structure on the map is covered in [Structure placement](./structure-placement.md).

## Sub-features

- `structure-parse` `Structure.parse` (`Scripts/mechanics/structures/structure.gd`) accepts pasted text leniently and gives one error naming the problem for each broken variant of the guard post (unknown tile, bad size, tile outside the layer's palette).
- `structure-text` `to_text()` is canonical: `parse(text).to_text() == text` for every canonical file.
- `structure-export` every Android export preset includes `structures/*.txt`, which `all_resources` would leave out of the APK.

## How to get to it (user POV)

- Read or paste a file under `structures/`. In game only `structures/castle.txt` is placed, as the [starting castle](./start-castle.md).

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: under 0.2 s in `tools/verify.sh` (~1.3 s alone with `--only=`).

- **Run.** `./.cursor/skills/verify-flagoria/bin/drive-verify.sh` and read `artifacts/verify.log`.
- **Proof.** Headers `-- test_structure_round_trip`, `-- test_structure_lenient_paste`, `-- test_structure_rejects`, `-- test_structure_export_filter` with no `FAIL` after them.
- **Drive (live).** Host from the main menu and see the starting castle.
