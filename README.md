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

## Rendering approach (v0.3 — stylized low-poly 3D ARPG, Diablo-3-family target, per RENDER REBUILD 2)
- Fixed-angle **orthographic 3D camera** via raylib `BeginMode3D`: classic 2:1
  dimetric (elevation atan(1/2) ≈ 26.565°, azimuth 45°), `up = +Z`,
  `camera.projection = CAMERA_ORTHOGRAPHIC`, `fovy` = ortho height in world
  units (20 at zoom 0). World coords: x east, y south, z up; one tile = 1×1
  world unit. **3-step zoom** (mouse wheel / PgUp/PgDn / +/-) divides `fovy`
  by 1.45 per step; **tilt toggle (T)** switches elevation 26.565° ↔ 38°.
- **Terrain = per-tile height field**, coherent by design (per-tile noise reads
  as rubble at iso zoom): hubs are a raised-rim town plateau (rim h=0.42, flat
  bowl), areas/dungeons are broad terraced bands from two low-frequency sine
  fields quantized to 3 levels (0 / 0.42 / 0.84). Every tile is a box from z=0
  to its height → **extruded cliff faces at every step**; oriented **ramp
  slabs** are placed at walkable transitions |Δh|>0.25; water tiles are sunken
  flush channels. 6 painted procedural tilesets (floor + wall each).
- **Lighting: real shadow map.** Custom GLSL: a DEPTH shader (encodes
  `gl_FragCoord.z` into RGB) renders the scene from an ortho light camera into a
  1024×1024 `RenderTexture`; the LIT shader does directional sun + ambient +
  Blinn spec, samples the shadow map on texture slot 1 with slope-scaled bias.
  Both passes draw the same scene via `DrawMeshS` (per-draw shader swap).
- **Props and characters are real 3D meshes — no billboards, no sprite quads.**
  Hand-built meshes (never `GenMesh*`, which SIGFPEs from FPC): unit cube,
  low-poly sphere, cylinder, ground quad — all `UploadMesh`'d once.
  Trees = trunk box + 2 canopy spheres; rocks = squashed spheres; portals =
  base slab + glowing column + rotating cap. **Characters are primitive rigs**
  (legs, torso, arms, head sphere, weapon, helm/robe/horns variants) with
  per-class body plans (Hound is a hulking 1.32× tank, casters wear robes…),
  animated: walk cycle (leg/arm swing + bob), attack swing, idle bob, death
  fall; NPCs wander ambiently. Projectiles are glowing spheres.
- **Telegraphs/click markers = additive glow decals** (radial-gradient quad,
  `BLEND_ADDITIVE`) plus ground rings; damage numbers/names/HP bars stay in the
  2D pass via `GetWorldToScreen`.
- **Textures: procedural-only, deterministic** (network-fetched CC0 packs are
  blocked in this environment; the brief allows procedural). 64×64 images
  from a local xorshift (game RNG untouched): ground noise, brick, rock, wood,
  water, glass, snow, cloth, radial glow — bilinear + repeat. CC0 bundling seam
  for later: `assets/tex/` + credit here.
- **Matrix convention (verified empirically)**: raylib `TMatrix` is row-major
  (`v*M`); `MatrixMultiply(left,right)` applies **left first** — compose models
  as `Scale * Rotate * Translate`. See AGENTS.md.
- Mouse picking: `GetScreenToWorldRay` (6.x name) intersected with the local
  ground plane (`TileH`).
- Color language (silhouette-first): player blue, enemies element-colored,
  boss maroon + horns, telegraph orange→red, loot/quest gold, NPC green.
- HUD every frame: HP/MP/Stamina/XP bars, 8-slot quickbar, quest tracker,
  minimap, gold/points, cursor-state label, and **build evidence:
  `PLAMEN <commit> | map=<id> "name" | region=.. act=.. | fps=.. | ents=..`**,
  always.
