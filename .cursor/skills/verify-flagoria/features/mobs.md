# Mobs

Slimes, crabs and piglets are placed from the world seed, wander near home, chase the nearest player, hurt on contact and die to sword hits. The host runs them and peers see the same mobs.

## Sub-features

- `mob-plan` seeded placement (`Scripts/mob_spawner.gd`): up to 10 mobs, none near the player spawn, crabs only on beaches.
- `mob-wander` idle and walk around home (`Scripts/mob.gd`).
- `mob-chase` chase within `CHASE_RADIUS`, give up past `GIVE_UP_RADIUS` or the home leash.
- `mob-contact` touching a mob costs `CONTACT_DAMAGE` half-hearts.
- `mob-sword` a swing costs a mob 1 HP once per swing, with a hurt window; a second attacker's swing in that window is not used up.
- `mob-art` one sheet path per type in `MobCatalog.TYPES` (`Scripts/mob_catalog.gd`): 8x16 grid of 16x16 frames.
- `mob-sync` mobs replicate to a joining client of a dedicated server.

## How to get to it (user POV)

- Host a world and walk around the spawn island; mobs are within a few screens.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`.

- **Run.** Run `./.cursor/skills/verify-flagoria/bin/drive-verify.sh` (or `./tools/verify.sh`) and read `artifacts/verify.log`.
- **Proof.** Each header `-- test_mob_predict_matches_chunks`, `-- test_mob_plan`, `-- test_mob_wander`, `-- test_mob_sheet_swap`, `-- test_mobs_sync_to_peer`, `-- test_mob_chase`, `-- test_mob_chase_two_players`, `-- test_mob_contact`, `-- test_mob_contact_two_players`, `-- test_mob_sword`, `-- test_mob_sword_two_players`, `-- test_mob_sword_two_attackers` appears in the log, no `FAIL` line follows it, and the run ends with `All tests passed.` and `Verification passed.`

## Gotchas

- The `*_two_players` tests start a second headless Godot as a dedicated server on a free UDP port; a blocked loopback port fails them.
- Swapping mob art is a sheet file change; `test_mob_sheet_swap` fails if a texture is put in `Mobs/mob.tscn`. Sheet layout notes live in `art/mobs/README.md`.
