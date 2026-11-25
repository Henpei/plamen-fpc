# PLAMEN (side 2 — Free Pascal / raylib)

Hardcore high-fantasy isometric action RPG. This document records MY technical
choices and reasoning (brief section 7: the README is my defense in the
bake-off against the QB64 implementation of the same vision).

## Platform decision (brief section 0, side 2)
- **Free Pascal 3.2.2, x86_64, `/usr/bin/fpc`, compiled from the terminal. No Lazarus/IDE.**
- Build: `make` → `tools/build.sh` stamps `src/version.inc` with the git commit
  hash, then `fpc -O2 -Mobjfpc -Sh -Fusrc -FEbuild -o./build/plamen src/plamen.dpr`.
- **Renderer: raylib 6.2** (pacman package `raylib`; `libraylib.so` + headers on
  the machine). Chosen because it is present, is a flat C API (bound by hand in
  `src/raylib.pas`, ~70 functions), gives hardware-accelerated 2D — exactly what
  an isometric projection needs — and has zero IDE dependency. Alternative
  considered and rejected: raw X11 via fpc's x11 unit (manual blit + event loop,
  no benefit over raylib).

## Rendering approach
- Isometric 2:1 projection: `sx = (x - y) * 32`, `sy = (x + y) * 16`; tile = 64x32
  px diamond drawn as two CCW triangles (raylib culls CW winding — found via
  screenshot debugging). World coords are float tile units; camera follows the
  player with optional screen shake; entities painter-sorted by `x+y`.
- Art: **procedural, silhouette-first, zero asset files.** Biome-colored diamond
  tiles with per-tile hash variation; entities are rim-lit circles with a facing
  tick and HP bar; telegraphs are pulsing orange ground circles with a shrinking
  windup ring; markers are colored glyphs. Color language: player cyan, enemy
  red, boss maroon/orange-enraged, telegraph orange, loot/quest gold, NPC green.
- HUD every frame: HP/MP/Stamina/XP bars, 8-slot quickbar, quest tracker, minimap,
  gold/points, and **build evidence: `PLAMEN <commit> | map=<id> "name" |
  region=.. act=.. | fps=..`** in the corner, always.

## Architecture
- Strict split: `core`, `data`, `reg`, `sim`, `maps`, `selftest` **never touch
  raylib**; only `render.pas` + `plamen.dpr` do. This is what makes
  `plamen selftest` a real headless suite (RC=0, logs to `selftest.log`).
- Data-driven: all content in `data/*.dat` (INI-ish `[kind:id]` + `key=value`,
  `|` lists) parsed by `data.pas` into typed registries in `reg.pas`. Maps are
  ASCII grids in `data/maps/*.map`. Adding a monster/spell/item/quest = adding a
  data section; selftest `data_add_monster`/`data_add_spell` prove it by loading a
  temp file at runtime.
- Stats: one shared formula registry (`data/stats.dat`). `kind=flat` stats
  accumulate gear/race/skill bonuses; `kind=derived` stats evaluate a small
  recursive-descent formula over attributes + level + flats (`sim.EvalFormula`).
  Combat code only ever calls `GetStat(p, id)` — new stats need no combat change.
- Quest/consequence system: one flag DB (`TFlagDB`) is the single source of
  truth. Quests complete → set flags → `rules.dat` consequence rules fire
  (act-1 looter choice → act-4 Compact supply line/blockade; act-2 cell survival →
  act-4 Remnant library → act-5 third path; Cinderhold overrun → alternate hub +
  pricier stores). All simulated headless in the selftest.
- Save system: `saves/<slot>.sav` = magic `PLAMSAVE` + format version + CRC32 +
  payload. Corruption/tamper = rejected with a named error; the game goes LOUD
  (Fatal → stderr + `error.log`, nonzero exit). Multi-slot; autosave slot +
  hardcore single-slot mode (death = reload).
- Error law: **no silent fallbacks.** Missing file / bad data / corrupt save =
  `Fatal()` (file:line named). Without `DISPLAY` the binary exits RC=2 with a
  clear message instead of crashing (verified).

## Data formats
- `data/*.dat`: `[kind:id]` sections, `key=value`, `#` comments, `|` lists.
- `data/maps/*.map`: header keys (`name, region, act, kind, tileset, w, h`,
  `portal.a=target:x:y`, `spawn.1=monster:count:radius`, `boss=monster`,
  `chest.1=table`, `lore.1=doc`, `marker.id=label`, `store=id`) then `h` rows of
  `w` chars (legend in `data/maps/LEGEND.txt`).
- Content generated deterministically by `tools/gen_content.py` (skills, builds,
  uniques, lore, side quests, maps); hand-authored story-critical files live
  alongside (quests.dat main chain, dialog.dat, rules.dat, npcs.dat...).

## Content delivered (counts verified by selftest)
- 26 monsters (5 Emberfall types + 10 bosses incl. act bosses), 36 spells in 6
  schools, 199 skill nodes across 9 trees (6 class + movement/crafting/arcana),
  52 named uniques with lore+source hooks, 33 base items, 32 affixes in 6 rarity
  pools, 26 lore documents (4 contradicting pairs, 1 hidden endgame codex),
  47 quests (5-act main chain + 40 side), 13 consequence rules, 5 regions ×
  (hub + 2 areas + dungeon) + alternate hub + world map = 22 maps, 5 stores,
  12 selftest-verified endgame builds, 10 NPCs with conditional dialog trees.

## Controls
WASD/arrows move · mouse aims · J/LMB attack combo · K hold block · SPACE/RMB
dodge (i-frames) · 1-8 quickbar · E interact/talk · I inventory · C build sheet ·
Q quest log · L lore log · ESC pause · F1 help · F3/F4/F5 toggles (shake,
telegraphs, damage numbers) · F10 screenshot. Pure-keyboard path works (facing
follows movement when the mouse is idle).

## Verification evidence
- `make selftest` → `plamen selftest` → **82 passed, 0 failed, RC=0**
  (`selftest.log`): stat formulas, element wheel, combat math, XP/levels, loot
  tables + affix rolls, quest chains act1→act4→act5 both branches, store
  price/trust/blockade rules, save round-trip + CRC tamper rejection, 12 build
  simulations, data-only monster/spell add.
- `plamen shot` → scripted graphical smoke on X: title/chargen/hub/combat
  screenshots (`shot_*.png`), fought and killed a War-Banner Cultist, died, death
  rules fired (corpse + lost XP logged), 60 FPS.
- `DISPLAY= plamen` → loud fatal, RC=2.

## Status vs the brief
First Playable (section 7) is implemented end-to-end: chargen (5 races × 6
classes, hardcore toggle) → Cinderhold hub → open areas → 5+ monster types with
telegraphs → death rules (corpse-run / Dagny / reload) → affix loot → leveling +
skill points → Compact store with trust prices → quests whose flags change later
NPC/faction/store state. Acts 2-5 exist as data (quests, rules, bosses, maps,
dialogs) and the consequence engine is proven headless; full playthrough of acts
2-5 is content-complete but not yet hand-playtested end to end.