- Acceptance screenshots (`./build/plamen shot`): `shot_hub.png` (hub, default
  camera, rim elevation + walking NPCs), `shot_combat.png` (player mid-swing
  vs monster, telegraph glow + ring), `shot_zoom.png` (same scene, max zoom —
  model detail, lighting/shadows). All fully 3D.
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

## Controls (v0.3 — POINT-AND-CLICK ONLY, per revised §4.6/4.12; WASD/arrow movement deleted)
- **LMB click = context order**: enemy → chase + attack; NPC/store/chest/lore/
  marker → walk there and act (acts immediately if already close); ground →
  click-to-move (fading gold ring marker at the click point). **Hold LMB on
  ground = sweep-move** (marker follows the cursor). **There is no WASD/arrow
  movement** — pointer orders are the only movement input.
- **RMB** on enemy = attack; **hold RMB (or K) = block**; **SPACE = dodge-step**
  with i-frames toward facing. **1-8 = quickbar** aimed at the cursor.
- Hover: cursor ring shows state — white `move`, red `attack`, gold `talk`,
  green `interact`, gray `--` unavailable (blocked/out of map) — plus the
  hovered entity's name.
- Pure-keyboard path (targeting/actions, not movement): **TAB** cycles targets
  nearest-first (purple ring), **ENTER/J** acts on the selected target,
  **E** interacts nearest.
- I inventory · C character/build · Q quest log · L lore log · ESC pause ·
  F1 help · F3/F4/F5 toggles (shake, telegraphs, damage numbers) · F10 screenshot.
- **Display**: window is resizable — projection/layout are computed from the
  live window size every frame (no squish at any aspect). **Mouse wheel** zooms
  the camera in 3 steps (PgUp/PgDn or +/- too), **T** toggles camera tilt,
  **F11 or Alt+Enter** toggles windowed-fullscreen (borderless on the current
  monitor via SetWindowMonitor) without restart.

## Verification evidence
- `make selftest` → `plamen selftest` → **82 passed, 0 failed, RC=0**
  (`selftest.log`): stat formulas, element wheel, combat math, XP/levels, loot
  tables + affix rolls, quest chains act1→act4→act5 both branches, store
  price/trust/blockade rules, save round-trip + CRC tamper rejection, 12 build
  simulations, data-only monster/spell add.
- `plamen shot` → scripted graphical smoke on X driving the real point-and-click
  command path: title/chargen/hub/combat/zoom screenshots (`shot_*.png`);
  `CmdMoveTo` marker visible in shot_hub, `CmdAttackEnt` fight in shot_combat
  with the monster's telegraph pinned (glow decal + range ring), same scene at
  max zoom in shot_zoom, 60 FPS, HUD shows
  `PLAMEN <commit> | map=.. | region=.. act=.. | fps` every frame.
- Display proofs in the same run: `shot_aspect43.png` (window resized to 4:3 —
  native-res render, no squish), `shot_fullscreen.png` (F11/Alt+Enter
  windowed-fullscreen via SetWindowMonitor, no restart), `shot_zoom1/2.png`
  (wheel-zoom steps 1 and 2, camera math intact).
- Renderer verified visually (human-eye on the screenshots, not just RC):
  heightfield terrain with cliffs/ramps, shadow-mapped lighting, 3D prop trees/
  rocks/portals, primitive-mesh animated character rigs (no billboards/quads),
  additive telegraph decals, damage numbers.
- `DISPLAY= plamen` → loud fatal, RC=2.

## Status vs the brief
First Playable (section 7) is implemented end-to-end: chargen (5 races × 6
classes, hardcore toggle) → Cinderhold hub → open areas → 5+ monster types with
telegraphs → death rules (corpse-run / Dagny / reload) → affix loot → leveling +
skill points → Compact store with trust prices → quests whose flags change later
NPC/faction/store state. Acts 2-5 exist as data (quests, rules, bosses, maps,
dialogs) and the consequence engine is proven headless; full playthrough of acts
2-5 is content-complete but not yet hand-playtested end to end.
