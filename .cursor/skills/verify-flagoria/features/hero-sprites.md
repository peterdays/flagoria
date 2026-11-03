# Hero sprites

Player sprite sheets come from a layered generator; the Flagbearer sheet is the player sprite.

## Sub-features

- `hero-generate` `python3 tools/hero/make_hero.py [hero ...]` builds sheets and previews from `art/hero/parts` and `art/hero/heroes/*.ini` (see `docs/hero-sprites.md`).
- `hero-in-game` `art/hero/sheets/flagbearer_sheet.png` (128x256) is used by `Player/character_body_2d.tscn`.

## How to get to it (user POV)

- Host and look at your player.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`.

- **Run.** `./.cursor/skills/verify-flagoria/bin/drive-verify.sh`. The generator smoke step (see [Headless verify](./headless-verify.md)) prints `PASS hero sheet (128, 256) used by the player scene` and, when Python 3 with Pillow is present, `PASS hero sheet regenerates identically`. Time cost: a few seconds inside `tools/verify.sh`.

## Gotchas

- Without Pillow verify prints `Hero regeneration: skipped` and checks only the committed sheet; record that the regeneration was not checked.
- How the hero looks in game is a manual call.
