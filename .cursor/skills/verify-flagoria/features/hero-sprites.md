# Hero sprites

Player sprite sheets come from a layered generator; the Flagbearer sheet is the player sprite.

## Sub-features

- `hero-generate` `python3 tools/hero/make_hero.py [hero ...]` builds sheets and previews from `art/hero/parts` and `art/hero/heroes/*.ini` (see `docs/hero-sprites.md`).
- `hero-in-game` `art/hero/sheets/flagbearer_sheet.png` (128x256) is used by `Player/character_body_2d.tscn`.

## How to get to it (user POV)

- Host and look at your player.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`.

- **Run.** No headless test covers this yet; see Gotchas for the manual recipe.

## Gotchas

- No automated check yet: verify.sh does not run the generator. Prove a change by running `python3 tools/hero/make_hero.py flagbearer` (needs Python 3 and Pillow) and comparing the committed sheet; record that this was manual.
