# App icon

Original pixel art made for Flagoria: a stone tower with battlements and a
waving flag on a grassy mound. Released under CC0 1.0, like the NinjaAdventure
pack whose palette (`art/Sprites/NinjaAdventure/Palette.png`) it uses.

- `tower_32.txt`: the 32x32 source grid, one character per pixel. The legend
  is the `PALETTE` table in `tools/icon/make_icon.py`, and `.` is transparent.
- `icon.png`: 256x256 project and window icon (`application/config/icon`).
- `launcher_main_192.png`: Android main icon.
- `launcher_fg_432.png` / `launcher_bg_432.png`: Android adaptive icon
  foreground and background. The foreground art stays inside the 66dp
  (264 px) safe circle; the script checks this.

To change the icon, edit the grid and regenerate:

    python3 tools/icon/make_icon.py

`--preview DIR` also writes review images to `DIR`: a 512 px icon, the
masked adaptive icon, a safe-zone overlay and a 48 px home-screen mock.
