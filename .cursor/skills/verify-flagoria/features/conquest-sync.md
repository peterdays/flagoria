# Conquest sync (towers and flag captures)

Drive: drives/tower_capture.gd

In a two-player game the host owns tower placement, capture progress and
flags-held points (#497). A client's tower is a request. The host checks the
placer is alive and in reach, checks the footprint the way solo play does,
writes the tower, charges the placer and tells every other peer. A refused
request leaves no tower and does not change the client's wood. Capture
progress and the owner change only on the host; every peer, including one
that joins during a capture, shows the same owner and progress. With land
score off, the host awards one point per owned flag tower and both peers'
totals match. Land score is the live conquest total
([Land score](./land-score.md)).

`StructureRequests` is the one host-request pipeline. Walls are a second
kind on it (#498).

## Sub-features

- `tower-shown` the Tower tool stays visible while a peer is connected. Wall
  is shown too (#498).
- `tower-request` the client sends `request_place`; the host writes with
  `place_from_host` and the client spends 10 wood only after `receive_charge`.
- `tower-refused` a tower on water is refused. The client's `Inventory.WOOD`
  stays where it was. No ghost tower appears.
- `capture-progress` the host calls `TowerCapture.tick`. A client does not
  advance. After 8 ticks of 0.5 s the progress is 4 and the owner is unchanged;
  2 more ticks hand the tower over and clear the progress.
- `flags-held-sync` the host's `FlagsHeldPoints.tick` awards the castle and
  the new tower. Both peers report the same totals.
- `late-join` a peer that joins after the place, or during the capture, matches
  the host's towers, owners, progress and points.

## How to get to it (user POV)

1. Host a game and join from a second peer.
2. On the joiner, open Buildings. Tower is shown; Wall is not.
3. With 10 wood, place a tower on clear land. Both peers see it in the
   builder's colour. The builder's wood drops by 10. A bad footprint does not.
4. The other player stands on the flag alone. The bar fills on both peers and
   the flag changes hands after 5 s. The score on both peers counts the flags
   the host awarded.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: `test_tower_place_two_players`
about 8–15 s alone with `--only=` (three Godot peers); `test_tower_capture_two_players`
about 10–20 s alone. In the Netcode stress job each is one scenario at that
job's tier (5 or 20). The drive is about 20–40 s under xvfb. The picker and
placer tests already in `tools/verify.sh` add nothing new there.

- **Run (headless).** `godot --headless --path . --script res://tests/run_tests.gd -- --only=tower_place_two_players,tower_capture_two_players`, or the full `tools/verify.sh`.
- **Proof.** `PASS test_tower_place_two_players` and `PASS test_tower_capture_two_players`, with no `FAIL` after them. The place test fails unless the refused request leaves the client on 10 wood, the accepted tower is owned by the builder's peer id on every peer including a late joiner, the host's total is one point for its castle, and the builder's total is one point for their castle plus one for the tower. The capture test fails unless 8 ticks of 0.5 s leave progress 4 and the builder as owner on the host, the client and a late joiner, and 2 further ticks make the owner the host and the progress 0 on all three.
- **Drive (live).** `bin/launch.sh drives/tower_capture.gd --seed 7 --display`. It hosts, a client builds a tower through the request path and steps aside, the host runs one capture, and the drive snapshots `tower-tool` (Tower visible with a peer connected) and `host-captured` (the flag now the host's). The client writes `client-captured.png` in the same evidence directory.

## Gotchas

- Inventories stay local. The host charges the placer with `receive_charge` after it accepts, the same as a plank. It does not spend the host's wood for a client's tower.
- `StructurePlacer.can_place` still says `multiplayer on`. Clients must not call `place_structure` for a tower. The host uses `place_from_host`.
- Walls are a request on `StructureRequests`, not a new pipeline (#498).
- The drive parks mobs and calls `TowerCapture.tick` for exactly 5 s so a wanderer cannot contest the flag and the capture does not depend on the body staying inside the ring.
