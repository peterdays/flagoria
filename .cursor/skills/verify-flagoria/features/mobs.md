# Mobs

Drive: not player-facing

Slimes, crabs and piglets are placed from the world seed, wander near home, chase the nearest player, hurt on contact and die to sword hits. The host runs them and peers see the same mobs.

## Sub-features

- `mob-plan` seeded placement (`Scripts/mob_spawner.gd`): at 1x one mob per `CELLS_PER_MOB` (300) island cells, up to `MAX_PER_ISLAND` (3) per island and `MAX_MOBS` (10) in all, none within `SAFE_RADIUS` (6) cells of the player spawn, crabs only on beaches.
- `mob-rate` the host's Mob spawns slider (`GameSettings.mob_rate`, default 2.0, see [Main menu](./main-menu.md)) divides `CELLS_PER_MOB` and multiplies both caps; a client never spawns mobs from its own rate.
- `mob-wander` idle and walk around home (`Scripts/mob.gd`).
- `mob-chase` chase within `CHASE_RADIUS`, give up past `GIVE_UP_RADIUS` or the home leash.
- `mob-contact` touching a mob costs `CONTACT_DAMAGE` half-hearts.
- `mob-sword` a swing costs a mob 1 HP once per swing, with a hurt window; a second attacker's swing in that window is not used up.
- `mob-art` one sheet path per type in `MobCatalog.TYPES` (`Scripts/mob_catalog.gd`): 8x16 grid of 16x16 frames.
- `mob-sync` mobs replicate to a joining client of a dedicated server.
- `mob-uncharted` a mob is drawn only on ground this peer has generated (#163); it shows in the same frame its chunk is drawn, and a type flagged `visible_in_uncharted` always shows. Hiding never changes its position, state or hurt box.
- `mob-sfx` `Scripts/mob_sfx.gd` plays `notice`, `attack`, `hurt`, `death` and `idle` once per event on each peer (see [Audio](./audio.md)).
- `mob-points` the killing hit pays [Points](./points.md) once for that mob's name. A second award for the same id adds nothing.

## How to get to it (user POV)

- Host a world and walk around the spawn island; mobs are within a few screens.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`.

- **Run.** Run `./.cursor/skills/verify-flagoria/bin/drive-verify.sh` (or `./tools/verify.sh`) and read `artifacts/verify.log`.
- **Proof.** Each header `-- test_mob_predict_matches_chunks`, `-- test_mob_plan`, `-- test_mob_wander`, `-- test_mob_sheet_swap`, `-- test_mobs_sync_to_peer`, `-- test_mob_chase`, `-- test_mob_chase_two_players`, `-- test_mob_contact`, `-- test_mob_contact_two_players`, `-- test_mob_sword`, `-- test_mob_sword_two_players`, `-- test_mob_sword_two_attackers`, `-- test_mob_spawn_rate`, `-- test_mob_hidden_on_uncharted`, `-- test_mob_shown_when_ground_drawn`, `-- test_mob_sfx_clips`, `-- test_mob_sfx_events` appears in the log, no `FAIL` line follows it, and the run ends with `All tests passed.` and `Verification passed.`

## Gotchas

- The `*_two_players` tests start a second headless Godot as a dedicated server on a free UDP port; a blocked loopback port fails them.
- `test_mob_sword_two_players` hosts a pinned map (`MOB_SWORD_SEED`) and swings at its most isolated mob, so no second mob dies to the same swings (#328). A map or spawn change that moves mobs can fail its isolation check; pick another seed then.
- Swapping mob art is a sheet file change; `test_mob_sheet_swap` fails if a texture is put in `Mobs/mob.tscn`. Sheet layout notes live in `art/mobs/README.md`.
