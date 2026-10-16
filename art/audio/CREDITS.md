# Audio credits

| File | Source | Author | License |
| --- | --- | --- | --- |
| `sfx/footsteps/footstep_sand_01.wav` … `_03.wav` | Original, generated (`tools/audio/gen_footsteps.py`) | Flagoria project | CC0 1.0 |
| `sfx/footsteps/footstep_grass_01.wav` … `_03.wav` | Original, generated (`tools/audio/gen_footsteps.py`) | Flagoria project | CC0 1.0 |
| `sfx/footsteps/footstep_swamp_01.wav` … `_03.wav` | Original, generated (`tools/audio/gen_footsteps.py`) | Flagoria project | CC0 1.0 |

Generated files are procedural filtered noise (numpy), mono 16-bit 22.05 kHz, 0.22–0.34 s,
RMS-normalized to about -20 dBFS with peaks below -0.3 dBFS. Regenerate with:

    python3 tools/audio/gen_footsteps.py art/audio/sfx/footsteps

Bundled third-party audio (not used by these files yet): `art/Sprites/NinjaAdventure/Sounds/`,
Ninja Adventure by pixel-boy and AAA, https://pixel-boy.itch.io/ninja-adventure-asset-pack, CC0 1.0
(see `art/Sprites/NinjaAdventure/LICENSE.txt`).
