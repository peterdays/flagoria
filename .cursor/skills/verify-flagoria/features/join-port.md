# Join an address with an optional port

Drive: drives/join_port.gd

Main Menu Join accepts a hostname or an IPv4 address, with an optional `:port`. The default port is UDP `9786`. A blank field joins `localhost` on that port. `127.0.0.1:9799` and `localhost:9799` dial port 9799, and the typed text stays in the address field and in `Could not join …`. `:9799`, `host:`, `host:abc`, port `0` and port `65536` are rejected on the menu before any connection attempt. Port `1` is valid: with nothing listening, the menu shows `Could not join 127.0.0.1:1`. An address with more than one colon, such as `::1`, is rejected instead of being split into a host and a port.

## Sub-features

- `join-port-default` blank, `127.0.0.1`, `localhost` and `my-host.local` use port `9786`.
- `join-port-explicit` `host:port` is the host and port passed to `create_client`. The field is not rewritten.
- `join-port-reject` a missing host, a non-numeric port, a port outside 1–65535, or more than one colon shows a menu error and does not dial.
- `join-port-timeout` `127.0.0.1:1` with nothing listening returns `Could not join 127.0.0.1:1`.

## How to get to it (user POV)

- Launch, leave the address blank, press Join: the client dials `localhost` on UDP `9786`.
- Or type `127.0.0.1:9799` (the letter keyboard already has `:`) and press Join to reach a dedicated server that was started with `--port 9799`.
- A bad address stays on the menu with the error under the field. The typed text is kept.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: `join_port_button` ~4 s in verify (one ~3 s no-listener wait); `join_port_dedicated` ~5 s in verify and ~5 s × 20 in netcode stress (4 at a time). Live drive ~10 s.

- **Run (headless).** `godot --headless --path . --script res://tests/run_tests.gd -- --only=join_port_button,join_port_dedicated`, or full `tools/verify.sh`. Both tests call `MainMenu._on_join_button_pressed`.
- **Drive (live).** `bin/launch.sh drives/join_port.gd --display` (## launch: --seed 42). The drive starts dedicated servers on loopback `9786` and `9799`, clicks Join with a blank address, returns to the menu, types `host:abc` and `127.0.0.1:1` and `127.0.0.1:9799`, and clicks Join each time. Snapshots: `default-address`, `joined-default`, `invalid-address`, `join-timeout`, `joined-9799`.
- **Proof.** Headers `-- test_join_port_button` and `-- test_join_port_dedicated` with no `FAIL` after them. The drive log has `join_port: default host=localhost port=9786`, `join_port: invalid`, `join_port: timeout status='Could not join 127.0.0.1:1'`, and `join_port: explicit host=127.0.0.1 port=9799`, and both joins show a player under `World`. The `9786` listen-server pair in [Two-player Host/Join](./two-player-host-join.md) is unchanged.

## Gotchas

- IPv6 is not accepted. `::1` is an unsupported address, not host `:` and port `1`.
- The client peer timeout is capped (`set_timeout(8, 800, 3000)`), so the port-1 case fails in about 3 s.
- The drive binds UDP `9786` and `9799` on loopback. Run one copy at a time, and not beside the two-player pair.
