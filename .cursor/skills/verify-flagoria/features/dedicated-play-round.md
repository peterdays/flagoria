# Dedicated cut-and-hit round

Drive: drives/dedicated_play/play_client_a.gd

Two clients on a dedicated `-- --server` host, in the generated spawn chunk. The server has no `World/1`. Client A chops one plant; A receives the wood and both clients see that plant removed. A then kills one mob with the sword; B sees the hurt state and the death. Walking to the mob is only how A reaches sword range. Movement sync itself stays in `test_two_player_smoke` and is not repeated here.

This is not the listen Host/Join pair. That pair clicks Host and is [Two-player Host/Join](./two-player-host-join.md). These drives click Join against a dedicated server.

## Sub-features

- `ds-round-spawn` the dedicated host's player list has no `1`, and each client sees the other client's player.
- `ds-round-cut` A cuts one tree or bush through the normal chop. A's wood goes up by that plant's yield. B's wood stays 0, because inventory is not synced. Both clients' maps drop the plant and record the cut.
- `ds-round-hit` A swings at one mob the server spawned inside the spawn chunk. Both clients see that mob hurt and then dying.

## How to get to it (user POV)

- One process: `godot --headless --path . -- --server` (or the server drive below, seed 5).
- Two others: Main Menu Join, address blank (`localhost:9786`). Chop a plant near spawn, then swing at the nearest mob.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Nothing else is using UDP 9786. Time cost: the headless round is about 6–8 s (worst 6.3 s across 3 runs). The three-launch drive keeps the server up for 110 s so both clients can finish.

- **Run (headless).** `godot --headless --path . --script res://tests/run_tests.gd -- --only=dedicated_play_round`. Three passes before Ready: `python3 tools/stress_netcode.py -n 3 --only=dedicated_play_round`.
- **Proof.** `PASS test_dedicated_play_round (...)`. It fails if the server has a player `1`, if either client misses the other's player, if the plant is not drawn and then removed on both clients, if A's wood is not the plant's yield, if B's wood changes, or if either client misses the hurt state or the death.
- **Drive (three launches, not run in CI).** The drives live in `drives/dedicated_play/`, which `verify-drive.yml` does not start alone. Seed 5 puts a bush and a slime in the spawn chunk. Start the server, then B, then A, each with its own launch:
  ```bash
  bin/launch.sh drives/dedicated_play/play_server.gd --seed 5 &
  sleep 4
  bin/launch.sh drives/dedicated_play/play_client_b.gd --display &
  sleep 4
  bin/launch.sh drives/dedicated_play/play_client_a.gd --display
  wait
  ```
  Each client snapshots `joined`, `after-cut`, and `after-hit`.
- **Screens.** Both clients show two heroes and no server hero. After the cut, the plant near spawn is a stump and A's wood has increased. After the hit, the mob is hurt or gone on both clients.

## Gotchas

- The dedicated host decides the cut from the generated map, so it does not need a drawn chunk or a starting castle. Do not treat a listen-host smoke as this round.
- B does not see A's wood count. The yield is A's inventory. The shared observation is the plant leaving the map.
- A mob outside the spawn chunk is out of scope. Seed 5 keeps the target inside the chunk the clients generate around themselves.
