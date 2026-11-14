# World saves

A world save is one file in `user://saves/<name>.json`. It records how the
world was generated and what changed in it since. Terrain is never stored: the
generator rebuilds it from the generation inputs, and the change sections are
applied on top.

`Scripts/map_save.gd` (`MapSave`) reads and writes the file.
`Scripts/world_save.gd` (`WorldSave`) is the save in memory. This page covers
the container format (#196). Tree and bush cuts fill
`world.object_changes` (see [Cut trees and bushes](#cut-trees-and-bushes)).
Placed plank bridges fill `world.tile_edits` (see
[Placed plank bridges](#placed-plank-bridges)). Placed structures and
free-form walls fill `world.structures` (see
[Structures and walls](#structures-and-walls)). Player progress fills
`player` (see [Player progress](#player-progress)).

## Encoding

The writer stores **gzip of one compact JSON document** (Godot
`PackedByteArray.compress` with `FileAccess.COMPRESSION_GZIP`). Gzip is the
compact encoding because the JSON repeats chunk keys, cell keys and tile
names, and the engine already decompresses it. The document is one line, with
`format` and `format_version` first, so it is readable after `gunzip`.

A file whose first bytes are not the gzip magic `1f 8b` is the JSON itself.
Version 1 and version 2 were written that way, and a hand-written file still
loads. The writer always gzips. A gzip that will not decompress, or whose JSON
would expand past 1 MiB (`MapSave.MAX_SAVE_BYTES`), is refused.

`_test_world_save_size_budget` prints the measured sizes against two budgets:

| Save | Budget |
| --- | --- |
| Fresh world (header and generation inputs, no edits) | 1024 bytes |
| 300 plank-cell edits, keyed by 32-cell chunk | 8192 bytes |

With the current params and that edit shape, a fresh world is about 520 bytes
of gzip (about 1.2 KB of JSON) and 300 edits are about 1.4 KB of gzip (about
15 KB of JSON). The timestamps move the size by a few bytes. The test prints
the sizes it measured and fails when one goes over the budget. Uncompressed
JSON of those two saves is already over the budget, so dropping the gzip
fails the test.

## File layout (version 3)

The JSON inside the gzip, shown with line breaks:

```json
{
	"format": "flagoria-world",
	"format_version": 3,
	"game_version": "0",
	"created": 1760000000,
	"updated": 1760000000,
	"params": {
		"altitude_seed": 4242,
		"...": "every MapGenParams value"
	},
	"world": {"object_changes": {}, "structures": {}, "tile_edits": {}},
	"player": {}
}
```

| Key | Meaning |
| --- | --- |
| `format` | Always `flagoria-world`. Any other value is refused, so a stray JSON file is never read as a world. |
| `format_version` | An integer. Bump it whenever the meaning of the file changes. |
| `game_version` | The game version string of the build that last wrote the file (`MapSave.GAME_VERSION`, currently `"0"`; there is no separate release number). The loader does not branch on it. An older file migrates with `""` until it is saved again. |
| `created` | Unix seconds when the file was first written. A later save of the same file keeps it. An older file uses the file's modified time. |
| `updated` | Unix seconds of the last write. |
| `params` | The generation inputs: every `MapGenParams` value, seeds included. Floats are written with enough digits to read back the same value. |
| `world.tile_edits` | Changed tiles (#41). |
| `world.object_changes` | Changed world objects such as felled trees or picked items (#198). |
| `world.structures` | Placed structures (#42). |
| `player` | The player's own progress (#197). Empty means the default player. |

Each `world` section is sparse and keyed by chunk, then by cell:
`{"<cx>,<cy>": {"<x>,<y>": <entry>}}`. A chunk is a fixed 32 by 32 cells
(`WorldSave.CHUNK_SIZE`, floored, so cell `-20,70` is in chunk `-1,2`), not the
map's draw chunk size, which the params can change. `WorldSave.chunk_key` and
`WorldSave.cell_key` build the keys. Only chunks with a change appear, so a
loader can apply a chunk's changes when it builds that chunk. The feature that
owns a section decides the shape of its entries. JSON numbers read back as
floats, so each entry's reader converts its own integers.

`format` and `format_version` come first so the document is easy to identify
after it is uncompressed. The saved maps list does not read the header: it
uses the file's modified time, which a save updates, and opening the list
does not rewrite the file.

The main menu's Worlds screen lists every file in that folder, by name and
modified time. Load hosts that file. Host, and New world, start a match whose
saves go in a new file, so an existing save is not replaced. Save writes that
match's file again. A file already in the folder is listed as it is; opening
the list does not rewrite it. Rename changes the file name through the same
inline confirm pattern as delete (`MapSave.rename_save`). Each row shows a
cached terrain preview from the generation inputs (`Scripts/world_save_preview.gd`).

## Cut trees and bushes

A felled tree or bush is a `world.object_changes` entry on its cell:

```json
"world": {"object_changes": {"0,0": {"23,19": {"cut": "tree", "age": 40.0}}}}
```

| Key | Meaning |
| --- | --- |
| `cut` | The type that was cut, by its `save_key` (`tree`, `pine`, `bush`). |
| `age` | Seconds of play since the cut. The regrowth wait goes on from there after a load. |

The age is play time only: time while the game is closed does not count, so
nothing regrows between sessions. That is a choice for now and can be
revisited. The cut's own play time is not stored, because play time starts
again from 0 in every session.

`TreeCuts.to_changes` writes the entries and `TreeCuts.restore` reads them
back. On a load, an entry is dropped when its type is unknown or the map no
longer grows that type on that cell (after a generator change, for example).
Entries with neither `cut` nor `sprout` belong to other features and are
left alone.

A tree that sprouted on a free cell (#361, see
[Interactables](interactables.md), Sprouting) is an entry with `sprout`, the
`save_key` of the tree that grew there; once chopped it also has `cut` and
`age`:

```json
"world": {"object_changes": {"0,0": {"24,19": {"sprout": "tree"}, "25,19": {"sprout": "pine", "cut": "pine", "age": 12.0}}}}
```

`TreeSprouts.to_changes` and `TreeSprouts.restore` write and read them, in
the same pass as the cuts; a sprout is dropped on a load when the map no
longer grows that tree on that cell. Joining peers get them in the same cut
list.

## Placed plank bridges

A plank bridge cell (#226) is a `world.tile_edits` entry on its cell, naming
the plank piece by its `TileCatalog` name:

```json
"world": {"tile_edits": {"0,0": {"14,12": {"tile": "BRIDGE_PLANK_H_START_WATER"}, "15,12": {"tile": "BRIDGE_PLANK_H_TIP_E_WATER"}}}}
```

| Key | Meaning |
| --- | --- |
| `tile` | The plank piece drawn on the cell, one of the `BRIDGE_PLANK_*_WATER` names. A name, not atlas coordinates, so a tileset rearrangement keeps old saves readable. |

Only bridge cells are written: every other cell regenerates from the seed, so
the save grows by one entry per plank. `BridgeBuilder.to_changes` writes the
entries from the bridge list (`bridges_for_sync`), and
`BridgeBuilder.from_changes` reads them back into that list for
`replace_bridges`. On a load, an entry is dropped when its tile is not a plank
piece, its cell key is malformed, or the map no longer generates water on its
cell (after a generator change, for example). Entries without `tile` belong
to other tile edits (#41) and are left alone.

## Structures and walls

A placed structure (#42) is a `world.structures` entry on its anchor cell; a
free-form palisade wall cell (#276) is an entry on its cell:

```json
"world": {"structures": {"0,0": {"3,4": {"structure": "castle", "owner": 1, "order": 0}, "12,2": {"structure": "tower_wood", "owner": -1, "order": 1}, "9,8": {"wall": "palisade"}}}}
```

| Key | Meaning |
| --- | --- |
| `structure` | The shipped structure file, by name (`res://structures/<name>.txt`). |
| `owner` | The owning peer id, `0` for a neutral tower or `-1` for one the mobs took (#274). The flag colour follows it. |
| `order` | Placement order, so placement ids come back the same. |
| `wall` | `palisade`: a free-form wall cell. Its piece is solved again on load. |

`StructureSaves.to_changes` writes the entries and `StructureSaves.restore`
reads them back, placements first so the walls join the structure walls.
Cities (#277) are not stored: they are rebuilt from the towers and walls.
Tower capture progress is not stored either; a capture in progress starts
over. On a load, a placement naming no shipped structure, a wall on a cell
that no longer generates land, and malformed keys are dropped. Entries with
neither key are left alone.

A save that holds the host's castle starts with that castle: its gate front
is the spawn and no new starting castle is placed. A save without one (every
save written before this section was filled) gets a starting castle as a new
world does. The file meaning is unchanged (the section was reserved in
version 2), so the version stays 2.

## Player progress

The host's own progress (#197) is the `player` object. `PlayerSave.capture`
writes it when the in-game menu saves, and `PlayerSave.apply` puts it back
when that host's body is placed (`add_player`). A joining peer is not this
section: they start fresh, and the host's health and score still sync the
way they do in a live match. Held items are not stored; there are none yet.

```json
"player": {
  "position": [120.0, 340.5],
  "health": 4,
  "wood": 3,
  "score": 2,
  "charted": {"0,0": "<base64 of 128 bytes>"},
  "discovered": {"0,0": 1}
}
```

| Key | Meaning |
| --- | --- |
| `position` | World pixels `[x, y]`. Missing, or not a pair of numbers: the map's spawn. |
| `health` | Half-hearts, from 0 up to the player's maximum. Missing, or not a whole number in that range: full health. |
| `wood` | Wood in the inventory. Missing, or negative: 0. |
| `score` | This peer's point total. Missing, or negative: 0. |
| `charted` | Explored ground (#247). Chunk key -> base64 of that chunk's 128-byte bitset, the same 32-cell grid as the chart. A bad chunk is dropped. Missing: nothing charted. |
| `discovered` | Chunks that already paid discovery points, `"cx,cy"` -> peer id. Kept so the saved score is not paid again for the same chunk. A bad entry is dropped. Missing: no chunk has paid. |

An older save has no `player` object, or `{}`. Both load as the default player: spawn, full health, no wood, no score, nothing charted. The file meaning of an empty section is unchanged, so the version stays 3.

## Saving during play

**Save** in the in-game menu writes the world being played, named after the
date and time (`2026-10-27 22-15-03`; a second save in the same second gets
` 2`). The panel stays open and confirms it on one line ("Saved: 10-27 22:15"),
so the player can resume or leave. The file is the version 3 gzip above. It
holds the generation inputs, this peer's tree and bush cuts, plank bridges,
placed structures and walls, and this peer's player state (position, health,
wood, score, charted ground). A second save of that same file keeps `created`
and refreshes `updated`. The rest of the object changes (#198: picked items,
destroyed objects, cleared mobs) are not saved yet.

The new bytes are not written into the existing file. They go to
`<name>.json.tmp` beside it. That file is closed, then kept only when
`MapSave.read_document` reads it as a save. `DirAccess.rename_absolute` then
moves it onto `<name>.json`, replacing the previous save in one step. A crash
while the temp file is being written leaves the previous save loadable. The
next save removes a leftover `.tmp`. The worlds list skips `.tmp` files.

## Loading

`MapGen.load_map_inputs(path)` makes a save the world the next host starts. It
sets the params and keeps the change sections. When the host then starts with
those same params, `Flagoria.setup_server` restores the cuts, plank bridges, structures and
walls after it applies the params and before any chunk is drawn or any player
spawns, so cut cells are drawn as stumps and a saved bridge is walkable
straight away. The host body is then placed from `player` (or at the spawn,
when that section is empty). If the params were changed in between, no
changes are applied and the player section is not used.
A player who joins gets the restored bridges with the map, like any other
bridge (#297). A dedicated
server started with `--params` reads the params only.

A player who joins gets the host's current cut list with the map params
(`receive_map_params`, in the same entry format) and restores it before
drawing any chunk, so both see the same stumps. The list goes at most 500
cuts per message (`JOIN_CUTS_PER_MESSAGE` in `flagoria_main.gd`, #354): the
first part with the params, the rest in `receive_join_cuts` right after. The list replaces whatever
cuts the joiner held, so it ends with exactly the host's set. Cuts made
during play go through the host and reach every peer as they happen
(`Interaction.apply_cut`, after the join list on the same reliable channel).
Regrowth is decided by the host alone and reaches every peer the same way
(`Interaction.apply_regrow_cells`, #298), so the lists cannot drift apart during
two-player play.

`MapSave.load_world(path)` returns `{"world", "error", "version"}`:

- A file at the current version loads as it is. A missing section counts as
  empty.
- An older version is migrated in memory, one version step at a time (see
  `MapSave._migrate`). `version` reports the version the file was written at.
  The file itself is only rewritten, at the current version, when the world is
  next saved.
- Newer versions are refused with an error naming both versions: "map save
  version 4, from a newer build; this build reads versions 1 to 3". A build
  never guesses at a format it does not know.
- Refused with an error, never a partial world: a version that is not a whole
  number of at least 1, a wrong or missing `format` from version 2 on, missing
  `params`, a section that is not an object, a `game_version` that is not a
  string, a `created` or `updated` that is not a whole number of seconds, or
  a gzip payload that will not decompress.

`MapSave.load_map` and `MapSave.save_map` still work on the generation inputs
only. Existing callers are unchanged, and saving through them writes the
current version with empty sections.

## Versions

| Version | Change |
| --- | --- |
| 1 | `format_version` and `params` only. Written by the first map saves. Plain JSON. |
| 2 | Adds `format`, `world` and `player`. Version 1 files migrate with empty sections, because version 1 saved no changes. Plain JSON. |
| 3 | Adds `game_version`, `created` and `updated`, and the file is gzip of the compact JSON. Version 2 migrates with `game_version` `""` and both times set from the file's modified time. The sections are unchanged. |

### Bumping the version

1. Raise `MapSave.FORMAT_VERSION`.
2. Add a step to `MapSave._migrate` that turns the previous version into the
   new one.
3. Add `tests/fixtures/world_save_v<N>.json`, a file written by the new code.
   `_test_world_save_migrates_v1` loads every fixture from version 1 up, so a
   migration that breaks an old version fails the tests.
4. Add a row to the table above.

Never edit an existing fixture: each one stands for files that players already
have.

## Why existing saves are not rewritten on disk

Version 1 and version 2 files load through the migration, so nothing needs
rewriting. Rewriting every file in `user://saves/` at startup would touch
player data without a reason. An interrupted write could also lose a save
that loads fine as it is. An older file becomes version 3 the next time that
world is saved. `created` is then the time the older file was last modified,
and `updated` is the time of the new save.
