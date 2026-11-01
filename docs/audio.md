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

### Regen tick

`CombatSfx` event `regen` plays `art/audio/sfx/world/regen_tick_01.wav` each
time health regeneration heals the player (`PlayerHealth.healed`, from
`heal()` only; `set_health_now` and a respawn do not fire it). Regen only
heals a hurt, living player, so the tick plays only while recovering. Only
the peer that controls the player plays it, so other players do not hear
someone else heal. Volume is -9 dB, the `hurt` level; the clip itself is
mastered about 10 dB under the other sounds.

### Mob sounds

`Scripts/mob_sfx.gd` (the `Sfx` child of `Mobs/mob.tscn`) plays
`art/audio/sfx/mobs/<type>/<type>_<event>_NN.wav` for slime, crab and
piglet. Each event plays once on every peer, from values the mob already
syncs:

| Event | Hook | Volume |
| --- | --- | --- |
| notice | `state` enters `CHASE` (not the re-chase right after a hit) | -12 dB |
| attack | `attacks` rises; the server adds 1 when contact damage lands | -11 dB |
| hurt | `state` enters `HURT` or `DYING`, via `sword_hit_landed()` | -10 dB |
| death | `state` enters `DYING`, via `sword_hit_landed()` | -9 dB |
| idle | local random timer, 12–30 s, while idle or walking | -12 dB |

- `attacks` is the only new synced value (on change, a few bytes per
  landed hit). `state` was already synced.
- Crab adds +2 dB (`MOB_VOLUME_DB`); its clips are quieter.
- Players are `AudioStreamPlayer2D` on `SFX`, `max_distance` 320 px (just past
  the view edge), so far mobs are quiet or silent.
- A mob that is not visible (for example hidden on uncharted ground) plays
  nothing.
- A late joiner hears nothing for past events: the spawn values are applied
  before the mob is ready.
- `sword_hit_landed()` is the one place a sword hit on a mob is handled; add
  a sword impact sound there.

### Chop sounds

`ChopAction` (`Scripts/mechanics/trees/chop_action.gd`) plays a plant's
sound slots from its `InteractableType` (`data/interactables/*.tres`), on
this client only (chopping is single-player). Each slot has its own
`AudioStreamPlayer2D` on `SFX` at -8 dB, pitch 0.93–1.07, so slots that start
together do not cut each other off. An empty slot plays nothing.

| Slot | Hook | Tree | Bush |
| --- | --- | --- | --- |
| `hit_sounds` | each impact (`chop_hit`) | `trees/tree_chop_01..03`, never the same twice in a row (`hit_no_repeat`) | `bushes/bush_hit_01..03` |
| `hit_layer_sounds` | each impact, with the hit sound | `trees/leaf_rustle_01` | none |
| `last_hit_sounds` | the last impact, with the hit sound | `trees/tree_crack_01` | none |
| `fell_sounds` | the plant becomes its stump, 0.1 s after the last impact; on its own player with `fell_own_player`, else on the hit player (it cuts the last hit off) | `trees/tree_fall_01` (`fell_own_player`) | `bushes/bush_break_01` (hit player) |
| `pickup_sounds` | its yields are added to the inventory | `trees/wood_pickup_01..02` | none |

A chop cancelled before the fall (moving away, leaving interact mode, the
hero dying) plays no fall or pickup sound.

### UI sounds

The `UiSfx` autoload (`Scripts/ui_sfx.gd`) plays `art/audio/sfx/ui/` on the
`SFX` bus, on this client only. Nothing is networked. Scenes do not call it;
they only tag nodes:

| Event | Hook | Volume |
| --- | --- | --- |
| click | any `BaseButton` press (connected when the button enters the tree) | -9 dB |
| back | a press on a button in the `ui_back` group, instead of click | -10 dB |
| menu_open | a Control in the `ui_menu` group becomes visible in the tree | -10 dB |
| menu_close | a `ui_menu` Control stops being visible | -10 dB |
| saved | `MapGen.map_saved`, emitted when `save_map_inputs` succeeds | -10 dB |

- The press sound is connected ahead of the button's own handlers, so it
  starts before a handler that blocks (Host builds the world) or changes the
  scene, and the autoload outlives the scene.
- `UiSfx` keeps running while the game is paused.
- New Back, Close or Cancel buttons join `ui_back`; a new menu panel joins
  `ui_menu`. Sliders and the touch attack button make no UI sound.

Two checks catch a sound that is not heard: one in the running game, one in the
Android build.

## In-game check: `tools/audio_check.gd`

`tools/verify.sh` runs it, locally and in CI:

```sh
godot --headless --audio-driver Dummy --path . --script res://tools/audio_check.gd
```

It resets the volumes to their defaults without saving, loads the real main
and player scenes, and runs a timeline: idle, walk on
grass, sand and swamp, swing, damage, kill, a regen heal on this peer's own
player, then one mob of each type
noticing, attacking, getting hurt, dying, idling and staying silent while
hidden, then a Map settings click, its Back, a `ui_menu` panel opening and
closing, and a map save. It records the mixer output
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
  earshot. Clips mastered quieter on purpose (`QUIET_DB`, the regen tick
  at 10 dB) get a floor that much lower, for this and the step RMS below;
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
   probed automatically, and so are the `UiSfx` players. For sounds elsewhere (UI, world objects), call
   `_add_probe(node)` for their players in `_setup`. A step with
   `"music": "GAME_TRACK"` plays that `MusicPlayer` constant for the step.
5. Run `./tools/verify.sh` and look at `artifacts/out/audio_check.png`.
