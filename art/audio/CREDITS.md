# Audio credits

| File | Source | Author | License |
| --- | --- | --- | --- |
| `sfx/footsteps/footstep_sand_01.wav` … `_03.wav` | Original, generated (`tools/audio/gen_footsteps.py`) | Flagoria project | CC0 1.0 |
| `sfx/footsteps/footstep_grass_01.wav` … `_03.wav` | Original, generated (`tools/audio/gen_footsteps.py`) | Flagoria project | CC0 1.0 |
| `sfx/footsteps/footstep_swamp_01.wav` … `_03.wav` | Original, generated (`tools/audio/gen_footsteps.py`) | Flagoria project | CC0 1.0 |
| `sfx/combat/sword_swing_01.wav` | Ninja Adventure, `Sounds/Game/Sword.wav`, https://pixel-boy.itch.io/ninja-adventure-asset-pack | pixel-boy and AAA | CC0 1.0 |
| `sfx/combat/sword_swing_02.wav` | Ninja Adventure, `Sounds/Game/Sword2.wav`, https://pixel-boy.itch.io/ninja-adventure-asset-pack | pixel-boy and AAA | CC0 1.0 |
| `sfx/combat/sword_swing_03.wav` | Original, generated (`tools/audio/gen_combat.py`) | Flagoria project | CC0 1.0 |
| `sfx/combat/hit_land_01.wav` | Ninja Adventure, `Sounds/Game/Hit1.wav`, https://pixel-boy.itch.io/ninja-adventure-asset-pack | pixel-boy and AAA | CC0 1.0 |
| `sfx/combat/hit_land_02.wav` | Ninja Adventure, `Sounds/Game/Hit3.wav`, https://pixel-boy.itch.io/ninja-adventure-asset-pack | pixel-boy and AAA | CC0 1.0 |
| `sfx/combat/hit_land_03.wav` | Ninja Adventure, `Sounds/Game/MiniImpact.wav`, https://pixel-boy.itch.io/ninja-adventure-asset-pack | pixel-boy and AAA | CC0 1.0 |
| `sfx/combat/player_hurt_01.wav` | Ninja Adventure, `Sounds/Game/Hit2.wav` (trimmed to 0.4 s), https://pixel-boy.itch.io/ninja-adventure-asset-pack | pixel-boy and AAA | CC0 1.0 |
| `sfx/combat/player_hurt_02.wav` | Ninja Adventure, `Sounds/Game/Hit6.wav`, https://pixel-boy.itch.io/ninja-adventure-asset-pack | pixel-boy and AAA | CC0 1.0 |
| `sfx/combat/hit_sting_01.wav` | Original, generated (`tools/audio/gen_combat.py`) | Flagoria project | CC0 1.0 |
| `art/Sprites/NinjaAdventure/Musics/5 - Peaceful.ogg` (menu music, used in place) | Ninja Adventure, `Musics/5 - Peaceful.ogg`, https://pixel-boy.itch.io/ninja-adventure-asset-pack | pixel-boy and AAA | CC0 1.0 |
| `art/Sprites/NinjaAdventure/Musics/4 - Village.ogg` (game music, used in place) | Ninja Adventure, `Musics/4 - Village.ogg`, https://pixel-boy.itch.io/ninja-adventure-asset-pack | pixel-boy and AAA | CC0 1.0 |

Footstep files are procedural filtered noise (numpy), mono 16-bit 22.05 kHz, 0.22–0.34 s,
RMS-normalized to about -20 dBFS with peaks below -0.3 dBFS. Regenerate with:

    python3 tools/audio/gen_footsteps.py art/audio/sfx/footsteps

Ninja Adventure files are copied from `art/Sprites/NinjaAdventure/Sounds/Game/` (license: `art/Sprites/NinjaAdventure/LICENSE.txt`),
converted to mono 16-bit 22.05 kHz, trimmed, and RMS-normalized to about -20 dBFS. Generated files use the same format and level.
