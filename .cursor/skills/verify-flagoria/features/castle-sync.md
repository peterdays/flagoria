# Castle sync

Drive: drives/castle_sync.gd

In a two-player game the host owns castle placement and ownership (#278).
The host's starting castle is placed while it is still alone and travels with
the map. When a peer joins, the host places that peer's castle outside the
shared spawn disk, so players still gather beside the host's gate. The castle
is sent to peers already connected, and a peer that joins later receives every
castle and its owner. The flag is blue for the host and red for every other
peer. A client cannot place a castle itself.

## Sub-features

- `castle-pair` after the first client joins, the host and the client each
  hold two castles: the host's, owned by peer 1, and the client's, owned by
  the client's peer id. Every footprint cell matches, including a blocking
  wall, and the flag atlas is the owner's colour.
- `castle-late` a third peer receives those two castles plus the castle the
  host places for them. The first client receives that third castle by
  broadcast. All three peers report the same cells and owners.

## How to get to it (user POV)

1. Host a game. The player stands outside the blue castle's gate.
2. Join from a second peer. A second castle appears, with a red flag, and
   both peers see both castles. The joiner still starts beside the host's gate.
3. A peer that joins after that sees both castles and gets one of their own.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: `test_castle_owners_two_players`
about 8–15 s alone with `--only=` (three Godot peers). In the Netcode stress
job it is one scenario at that job's tier (5 or 20). The drive is about 20–40 s
under xvfb. `test_castle_sync_join` already in `tools/verify.sh` also checks
the host castle's cells and the joiner's spawn.

- **Run (headless).** `godot --headless --path . --script res://tests/run_tests.gd -- --only=castle_owners_two_players`, or the full `tools/verify.sh`.
- **Proof.** `PASS test_castle_owners_two_players`, with no `FAIL` after it. The test fails unless the first client and the host share two castles with owners 1 and the client's peer id, flags blue and red, and a blocking cell on each, and a late joiner matches a three-castle list that also includes a castle owned by the late joiner.
- **Drive (live).** `bin/launch.sh drives/castle_sync.gd --seed 7 --display`. It hosts, a client joins, and the drive snapshots `host-castles` on an 854×480 phone window (both flags in view). The client writes `client-castles.png` in the same evidence directory, the joiner's view of those castles.

## Gotchas

- Inventories stay local. The starting castle is free. The host does not charge wood.
- The shared spawn does not move. A joining castle's footprint stays `SPAWN_KEEP` (6) cells off that spawn, so the spawn-radius checks still hold.
- A client must not call `place_structure` for a castle. The host uses `place_for_peer`, then `publish_structure`.
- `apply_structure` ignores a castle the peer already has at that anchor, so the join snapshot and the broadcast do not stack two copies.
- A castle can clear trees inside the mob scan. When the opening set is still intact and no player body exists yet, the host replans it so a joiner's mobs match that map. A set that already lost a mob stays as it is.
