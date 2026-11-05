# App icon

Drive: not player-facing

A pixel-art tower is the project, window and Android launcher icon.

## Sub-features

- `icon-generate` `python3 tools/icon/make_icon.py` renders `art/icon/*.png` from `art/icon/tower_32.txt` (see `art/icon/README.md`).
- `icon-wired` `project.godot` `config/icon` and the Android `launcher_icons/*` in `export_presets.cfg`.

## How to get to it (user POV)

- Window title bar icon; Android launcher after installing the debug APK (`docs/android-apk.md`).

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`.

- **Run.** `./.cursor/skills/verify-flagoria/bin/drive-verify.sh`. The generator smoke step prints `PASS app icon and 3 launcher icons` (the project icon and each Android launcher key with its square size). Time cost: under a second inside `tools/verify.sh`.

## Gotchas

- Verify does not re-run `make_icon.py`; after a generator change, re-run it and confirm `git status` shows no unintended image change.
