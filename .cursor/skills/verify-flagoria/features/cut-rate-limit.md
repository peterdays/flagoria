# Cut request limit

Drive: not player-facing

In multiplayer the host limits how fast each client may ask for cuts (#355). `Interaction.request_cut` (`Scripts/mechanics/interact/interaction.gd`) first takes a token from the sending peer's bucket in `CutRateLimit` (`Scripts/mechanics/interact/cut_rate_limit.gd`) and drops the request, with no reply, when the bucket is empty. That check runs before the cutter lookup, the dead-player check ([Dead player cuts nothing](./dead-player-cut.md)) and the reach check, so a client that floods the host (alive or dead) costs one lookup per request once its bucket is spent. The host's own cuts do not use a bucket. The rest of cut sync is in [Cut sync](./cut-sync.md).

## Sub-features

- `cut-rate-burst` a full bucket holds `BURST` (162) tokens: twice `DRAG_CELLS` (81), the most 16 px cell centres within `Interaction.REACH` (80 px) of one point, so the biggest drag a player can make goes through whole. Once the bucket is spent, a request for a plant in reach is dropped: no stump, no yields.
- `cut-rate-refill` the bucket refills at `RATE` (162.5) tokens a second, up to `BURST`: twice `SWEEP_CELLS` (81.25), the new cells a 2 * `REACH` wide strip brings into reach each second at the keyboard top speed (`MAX_SPEED`, 130 px/s, in `Scripts/player.gd`). A player dragging every frame while walking at top speed through a plant on every cell is never refused; with no headroom (1x) a diagonal walk is refused 25 of 917 requests.
- `cut-rate-per-peer` each peer has its own bucket: a peer that spent its bucket does not hold back another peer's cuts.

## How to get to it (user POV)

- None in normal play: a real client never reaches the limit. It shows only with a modified client that sends many more cut requests than its player could make.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: `test_cut_rate_burst_dropped`, `test_cut_rate_per_peer`, `test_cut_rate_drag_burst` and `test_cut_rate_numbers` add about 0.1 s each to `tools/verify.sh` (each ~2.1-2.3 s alone with `--only=`, against ~1.95 s for runner start-up; all four together ~2.3 s). They run in one process with a `MultiplayerAPIExtension` stand-in and open no network peer, so they add nothing to the Netcode stress job.

- **Run.** `godot --headless --path . --script res://tests/run_tests.gd -- --only=cut_rate_burst_dropped,cut_rate_per_peer,cut_rate_drag_burst,cut_rate_numbers` with scratch `XDG_*` dirs, or `./.cursor/skills/verify-flagoria/bin/drive-verify.sh`.
- **What the tests do.** `tests/net/test_cut_rate.gd` loads the main scene as a host with a stand-in `MultiplayerAPI` (`FakeApi`: peers 2 and 3, RPCs recorded, a chosen sender), puts a cutter node for peers 2 and 3 on two plants near the origin, and pins the limit's clock. The burst test sends `BURST` requests from peer 2 for an empty cell, then one for its plant (dropped), then the same one `1 / RATE` s later (cut). The per-peer test spends peer 2's bucket and has peer 3 cut. The drag test sends `DRAG_CELLS` requests, the last for a plant (cut). The numbers test checks the tile size, recounts the cells in reach over 1/4 px offsets, and walks 10 s at top speed in three directions asking for every cell that comes into reach, every frame, against a fresh limit.
- **Proof.** `PASS test_cut_rate_burst_dropped (162 requests, then 1 dropped)`, `PASS test_cut_rate_per_peer`, `PASS test_cut_rate_drag_burst (81 requests)` and `PASS test_cut_rate_numbers (81 cells in reach, burst 162, 162.5/s)`.

## Gotchas

- `SWEEP_CELLS` uses the keyboard top speed; the touch joystick is slower (60 px/s), so touch play has more headroom.
- A full bucket also absorbs about 1 s of requests that arrive together after a network stall at the worst case (top speed, a plant on every cell); real forests are sparser, so the margin is larger.
- `TILE`, `DRAG_CELLS` and the speed follow the game through `test_cut_rate_numbers`: change the tile size, `REACH` or `MAX_SPEED` and that test fails until the limit's figures match again.
- Buckets are kept per peer id for the session (two floats each); a rejoining client gets a new id and a new full bucket.
