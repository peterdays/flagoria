# Walls and cities sync

Drive: drives/walls_cities.gd

In a two-player game the host owns free-form walls and city formation (#498).
The Wall tool stays visible. A client's wall drag is a request on
`StructureRequests`. The host checks reach and the solo footprint, spends wood
with the solo rules, writes the chain and sends the free-form cells plus the
solved auto junction cells. Connecting pieces match on every peer. `Cities.tick`
runs on the host. A closed loop around a flag tower, and the loss of that loop,
are sent to every peer. A late joiner receives the same walls, auto junctions
and cities.

## Sub-features

- `wall-shown` the Wall tool stays visible while a peer is connected.
- `wall-request` the client sends `request_place` for `wall_block`. The host
  writes with `write_wall` and the client spends 2 wood per cell only after
  `receive_charge`. A water cell is refused and the client's wood stays put.
- `wall-pieces` the placed cell's palisade piece and collar caps match on the
  host, the client and a late joiner, and so do the auto junction tile names.
- `city-host` `Cities.tick` on the host adds the tower's city when the client
  closes the loop. Both peers report the same cities keys. Erasing one ring
  cell drops that key on the host, the client and a late joiner.
- `late-join` a peer that joins after the place matches the host's free-form
  walls, auto junctions and cities.

## How to get to it (user POV)

1. Host a game and join from a second peer.
2. On either peer, open Buildings. Wall is shown.
3. With wood, drag a wall that 4-touches the castle or a tower. Both peers
   see the same pieces. The builder's wood drops by 2 per cell. A cell on
   water does not.
4. Close a loop around a flag tower. The tint appears on both peers. Open a
   gap and that city goes away on both.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: `test_wall_place_two_players`
about 8–15 s alone with `--only=` (three Godot peers); `test_city_change_two_players`
about 12–25 s alone. In the Netcode stress job each is one scenario at that
job's tier (5 or 20). The drive is about 20–40 s under xvfb.

- **Run (headless).** `godot --headless --path . --script res://tests/run_tests.gd -- --only=wall_place_two_players,city_change_two_players`, or the full `tools/verify.sh`.
- **Proof.** `PASS test_wall_place_two_players` and `PASS test_city_change_two_players`, with no `FAIL` after them. The wall test fails unless a water request leaves the client on 4 wood, the accepted cell is one connecting palisade with a collar, and the free-form pieces, caps and auto junction names match on the host, the client and a late joiner. The city test fails unless the client's closed loop puts the same cities keys on both peers, a late joiner matches those keys and the walls, and opening one ring cell removes that tower's city on all three.
- **Drive (live).** `bin/launch.sh drives/walls_cities.gd --seed 11 --display`. It hosts, shows the Wall tool with a peer connected, a client closes a loop through the request path, and the drive snapshots `wall-tool` and `host-city`. The client writes `client-city.png` in the same evidence directory.

## Gotchas

- Inventories stay local. The host charges the placer with `receive_charge` after it accepts. It does not spend the host's wood for a client's wall.
- A client must not call `place_wall_cells`. The host uses `write_wall`, then `apply_wall_state`.
- Auto junction cells are `StructurePlacer` auto cells. The snapshot sends each solved tile name so a late joiner matches the host even when the chunk is drawn later.
- `Cities.tick` on a client does not rebuild and does not clear the host's list.
