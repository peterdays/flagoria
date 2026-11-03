# In-game menu and quit prompt

The in-game menu button (three bars, top right) or Esc opens a Pause panel with Resume, Save, Main menu and a status label. Nothing is paused, locally or for other players. The Android back button or a window close asks "Do you want to quit?" first.

## Sub-features

- `menu-panel` `InGameMenu` (`Scripts/ingame_menu.gd`): `MenuButton` opens `MenuPanel`; Resume (`ui_back` sound) or Esc again closes it; on the main menu Esc does nothing. An open panel covers the map, so pinch zoom does not reach it. While it is open, touch aim and swings do not start.
- `menu-save` Save writes a world save (see [Map save files](./map-save.md)) and the status shows `Saved: MM-DD HH:MM`.
- `menu-leave` Main menu leaves the session and goes back to the main menu.
- `quit-prompt` `Scripts/quit_prompt.gd`: back or close shows the confirm dialog; nothing is paused.

## How to get to it (user POV)

- Host, tap the three-bar button, try Resume, Save and Main menu; press back on Android.

## Driving it with verify-flagoria helpers

Preconditions: `doctor.sh` exits `0`. Time cost: the four tests add about 1 s to `tools/verify.sh` (~2.2 s alone with `--only=`).

- **Run.** `./.cursor/skills/verify-flagoria/bin/drive-verify.sh` and read `artifacts/verify.log`.
- **Proof.** Headers `-- test_ingame_menu_open_resume`, `-- test_ingame_menu_save`, `-- test_ingame_menu_leave`, `-- test_quit_prompt_on_back` with no `FAIL` after them.
- **Drive (live).** `bin/launch.sh drives/combat_hud.gd` clicks the menu button, checks a touch aim does not start and no swing happens under the panel, then clicks Resume. `bin/launch.sh drives/chop_trees.gd --seed 49` saves through the panel (see [Chop trees (live drive)](./chop-trees.md)). `combat_hud` takes ~3 s.
