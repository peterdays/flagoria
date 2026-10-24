# App icon

A pixel-art tower is the project, window and Android launcher icon.

## Sub-features

- `icon-generate` `python3 tools/icon/make_icon.py` renders `art/icon/*.png` from `art/icon/tower_32.txt` (see `art/icon/README.md`).
- `icon-wired` `project.godot` `config/icon` and the Android `launcher_icons/*` in `export_presets.cfg`.

## How to get to it (user POV)

- Window title bar icon; Android launcher after installing the debug APK (`docs/android-apk.md`).

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`.

- **Run.** No headless test covers this yet; see Gotchas for the manual recipe.

## Gotchas

- No automated check yet; prove by re-running the generator and confirming `git status` shows no image change.
