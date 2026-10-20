# Audio

## Buses and volume

`default_bus_layout.tres` defines `Music` and `SFX` buses, both sending to
`Master`. Game sounds (footsteps, combat) play on `SFX`. The `AudioSettings`
autoload (`Scripts/audio_settings.gd`) keeps a 0..1 volume per bus (defaults:
Music 0.6, SFX 1.0). It applies the volume as `volume_db = linear_to_db(v)`,
mutes the bus at 0, and saves to `user://audio_settings.cfg`. Saved values
that are not finite numbers, or are negative, load as the default; values
above 1 are clamped. The main menu has a slider and a percent label for each
bus.

New sounds should use `SFX` (or `Music` for music) rather than `Master`, so
the sliders cover them.

## Music

The `MusicPlayer` autoload (`Scripts/music_player.gd`) plays looping music
on the `Music` bus, on this client only. Nothing is networked. Tracks:

- **Menu:** `MENU_TRACK`, Ninja Adventure "5 - Peaceful". Started by the
  main menu.
- **Game:** `GAME_TRACK`, "4 - Village". Started by Host and Join.

`play(track)` crossfades over 1.5 s on two players. Asking for the track
that is already playing does nothing, so menus and scene reloads never
restart or double it. A dedicated server stops the music.

## Sounds

Sounds live under `art/audio/sfx/<group>/<name>_NN.wav`, credited in
`art/audio/CREDITS.md`. `Scripts/footsteps.gd` and `Scripts/combat_sfx.gd`
play them from the player scene.

Two checks catch a sound that is not heard: one in the running game, one in the
Android build.

## In-game check: `tools/audio_check.gd`

`tools/verify.sh` runs it, locally and in CI:

```sh
godot --headless --audio-driver Dummy --path . --script res://tools/audio_check.gd
```

It resets the volumes to their defaults without saving, loads the real main
and player scenes, and runs a timeline: idle, walk on
grass, sand and swamp, swing, damage, kill. It records the mixer output
while it runs. Headless Godot uses the Dummy audio driver, which still mixes
in real time, so no sound card or display is needed.

- **Recording:** an `AudioEffectCapture` on Master records the full mix,
  after every bus volume, mute and effect. Godot applies Master's own volume
  and mute after its effects, so the check applies them to the recording.
- **Per-sound probes:** each sound player gets a probe bus with its own
  capture, routed to the bus the player already used. A sound that is silent
  on its own is caught even when another sound plays at the same moment.
- **Event log:** each start of a sound player (the rising edge of `playing`)
  is logged with its time, sound, file and player.

It fails (exit 1) when:

- a step's sounds do not start exactly the expected number of times. This
  covers a sound that is unwired or plays twice;
- a logged sound is quieter than -50 dBFS on its own probe within 0.25 s of
  starting. This covers volume -80, an empty stream, or a player out of
  earshot;
- a step with sounds has a Master RMS outside -50..-6 dBFS. This covers a
  muted or -80 dB bus;
- the last 0.35 s after a step is not silent (peak above -60 dBFS), or a
  step marked `audible: false` is not silent. The `swing_sfx_off` step sets
  the SFX slider to 0 and expects the swing to start but be silent on
  Master. `music_slider_off` does the same for the Music slider and a
  track;
- the Master peak reaches 0 dBFS (clipping). The `music_with_swing` step
  mixes music and SFX to cover this;
- a sound file is missing: the `preload` fails to compile, and verify.sh
  treats script errors as failures.

Outputs go to `artifacts/out/`. CI uploads them as the `audio-check`
artifact.

- `audio_check.wav`: the Master mix.
- `audio_check_events.json`: the event log, step windows and failures.
- `audio_check.png`: the waveform. Sound steps are green, silent windows are
  grey, and logged starts are red ticks.

## APK check: `tools/check_apk_audio.sh`

The android-apk workflow runs it on the exported APK:

```sh
./tools/check_apk_audio.sh Builds/android/flagoria-debug.apk
```

It collects every `res://…(.wav|.ogg|.mp3)` path referenced by game scripts,
scenes and resources, leaving out `tools/` and `tests/`. For each path the
APK must contain:

- `assets/<path>.import`;
- a non-empty `assets/.godot/imported/<file>-<hash>.sample`, `.oggvorbisstr`
  or `.mp3str`.

## Adding a sound and its check

1. Add the files under `art/audio/sfx/<group>/` with an `_NN` suffix, and
   credit them in `art/audio/CREDITS.md`. Commit the generated `.import`
   files.
2. Play them from game code, for example as a `preload` in the script that
   owns the `AudioStreamPlayer`/`AudioStreamPlayer2D`. The APK check picks up
   any `res://` path in game code automatically.
3. Add a step to `TIMELINE` in `tools/audio_check.gd`. Give it a name, an
   action, a duration, and `expect`: the sound name (file name without
   `_NN.wav`) mapped to the exact number of starts. If no existing action
   triggers the sound, add a branch in `_begin_step` that calls the same game
   path a player would use (input handler, RPC body, signal callback), not
   `play()` directly.
4. Sound players on the two test players and the `MusicPlayer` players are
   probed automatically. For sounds elsewhere (UI, world objects), call
   `_add_probe(node)` for their players in `_setup`. A step with
   `"music": "GAME_TRACK"` plays that `MusicPlayer` constant for the step.
5. Run `./tools/verify.sh` and look at `artifacts/out/audio_check.png`.
