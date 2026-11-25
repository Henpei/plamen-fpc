# PLAMEN (side 2 — Free Pascal / raylib)

Hardcore high-fantasy isometric action RPG. This document records MY technical
choices and reasoning as I build (section 7 of the brief: the README is my
defense in the bake-off against the QB64 implementation).

## Platform decision (section 0, side 2)
- **Free Pascal 3.2.2, x86_64, `/usr/bin/fpc`, compiled from terminal. No Lazarus.**
- Build: `make` → `tools/build.sh` stamps `src/version.inc` with the git commit
  hash, then `fpc -O2 ... src/plamen.dpr -o build/plamen`.
- **Renderer: raylib 6.2** (`pacman` package `raylib`, `libraylib.so` +
  `/usr/include/raylib.h`). Chosen because it is installed on the machine, is a
  flat C API (trivially bound from Pascal — see `src/raylib.pas`), gives
  hardware-accelerated 2D with textures/triangles (exactly what an isometric
  projection needs), and has no IDE dependency. Alternative considered: raw
  X11 via fpc's x11 unit — rejected: software blitting + manual event loop for
  no benefit over raylib.

## Rendering approach
- Isometric 2:1 projection: `sx = (x - y) * 32`, `sy = (x + y) * 16 - z`,
  tile = 64x32 px. World coordinates are float tile units; camera follows the
  player; y-sorted draw order (painter's algorithm) for entities + tiles.
- Art style: **procedural silhouette-first sprites**. No external art assets.
  At startup the game renders every sprite into a `RenderTexture` (colored
  diamond tiles per biome, rim-lit circles/blades for entities, letter glyphs
  for markers) — readable at combat speed, zero asset pipeline, fully
  deterministic. Team/enemy/telegraph color language: player cyan-white, enemy
  red, telegraph orange fill + white outline, loot gold, NPC green.
- HUD every frame: HP/MP/Stamina bars, XP bar, quickbar, minimap, quest tracker,
  and **build evidence: map name + commit hash + act/region in the corner,
  always**.

## Architecture
- Strict split: **simulation units never touch raylib** (`core`, `data`, `sim`,
  `maps`, `selftest`). Only `render.pas` + `plamen.dpr` do graphics/input.
  This is what makes `plamen selftest` a real headless suite (RC=0, log file).
- All content is **data-driven**: `data/*.dat` INI-ish files parsed into typed
  registries by `data.pas`. Monsters, spells, gear, affixes, quests, NPCs,
  lore, stores, maps = data, not code branches. Selftest `data_add_monster`
  drops a new monster into a temp data file and verifies it loads and spawns
  without touching code.
- Save system: binary slots in `saves/`, header magic + format version +
  CRC32 payload checksum; corruption/tamper = loud fatal, no silent repair;
  migration path via version field.
- Error law: **no silent fallbacks**. Anything missing/corrupt is a loud fatal
  (`Fatal()` → console + `error.log`, nonzero exit). Without `DISPLAY` the game
  exits RC=2 with a clear message instead of crashing silently.

## Data formats
- `data/*.dat`: `[type:id]` sections, `key=value`, `#` comments, `|` lists.
- `data/maps/*.map`: header `key=value` lines then an ASCII grid (legend in
  `data/maps/LEGEND.txt`).

## Status
See git log; milestone = First Playable per brief section 7. Selftest gate:
`make selftest` must be RC=0 before every commit (SGT loop).
