# Tower capture

Flag towers change hands (#274). Every placement with a `team` flag (the castle's main tower, a guard post) is a tower. `TowerCapture` (`Scripts/mechanics/conquest/tower_capture.gd`, the `World/TowerCapture` node in `flagoria_main.tscn`) checks each tower every physics tick. Living players count for their peer id. Mobs that are not dying count for the mobs (`StructurePlacer.OWNER_MOBS`, -1). Only those within `CAPTURE_RADIUS` (32 px, two cells) of the flag cell's centre take part. When progress reaches `CAPTURE_TIME` (5 s), `StructurePlacer.set_owner` hands the tower over: the placement's `owner` entry and its flag tile change, nothing else. Flags: host blue, other peers red, neutral grey (`OWNER_NEUTRAL`, 0), mobs purple; the neutral and mob flags are placeholders drawn by `tools/art/gen_flag_tiles.py`. A bar above the flag shows progress in the capturing side's colour. Capture runs only offline or on a host that is still alone; live capture sync is #278.

## Sub-features

- `capture-completes` one other side alone inside the area takes the tower in exactly 5 s, not one tick sooner; the owner becomes that peer and the flag is redrawn red. Standing just outside the circle starts nothing.
- `capture-defender-pauses` a living player of the owner's side inside pauses the progress, even with the attacker still in.
- `capture-drains` with the area empty, progress drains at the capture rate down to 0. A different lone side first drains the old side's progress, then builds its own.
- `capture-contested` two other sides inside (two peers, or a peer and a mob) freeze the progress.
- `capture-dead-players` a dead player counts for no side: it neither captures nor defends.
- `capture-mob` a mob standing in the area takes the tower for the mobs (purple flag); a dying mob does not count. Mobs do not seek towers yet (#280); they count when they wander or chase in.
- `capture-owner-and-flag-only` a capture changes the placement's owner and its flag cell only (every other footprint cell on every layer, the name and the anchor stay), `predict_cell` gives the new flag, and the new owner survives `structures_for_sync` → `replace_structures`, the copy a joining peer gets.
- `capture-off-in-multiplayer` while multiplayer is on (a connecting client in the test) no tower moves; back offline it runs again.

## How to get to it (user POV)

- Main menu → Host, then walk into the castle courtyard: nothing happens, the host owns it. A tower changes hands only when someone else or a mob stands by its flag, so a solo session sees a capture only when a mob wanders or chases into the courtyard and stays for 5 s (the flag turns purple).

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: the eight tests in `tests/mechanics/conquest/test_tower_capture.gd` take about 1 s together in `tools/verify.sh` (about 0.12 s each; ~2.5 s alone with `--only=` for all eight, against ~1.5 s for runner start-up). They call `TowerCapture.tick` by hand with a 0.125 s step, so no test waits on real time.

- **Run.** `./.cursor/skills/verify-flagoria/bin/drive-verify.sh` and read `artifacts/verify.log`.
- **Proof.** Headers `-- test_tower_capture_completes`, `-- test_tower_capture_defender_pauses`, `-- test_tower_capture_drains_when_empty`, `-- test_tower_capture_contested`, `-- test_tower_capture_dead_players`, `-- test_tower_capture_mob`, `-- test_tower_capture_changes_owner_and_flag_only`, `-- test_tower_capture_off_in_multiplayer` with no `FAIL` after them.
- **Drive (live).** Host from the main menu, lure a mob into the castle courtyard and leave it there: the purple bar fills in 5 s and the flag turns purple. Step back in and the next capture needs your side to be the only one inside.
- **Look.** `docs/screenshots/tower-capture.png` shows the four flag colours and two bars (red over the host's tower, purple over a neutral one).

## Gotchas

- Placements, and so captured owners, are not saved to disk yet; a reloaded world places the castle again for the host (#42).
- While multiplayer is on, progress stays where it was and the bars stay up; nothing syncs to peers yet (#278).
- A side is a player node's name as a peer id; player bodies whose name is not a number are ignored.
