# Footprint rotation

Drive: drives/footprint_rotation.gd

While placing a footprint structure (the wooden tower today), interact mode
shows a round Rotate control beside the placement preview. Each tap turns the
footprint 90° clockwise; green/red cells, wood cost and refusal reasons follow
the rotated shape. Committing writes that rotation on the placement so saves
and join sync restore it (#493).

## Sub-features

- `footprint-rotate-preview` the Rotate button uses `RoundHudStyle`, sits next
  to the preview, and steps rotation 0→3 then wraps.
- `footprint-rotate-place` `StructurePlacer` stores `rotation` quarter turns with
  each placement; `can_place` and previews use `Structure.rotated`.
- `footprint-rotate-save` `StructureSaves` persists non-zero `rotation` on the
  anchor cell entry in `world.structures`.

## How to get to it (user POV)

1. Start a local game with at least 10 wood.
2. Enter interact mode, open Buildings, choose Tower.
3. Touch the map to preview the 3×3 footprint; the Rotate disc appears beside
   the finger. Tap it to turn the preview, then lift to place.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: three headless tests
`test_structure_rotation_four_turns` (~0.02 s), `test_structure_rotation_blocked`
(~0.4 s) and `test_structure_rotation_save_roundtrip` (~0.5 s) in
`tools/verify.sh`; drive `footprint_rotation` about 12 s under xvfb.

- **Run (headless).** `--only=structure_rotation_four_turns,structure_rotation_blocked,structure_rotation_save_roundtrip`, or full `tools/verify.sh`.
- **Proof.** Those three headers in `artifacts/verify.log` without `FAIL`.
  Drive snapshots `preview-0`, `preview-90`, and `placed-two` phone PNGs
  (two towers at rotation 0 and 90°; wooden tiles are symmetric so a rotated
  marker sprite shows facing).

## Gotchas

- Rotation applies to footprint tools only (Tower today); planks and walls keep
  drag direction. Rotation resets when the tool changes or interact mode closes.
- `Structure.rotated` returns a copy; the cached `tower_wood` definition must
  not be mutated in place.