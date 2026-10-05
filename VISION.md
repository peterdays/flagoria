# Flagoria vision

> A living document. It captures where Flagoria comes from and where it is heading, and it is meant to be revised as the game evolves.

## Why it exists

Flagoria is an experiment for an era where anyone can make their own game. Builds are play-tested with live feedback ("I like this, I don't like that"), and the game is iterated from that. Every change should be easy to try quickly.

## Origins

Flagoria started about two years ago as the first iteration of a live-coded game.

## The core fascination: procedural maps

What drives Flagoria is procedural map generation: worlds that are generated, not hand-painted, so every match plays on fresh ground.

## The original concept

The first idea was capture the flag on floating islands, inspired by Age of Empires. That turned out hard to build in full, so the game became islands with player-versus-player combat between two players.

## Core game

Capture the flag on floating islands. Build a village: walls, city walls, and buildings that are generated procedurally, update procedurally, and blend with each other (procedural city walls are a favourite idea). Mix in tower defense: a base holds flags, can expand and conquer other bases to collect their flags, and loses at zero flags.

## Endless possibilities

Like real life: Flagoria should be an open playground for everything in the world, not just the terrain — items, players, clothing, buildings, and how they all fit together.

## Buildings from building blocks

Buildings are generated from modular pieces, combined with techniques such as wave function collapse plus constraints, so every building always makes sense structurally and visually.

## Multiplayer is a hard requirement

Multiplayer is essential and non-negotiable. Every change has to keep two-player PvP working, and features that break or sideline multiplayer are out of scope.

There is no public release planned for now, but the multiplayer experience should still be great. The target is an always-running server that friends connect to and play on: the server runs in a Docker container (`docker compose up` on a home machine), and friends join over a VPN.

### Open question: dedicated-server feasibility

**What works today**

- Godot 4.1 supports `--headless` (display/audio drivers stubbed). The project binary starts under `--headless` and loads the main scene.
- The engine build includes a dedicated-server export path (feature tag / "Export as dedicated server") that can strip visuals on export.
- Networking today uses `ENetMultiplayerPeer` on UDP port `9786`, with a listen-server model: one player presses Host (`create_server`), others Join (`create_client`). Hosting always goes through the main menu and spawns the host as a player.

**What is missing**

- No headless auto-host / dedicated server mode: launching headless still presents the normal client flow; there is no export preset or boot path that starts a server without a local player UI.
- No Docker Compose setup yet, and no server-authoritative dedicated process separate from a listening player host.

**Likely next steps**

1. Add a headless boot flag or main-scene path that calls `create_server` and skips local player / menus.
2. Add a Linux dedicated-server export preset (and optionally a `.pck` + headless binary layout suitable for a container).
3. Document UDP `9786` publishing for compose/VPN join; keep two-player PvP working throughout.

## Roadmap

**First step:** an in-game admin menu to set every map generation parameter before a new match (no hardcoding, no recompile).

**Next:** save the current map and keep playing it later.

**Current focus:** a procedural map that is genuinely strong and fun to explore — island shapes, terrain, shorelines, vegetation, props, and how they are placed.

**Long term:** make everything procedural, weapons included. Options: building-block formulas that combine parts into mix-and-match weapons (for example a sword = handle + edge + runes, three options each, with formulas over each block's elements scoring the weapon's stats), or dice-roll rules with a maximum size and rolled stats. Either way, every game is unique.

## Iterating on this document

This vision is a living doc. Update it when the direction changes, and keep it short.
