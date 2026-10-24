# Audio

Music loops in the menu and in game, and combat and footstep sounds play on the SFX bus. Music and SFX volumes are set from the main menu and persist.

## Sub-features

- `audio-buses` Music and SFX buses under Master (`default_bus_layout.tres`), sliders persisted in `user://audio_settings.cfg`.
- `audio-music` looping menu and game tracks (`Scripts/music_player.gd`).
- `audio-sfx` swing, hit, hurt and kill sounds (`Scripts/combat_sfx.gd`).
- `audio-footsteps` per-terrain footsteps (`Scripts/footsteps.gd`).
- `audio-check` in-game check that every wired sound is heard (`tools/audio_check.gd`, run by verify.sh).

## How to get to it (user POV)

- Main Menu sliders **Music** and **Sound effects**; then Host and move or attack.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`.

- **Run.** Run `./.cursor/skills/verify-flagoria/bin/drive-verify.sh` (or `./tools/verify.sh`) and read `artifacts/verify.log`.
- **Proof.** Each header `-- test_combat_sfx`, `-- test_footsteps`, `-- test_audio_settings`, `-- test_music_player` appears in the log, no `FAIL` line follows it, and the run ends with `All tests passed.` and `Verification passed.`

## Gotchas

- verify.sh also runs `tools/audio_check.gd` with the Dummy driver and requires `AUDIO_CHECK_OK`; its recording goes to `artifacts/out/audio_check*` (see `docs/audio.md`).
- Bus mix and volumes are taste calls; do not retune them in a verification change.
