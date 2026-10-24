# Mob art

| file | what |
|---|---|
| `mob_slime_sheet.png` | slime (grass) |
| `mob_crab_sheet.png` | beach crab (sand) |
| `mob_piglet_sheet.png` | boar piglet (grass) |
| `fx_puff.png` | shared death puff, 4 frames of 16x16 (64x16) |

## Sheet layout

Each sheet is 128x256: 8 columns x 16 rows of 16x16 frames, the same grid as the
hero sheet (`hframes = 8`, `vframes = 16`). Row order inside each block is
down, left, right, up.

| rows | anim | cols | fps |
|---|---|---|---|
| 0-3 | walk | 0-3 | 5 |
| 4-7 | attack | 0-3 | 5 |
| 8-11 | idle | 0-1 | 2.5 |
| 12-15 | hurt | 0-1 (white flash, recoil) | 10 |

The frame layout is the same for every mob and lives in
`Scripts/mob_catalog.gd`. Each mob type names exactly one sheet path there, so a
recoloured sheet (for example a different crab shell colour) is a file swap:
replace the PNG with the same name, or change that one path.

## Provenance and licence

Original project art. The sheets are drawn in code from small text grids by a
palette-locked, deterministic sprite script (fills plus a 1 px outline in the
project ink colour `#2a2238`), the same method as the tileset and the hero
generator. The crab uses a two-step orange ramp (`#f57620`, `#b03c14`) with a
`#ffe680` highlight; orange is a creature colour only, never a team colour.
No third-party images, packs or generated-image models were used.
No separate licence is declared for these files, so they are covered by the
repository licence (`LICENSE.md`).
