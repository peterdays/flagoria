# Netcode stress tiers (CI)

Drive: not player-facing

The required check **Netcode stress** (`.github/workflows/play-review.yml`) runs `tools/stress_netcode.py` when `tools/play_review_paths.py` sets `run_stress=true`: a gameplay change, or a change to the stress runner, the stress lint, `tests/net/`, or a `tests/*_probe.gd` probe. How many times each multiplayer scenario runs is chosen in that script (`FULL_RUNS`, `LIGHT_RUNS`, `stress_tier()`). Do not change default run counts in the workflow; set `STRESS_RUNS` from that script's output only.

Pull-request workflows classify changes once per job through `.github/actions/classify-change`, which runs `play_review_paths.py` and exposes `gameplay` and `stress_runs` outputs. `play-review-label.yml` uses the same composite with paths read via the API (no checkout of PR code).

## When the job is skipped

The change is not gameplay and it does not touch the stress matrix: no changed path matches `GAMEPLAY` or `STRESS_MATRIX` in `play_review_paths.py`, and the pull request does not carry `needs-play-review` (the label workflow adds it when gameplay paths match). The workflow still checks out the repo, runs `python3 tools/play_review_paths.py --self-test`, and classifies paths; install Godot and stress are skipped. Wall time is on the order of tens of seconds.

`STRESS_MATRIX` is the stress runner (`tools/stress_netcode.py`), the stress lint and its allow list, `tests/net/*`, and `tests/*_probe.gd`. Those paths are not player-facing gameplay, so they do not add the label, a drive, or a debug APK. They do run the full matrix, so a broken runner or probe fails on the pull request that changed it.

## 5 runs per scenario (`LIGHT_RUNS`)

- GitHub `event` is `pull_request` (not a push to `main`).
- At least one gameplay path changed (or `needs-play-review` is present).
- No file in `NETCODE` changed.
- For each changed `NETCODE_MIXED` file, no added/removed line in the PR diff matches `NET_LINE` (RPCs, peers, authority, synchronizers, and the other tokens in `play_review_paths.py`).

Typical job time is a few to about ten minutes, depending on scenario count.

## 20 runs per scenario (`FULL_RUNS`)

Any of:

- GitHub `event` is `push` to `main` and the push includes gameplay paths (main always gets the full tier when stress runs).
- Any changed path matches `NETCODE` (spawners, score sync, and every `STRESS_MATRIX` path: the runner, the lint, `tests/net/*`, and `tests/*_probe.gd`).
- A changed `NETCODE_MIXED` file has at least one changed line matching `NET_LINE` in the PR diff.

If `stress_tier()` is called without `--diff`, any changed `NETCODE_MIXED` path counts as netcode (used in self-tests and anywhere diff is not passed). CI on pull requests always passes `--diff`.

## Local runs

`python3 tools/stress_netcode.py` defaults to 20 runs (`STRESS_RUNS` or `-n`). That default is for local stress, not the CI tier rules above.

## Writing netcode stress scenarios

Scenarios must be deterministic: a fixed world seed, no sleep-based timing, and a wait on explicit host or peer state with a bounded timeout. Each run has a 60 s budget (`--timeout` on `tools/stress_netcode.py`). The job stops at the first run that fails and names the scenario, the run index, and the time. It keeps the pass-rate table for whatever finished and does not start the rest.

A single flaky run otherwise shows up only after every scenario has finished, which costs about 30 minutes of CI. `tools/stress_scenario_lint.py` rejects a bare sleep or an unseeded random call in a scenario or its probe; it runs from `tools/verify.sh`. See [AGENTS.md](../../../AGENTS.md#writing-netcode-stress-scenarios).

## Proof

- `python3 tools/play_review_paths.py --self-test` includes tier cases for both `FULL_RUNS` and `LIGHT_RUNS`.
- Required check name stays **Netcode stress**.
