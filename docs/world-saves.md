# World saves

A world save is one JSON file in `user://saves/<name>.json`. It records how the
world was generated and what changed in it since. Terrain is never stored: the
generator rebuilds it from the generation inputs, and the change sections are
applied on top. An unchanged world is about 1 KB.

`Scripts/map_save.gd` (`MapSave`) reads and writes the file.
`Scripts/world_save.gd` (`WorldSave`) is the save in memory. This page covers
the container format, which is slice 1 of #196. Tree and bush cuts fill
`world.object_changes` (see [Cut trees and bushes](#cut-trees-and-bushes)). The
other change sections stay empty until the features that fill them land.

## File layout (version 2)

```json
{
	"format": "flagoria-world",
	"format_version": 2,
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
| `params` | The generation inputs: every `MapGenParams` value, seeds included. Floats are written with enough digits to read back the same value. |
| `world.tile_edits` | Changed tiles (#41). |
| `world.object_changes` | Changed world objects such as felled trees or picked items (#198). |
| `world.structures` | Placed structures (#42). |
| `player` | The player's own progress (#197). |

Each `world` section is sparse and keyed by chunk, then by cell:
`{"<cx>,<cy>": {"<x>,<y>": <entry>}}`. A chunk is a fixed 32 by 32 cells
(`WorldSave.CHUNK_SIZE`, floored, so cell `-20,70` is in chunk `-1,2`), not the
map's draw chunk size, which the params can change. `WorldSave.chunk_key` and
`WorldSave.cell_key` build the keys. Only chunks with a change appear, so a
loader can apply a chunk's changes when it builds that chunk. The feature that
owns a section decides the shape of its entries. JSON numbers read back as
floats, so each entry's reader converts its own integers.

`format` and `format_version` come first so the file is easy to identify by eye.
There are no timestamps in the file: the saved maps list uses the file's
modified time.

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
Entries without `cut` belong to other features and are left alone.

## Saving during play

**Save** in the in-game menu writes the world being played, named after the
date and time (`2026-10-27 22-15-03`; a second save in the same second gets
` 2`). The panel stays open and confirms it on one line ("Saved: 10-27 22:15"),
so the player can resume or leave. The file holds the generation inputs and
this peer's tree and bush cuts. Player state (#197) and the rest of the object
changes (#198) are not saved yet.

## Loading

`MapGen.load_map_inputs(path)` makes a save the world the next host starts. It
sets the params and keeps the change sections. When the host then starts with
those same params, `Flagoria.setup_server` restores the cuts after it applies
the params and before any chunk is drawn, so cut cells are drawn as stumps.
If the params were changed in between, no cuts are applied. A dedicated
server started with `--params` reads the params only.

A player who joins gets the host's current cut list with the map params
(`receive_map_params`, in the same entry format) and restores it before
drawing any chunk, so both see the same stumps. The list replaces whatever
cuts the joiner held, so it ends with exactly the host's set. Cuts made
during play go through the host and reach every peer as they happen
(`Interaction.apply_cut`, after the join list on the same reliable channel).
Regrowth is decided by the host alone and reaches every peer the same way
(`Interaction.apply_regrow`, #298), so the lists cannot drift apart during
two-player play.

`MapSave.load_world(path)` returns `{"world", "error", "version"}`:

- A file at the current version loads as it is. A missing section counts as
  empty.
- An older version is migrated in memory, one version step at a time (see
  `MapSave._migrate`). `version` reports the version the file was written at.
  The file itself is only rewritten, at the current version, when the world is
  next saved.
- Newer versions are refused with an error naming both versions: "map save
  version 3, from a newer build; this build reads versions 1 to 2". A build
  never guesses at a format it does not know.
- Refused with an error, never a partial world: a version that is not a whole
  number of at least 1, a wrong or missing `format` from version 2 on, missing
  `params`, or a section that is not an object.

`MapSave.load_map` and `MapSave.save_map` still work on the generation inputs
only. Existing callers are unchanged, and saving through them writes the
current version with empty sections.

## Versions

| Version | Change |
| --- | --- |
| 1 | `format_version` and `params` only. Written by the first map saves. |
| 2 | Adds `format`, `world` and `player`. Version 1 files migrate with empty sections, because version 1 saved no changes. |

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

Version 1 files load through the migration, so nothing needs rewriting.
Rewriting every file in `user://saves/` at startup would touch player data
without a reason. An interrupted write could also lose a save that loads fine
as it is. A version 1 file becomes version 2 the next time that world is saved.
