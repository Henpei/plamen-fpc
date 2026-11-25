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

## Rendering approach (v0.2 — TRUE 3D, per the revised contract §6)
- Fixed-angle **orthographic 3D camera** via raylib `BeginMode3D`: classic 2:1
  dimetric (elevation atan(1/2) ≈ 26.565°, azimuth 45°), `up = +Z`,
  `camera.projection = CAMERA_ORTHOGRAPHIC`, `fovy` = ortho height in world
  units (23). World coords: x east, y south, z up; one tile = 1×1 world unit.
  Camera follows the player (+ optional shake offset).
- **Real 3D geometry with textured surfaces.** One hand-built unit-cube mesh
  (24 verts / 12 tris, CCW outward faces, uploaded with `UploadMesh`) is
  scaled/rotated per draw call (`DrawMesh` + `MatrixTranslate/Scale/RotateZ`)
  with per-material textures: per-tileset floor slabs and extruded wall boxes,
  trunk + canopy boxes for trees, rock boxes, water slabs, glowing portal
  columns. Tiles outside the ortho view range are culled. NOTE: raylib 6.2's
  `GenMesh*` functions SIGFPE'd sporadically when called from Pascal (integer
  div-by-zero inside the C lib; FPC unmasks FP exceptions), so no `GenMesh*`
  is used — the cube is emitted vertex-by-vertex (`render.BuildCubeMesh`,
  winding verified via screenshots).
- **Textures: procedural-only, deterministic.** 64×64 images generated at
  startup with a local xorshift (game RNG untouched): ground noise, brick,
  rock, wood grain, water waves, glass streaks, snow — one set per tileset for
  floor + wall, plus shared rock/trunk/canopy/water/portal/under-void
  materials. Entity silhouettes are generated 64×64 billboard textures cached
  per id. CC0 asset download was blocked by the sandbox network policy; the
  brief explicitly allows procedural textures, so this is the deliberate,
  documented pipeline (loader seam for future CC0 files: `LoadTexture`, already
  bound; bundle under `assets/tex/` and credit in this README).
- Characters/props are camera-facing billboards (`DrawBillboard`) over a ground
  shadow disc; projectiles are glowing spheres; telegraphs are 3D ground discs
  + rings (`DrawCircle3D`/`DrawLine3D`); the click-to-move marker is a fading
  gold ground ring. The depth buffer handles occlusion (no painter sort in 3D).
- After `EndMode3D`, a 2D pass draws names/HP bars/quest markers/damage numbers
  via `GetWorldToScreen`. Mouse picking: `GetScreenToWorldRay` (raylib 6.x
  name — `GetMouseRay` no longer exists) intersected with the z≈0 ground plane.
- Color language (silhouette-first): player sky-blue, enemies element-colored,
  boss maroon + horns, telegraph orange, loot/quest gold, NPC green, cursor
  ring white/red/gold/green/gray by state.
- HUD every frame: HP/MP/Stamina/XP bars, 8-slot quickbar, quest tracker, minimap,
  gold/points, cursor-state label, and **build evidence:
  `PLAMEN <commit> | map=<id> "name" | region=.. act=.. | fps=.. | ents=..`**,
  always.

## Architecture
- Strict split: `core`, `data`, `reg`, `sim`, `maps`, `selftest` **never touch
  raylib**; only `render.pas` + `plamen.dpr` do. This is what makes
  `plamen selftest` a real headless suite (RC=0, logs to `selftest.log`).
  Boundary audited before the v0.2 rebuild (2026-11-25): `grep -ril raylib
  src/` = render/plamen/raylib only; all 54 input polls live in `render.pas`;
  `maps.pas` `WorldToScreen/ScreenToWorld` are pure math, unused by selftest,
  left in place (3D picking lives in render). The v0.2 renderer+input swap was
  therefore surgical: only `render.pas` + `raylib.pas` changed; zero logic
  lines moved, so every selftest still maps 1:1.
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

## Controls (v0.2 — POINT-AND-CLICK is the primary scheme, per revised §4.6/4.12)
- **LMB click = context order**: enemy → chase + attack; NPC/store/chest/lore/
  marker → walk there and act (acts immediately if already close); ground →
  click-to-move (fading gold ring marker at the click point). **Hold LMB on
  ground = sweep-move** (marker follows the cursor).
- **RMB** on enemy = attack; **hold RMB (or K) = block**; **SPACE = dodge-step**
  with i-frames toward facing. **1-8 = quickbar** aimed at the cursor.
- Hover: cursor ring shows state — white `move`, red `attack`, gold `talk`,
  green `interact`, gray `--` unavailable (blocked/out of map) — plus the
  hovered entity's name.
- Pure-keyboard path: **TAB** cycles targets nearest-first (purple ring),
  **ENTER/J** acts on the selected target, **E** interacts nearest,
  **WASD/arrows** remain only as an accessibility movement aid (never primary).
- I inventory · C character/build · Q quest log · L lore log · ESC pause ·
  F1 help · F3/F4/F5 toggles (shake, telegraphs, damage numbers) · F10 screenshot.

## Verification evidence
- `make selftest` → `plamen selftest` → **82 passed, 0 failed, RC=0**
  (`selftest.log`): stat formulas, element wheel, combat math, XP/levels, loot
  tables + affix rolls, quest chains act1→act4→act5 both branches, store
  price/trust/blockade rules, save round-trip + CRC tamper rejection, 12 build
  simulations, data-only monster/spell add.
- `plamen shot` → scripted graphical smoke on X driving the real point-and-click
  command path: title/chargen/hub/combat screenshots (`shot_*.png`);
  `CmdMoveTo` marker visible in shot_hub, `CmdAttackEnt` chase+fight in
  shot_combat (War-Banner killed, then player died, death rules fired — corpse +
  lost XP), 60 FPS, HUD shows `PLAMEN <commit> | map=.. | region=.. act=.. | fps`.
- Renderer verified visually: ortho 2:1 3D scene, textured tiles/walls/props,
  billboards, telegraph decals (screenshots inspected, not just RC-checked).
- `DISPLAY= plamen` → loud fatal, RC=2.

## Status vs the brief
First Playable (section 7) is implemented end-to-end: chargen (5 races × 6
classes, hardcore toggle) → Cinderhold hub → open areas → 5+ monster types with
telegraphs → death rules (corpse-run / Dagny / reload) → affix loot → leveling +
skill points → Compact store with trust prices → quests whose flags change later
NPC/faction/store state. Acts 2-5 exist as data (quests, rules, bosses, maps,
dialogs) and the consequence engine is proven headless; full playthrough of acts
2-5 is content-complete but not yet hand-playtested end to end.
