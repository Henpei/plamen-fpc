unit render;
{$mode objfpc}{$H+}
{ All raylib rendering, input, screens, HUD. The only unit besides plamen.dpr
  that touches raylib — everything else is headless-testable. }
interface

procedure RunGame(shot: Boolean);

implementation

uses SysUtils, Math, core, data, reg, sim, maps, raylib;

const
  INIT_W = 1280;   // initial window size only — ALL layout/projection/culling math
  INIT_H = 720;    // uses the LIVE window size (ScrW/ScrH) so nothing squishes at any resolution

// live render-target size (window is resizable; fullscreen changes it too)
function ScrW: Integer;
begin
  Result := GetScreenWidth();
end;

function ScrH: Integer;
begin
  Result := GetScreenHeight();
end;

type
  TGameState = (gsTitle, gsCharGen, gsGame, gsDeath);
  TOverlay = (ovNone, ovStore, ovDialog, ovInv, ovQuests, ovLore, ovChar, ovHelp, ovPause);

  TDlgLine = record cond, text: string; choices: TStrArray; end;

var
  font: TFont;
  state: TGameState = gsTitle;
  overlay: TOverlay = ovNone;
  shake: Single = 0;
  optShake, optTelegraph, optDmgNum: Boolean;
  shotMode: Boolean;
  shotFrame: Integer;
  // windowed-fullscreen state (F11 / Alt+Enter)
  gFullscreen: Boolean = False;
  gPrevWX, gPrevWY, gPrevWW, gPrevWH, gPrevMon: Integer;
  // chargen
  cgName: string;
  cgRace, cgClass: Integer;
  cgHardcore: Boolean;
  cgCursor: Integer;
  // dialog
  dlgNpc, dlgSec: string;
  dlgCursor: Integer;
  dlgLines: array of TDlgLine;
  // store
  storeCursor, storeMode: Integer;
  // generic
  listCursor: Integer;
  mouseWX, mouseWY: Single;
  mouseActive: Boolean;
  msg: string;
  msgT: Single;
  autosaveErr: string;

{ ---------------- helpers ---------------- }

procedure Say(const s: string);
begin
  msg := s;
  msgT := 4;
  Log('UI: ' + s);
end;

function FontPath: string;
var
  c: array[0..5] of string;
  i: Integer;
begin
  c[0] := '/usr/share/fonts/TTF/DejaVuSans.ttf';
  c[1] := '/usr/share/fonts/TTF/DejaVuSansMono.ttf';
  c[2] := '/usr/share/fonts/liberation/LiberationSans-Regular.ttf';
  c[3] := '/usr/share/fonts/TTF/DejaVuSansCondensed.ttf';
  c[4] := '/usr/share/fonts/noto/NotoSans-Regular.ttf';
  c[5] := '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf';
  for i := 0 to 5 do
    if FileExistsOS(c[i]) then Exit(c[i]);
  Fatal('no usable TTF font found in candidate list (loud, no fallback)');
end;

procedure LoadGameFont;
var
  cps: array of Integer;
  i: Integer;
begin
  SetLength(cps, 95 + 11);
  for i := 0 to 94 do cps[i] := 32 + i;
  cps[95] := $E5; cps[96] := $E4; cps[97] := $F6;   // å ä ö
  cps[98] := $C5; cps[99] := $C4; cps[100] := $D6;  // Å Ä Ö
  cps[101] := $2014; cps[102] := $2019; cps[103] := $201C; cps[104] := $201D;
  cps[105] := $2026; cps[106] := $B7;
  font := LoadFontEx(PAnsiChar(FontPath), 32, @cps[0], Length(cps));
  if not IsFontValid(font) then Fatal('font failed to load: ' + FontPath);
  Log('font loaded: ' + FontPath);
end;

procedure Text(x, y, size: Integer; const s: string; col: TColor);
var
  pos: TVector2;
begin
  pos.x := x; pos.y := y;
  DrawTextEx(font, PAnsiChar(s), pos, size, 1, col);
end;

function TextW(const s: string; size: Integer): Integer;
var
  v: TVector2;
begin
  v := MeasureTextEx(font, PAnsiChar(s), size, 1);
  Result := Round(v.x);
end;

procedure TextC(cx, y, size: Integer; const s: string; col: TColor);
begin
  Text(cx - TextW(s, size) div 2, y, size, s, col);
end;

function Subst(const s: string): string;
begin
  Result := s;
  Result := StringReplace(Result, '{PLAYER}', GPlayer.name, [rfReplaceAll]);
  Result := StringReplace(Result, '{DAGNY_PRICE}', I2S(GPlayer.level * 50), [rfReplaceAll]);
  Result := StringReplace(Result, '{COMPACT_TRUST}', FlagGet(GPlayer.flags, 'compact.trust'), [rfReplaceAll]);
end;

function IIfC(cond: Boolean; a, b: TColor): TColor;
begin
  if cond then Result := a else Result := b;
end;

function IIfS2(cond: Boolean; const a, b: string): string;
begin
  if cond then Result := a else Result := b;
end;

function MkCol(r, g, b: Integer): TColor;
begin
  Result.r := r; Result.g := g; Result.b := b; Result.a := 255;
end;

function MkColA(r, g, b, a: Integer): TColor;
begin
  Result.r := r; Result.g := g; Result.b := b; Result.a := a;
end;

function MkRec(x, y, w, h: Single): TRectangle;
begin
  Result.x := x; Result.y := y; Result.width := w; Result.height := h;
end;

function MkV(x, y: Single): TVector2;
begin
  Result.x := x; Result.y := y;
end;

procedure Panel(x, y, w, h: Integer; title: string);
begin
  DrawRectangleRec(MkRec(x, y, w, h), Fade(BLACK, 0.82));
  DrawRectangleLinesEx(MkRec(x, y, w, h), 2, RAYWHITE);
  if title <> '' then
  begin
    DrawRectangle(x, y, w, 22, DARKGRAY);
    Text(x + 8, y + 3, 16, title, RAYWHITE);
  end;
end;


{ ---------------- world — v3: stylized low-poly 3D ARPG renderer ----------------
  Fully 3D, textured, LIT with a real shadow map. Fixed-angle orthographic camera
  (default classic 2:1 dimetric; zoom 3 steps via wheel/PgUp/PgDn/+/-; tilt toggle T).
  Terrain = per-tile height field (plateaus, cliffs with extruded box faces, ramps at
  transitions, water channels). Props = trunk+canopy trees, rocks, portal columns.
  Characters = primitive-mesh rigs (legs/torso/head/arms/weapon), NO billboards;
  walk cycle, attack swing, idle bob, death fall; per-class body plans for the player.
  Telegraphs/click markers = additive glow decals (soft radial texture). Damage
  numbers stay world-to-screen above heads. Boundary: this unit is the ONLY game
  code touching raylib besides plamen.dpr; sim/reg/data/maps/selftest untouched. }

const
  CAM_DIST = 26.0;
  CAM_FOVY = 20.0;          // base ortho height (world units) at zoom level 0
  NTILESETS = 6;
  SHADOW_SIZE = 1024;
  SUN_DIR: array[0..2] of Single = (0.45, 0.45, 0.76); // direction TO the sun (normalized at init)

type
  TMoveMark = record x, y, t: Single; end;
  TFx = record phase, atk, dead, seed: Single; lastState: Integer; end;
  PFx = ^TFx;
  TBodyPlan = record scale, shoulder, torsoH, weapLen: Single; helm, robe: Boolean; end;

var
  cam3: TCamera3D;
  lightCam3: TCamera3D;
  animT: Single = 0;
  lastAnimT: Single = 0;
  texRnd: UInt64 = 88172645463325252;
  zoomLevel: Integer = 0;
  tiltOn: Boolean = False;
  curFovy: Single = CAM_FOVY;
  // meshes
  gCube, gSphere, gCyl, gQuad: TMesh;
  // materials (all use gLitShader in the main pass)
  gFloorMat, gWallMat: array[0..NTILESETS-1] of TMaterial;
  gMatRock, gMatTrunk, gMatCanopy, gMatWater, gMatPortal, gMatUnder: TMaterial;
  gMatBody, gMatSkin, gMatWeapon, gMatTrim, gMatGlow: TMaterial;
  // shaders + shadow map
  gLitShader, gDepthShader: TShader;
  locLightDir, locLightColor, locAmbient, locViewPos, locShadowVP, locShadowMap: Integer;
  shadowRT: TRenderTexture2D;
  shadowVP: TMatrix;
  sunDir: TVector3;
  // per-entity anim state (render-side only)
  entFx: array of TFx;
  pFxPhase, pFxAtk, pFxDead: Single;
  lastPX, lastPY: Single;
  moveMarks: array of TMoveMark;
  lastMX, lastMY: Single;
  hoverEnt: Integer = -1;
  cursorState: Integer = 0; // 0=move 1=attack 2=talk 3=interact 4=unavailable
  // point-and-click order state
  moveTX, moveTY: Single;
  hasMove: Boolean = False;
  attackTgt: Integer = -1;
  interactTgt: Integer = -1;
  kbTgt: Integer = -1;
  kbSel: Integer = 0;
  kbList: array of Integer;
  stuckX, stuckY, stuckT: Single;
  gActiveShader: TShader;

function ElemCol(const elem: string): TColor; forward;
function HasQuestFor(const npcId: string): Boolean; forward;

function NextRnd: UInt64;
begin
  texRnd := texRnd xor (texRnd shl 13);
  texRnd := texRnd xor (texRnd shr 7);
  texRnd := texRnd xor (texRnd shl 17);
  Result := texRnd;
end;

function V3(x, y, z: Single): TVector3;
begin
  Result.x := x; Result.y := y; Result.z := z;
end;

function V3Norm(v: TVector3): TVector3;
var
  l: Single;
begin
  l := Sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
  if l < 1e-9 then l := 1;
  Result.x := v.x / l; Result.y := v.y / l; Result.z := v.z / l;
end;

function V3Cross(a, b: TVector3): TVector3;
begin
  Result.x := a.y * b.z - a.z * b.y;
  Result.y := a.z * b.x - a.x * b.z;
  Result.z := a.x * b.y - a.y * b.x;
end;

function TilesetIdx(const ts: string): Integer;
begin
  if ts = 'emberfall' then Result := 0
  else if ts = 'veil' then Result := 1
  else if ts = 'glass' then Result := 2
  else if ts = 'maren' then Result := 3
  else if ts = 'crown' then Result := 4
  else Result := 5;
end;

{ ================= procedural textures ================= }

function FinishTex(img: TImage): TTexture2D;
begin
  Result := LoadTextureFromImage(img);
  SetTextureFilter(Result, TEXTURE_FILTER_BILINEAR);
  SetTextureWrap(Result, TEXTURE_WRAP_REPEAT);
  UnloadImage(img);
end;

procedure NoisePass(var img: TImage; w, h: Integer; dark, light: TColor; pDark, pLight: Integer);
var
  x, y, n: Integer;
begin
  for y := 0 to h - 1 do
    for x := 0 to w - 1 do
    begin
      n := Integer(NextRnd mod 100);
      if n < pDark then
        ImageDrawPixel(@img, x, y, Fade(dark, 0.55))
      else if n < pDark + pLight then
      begin
        n := Integer(NextRnd mod 20) - 10;
        ImageDrawPixel(@img, x, y, MkCol(ClampI(light.r + n, 0, 255), ClampI(light.g + n, 0, 255), ClampI(light.b + n, 0, 255)));
      end;
    end;
end;

function GenTexGround(base, speck: TColor): TTexture2D;
var
  img: TImage;
begin
  img := GenImageColor(64, 64, base);
  NoisePass(img, 64, 64, MkCol(0, 0, 0), speck, 9, 4);
  Result := FinishTex(img);
end;

function GenTexBrick(brick, mortar: TColor): TTexture2D;
var
  img: TImage;
  row, bx, off: Integer;
begin
  img := GenImageColor(64, 64, mortar);
  for row := 0 to 7 do
  begin
    off := 0;
    if (row mod 2) = 1 then off := 8;
    for bx := -1 to 4 do
      ImageDrawRectangle(@img, bx * 16 + off + 1, row * 8 + 1, 14, 6, brick);
  end;
  NoisePass(img, 64, 64, MkCol(0, 0, 0), brick, 18, 5);
  Result := FinishTex(img);
end;

function GenTexRock(base: TColor): TTexture2D;
var
  img: TImage;
  i, cx, cy, r: Integer;
begin
  img := GenImageColor(64, 64, base);
  for i := 0 to 14 do
  begin
    cx := Integer(NextRnd mod 64); cy := Integer(NextRnd mod 64); r := 3 + Integer(NextRnd mod 9);
    ImageDrawCircleV(@img, MkV(cx, cy), r, MkCol(ClampI(base.r - 25, 0, 255), ClampI(base.g - 25, 0, 255), ClampI(base.b - 25, 0, 255)));
  end;
  NoisePass(img, 64, 64, MkCol(0, 0, 0), base, 20, 4);
  Result := FinishTex(img);
end;

function GenTexWood(base: TColor): TTexture2D;
var
  img: TImage;
  x, y, plank: Integer;
begin
  img := GenImageColor(64, 64, base);
  for x := 0 to 63 do
  begin
    plank := x div 16;
    for y := 0 to 63 do
      if (x mod 16 = 0) or (Integer(NextRnd mod 100) < 6) then
        ImageDrawPixel(@img, x, y, MkCol(ClampI(base.r - 40 - plank * 6, 0, 255), ClampI(base.g - 34, 0, 255), ClampI(base.b - 24, 0, 255)))
      else if Integer(NextRnd mod 100) < 8 then
        ImageDrawPixel(@img, x, y, MkCol(ClampI(base.r + 22, 0, 255), ClampI(base.g + 18, 0, 255), ClampI(base.b + 12, 0, 255)));
  end;
  Result := FinishTex(img);
end;

function GenTexWater: TTexture2D;
var
  img: TImage;
  x, y, v: Integer;
begin
  img := GenImageColor(64, 64, MkCol(28, 96, 160));
  for y := 0 to 63 do
    for x := 0 to 63 do
    begin
      v := Round(24 * Sin((y + 8 * Sin(x * 0.3)) * 0.35));
      if v > 8 then ImageDrawPixel(@img, x, y, MkCol(120, 190, 235));
    end;
  Result := FinishTex(img);
end;

function GenTexGlass: TTexture2D;
var
  img: TImage;
  x, y: Integer;
begin
  img := GenImageColor(64, 64, MkCol(148, 178, 190));
  for y := 0 to 63 do
    for x := 0 to 63 do
      if ((x + y) mod 16 < 2) or ((x - y + 64) mod 24 < 2) then
        ImageDrawPixel(@img, x, y, MkCol(215, 235, 240));
  NoisePass(img, 64, 64, MkCol(90, 110, 120), MkCol(190, 215, 225), 10, 6);
  Result := FinishTex(img);
end;

function GenTexSnow: TTexture2D;
var
  img: TImage;
begin
  img := GenImageColor(64, 64, MkCol(206, 216, 228));
  NoisePass(img, 64, 64, MkCol(160, 172, 190), MkCol(240, 246, 252), 16, 8);
  Result := FinishTex(img);
end;

function GenTexCloth(base: TColor): TTexture2D;
var
  img: TImage;
begin
  img := GenImageColor(64, 64, base);
  NoisePass(img, 64, 64, MkCol(ClampI(base.r - 30, 0, 255), ClampI(base.g - 30, 0, 255), ClampI(base.b - 30, 0, 255)),
    MkCol(ClampI(base.r + 25, 0, 255), ClampI(base.g + 25, 0, 255), ClampI(base.b + 25, 0, 255)), 14, 8);
  Result := FinishTex(img);
end;

// soft radial glow for additive decals (white center -> transparent edge)
function GenTexGlow: TTexture2D;
var
  img: TImage;
  x, y: Integer;
  dx, dy, d: Single;
  a: Byte;
begin
  img := GenImageColor(64, 64, BLANK);
  for y := 0 to 63 do
    for x := 0 to 63 do
    begin
      dx := x - 31.5; dy := y - 31.5;
      d := Sqrt(dx * dx + dy * dy) / 31.5;
      if d < 1.0 then
      begin
        a := Round(255 * (1.0 - d) * (1.0 - d));
        ImageDrawPixel(@img, x, y, MkColA(255, 255, 255, a));
      end;
    end;
  Result := LoadTextureFromImage(img);
  SetTextureFilter(Result, TEXTURE_FILTER_BILINEAR);
  UnloadImage(img);
end;

{ ================= hand-built meshes (no GenMesh* — see AGENTS.md) ================= }

procedure AddFace(var verts, norms: array of Single; var uvs: array of Single;
  var idx: array of Word; var nv, ni: Integer;
  const a, b, c, d: TVector3; const n: TVector3);
var
  base: Integer;
begin
  base := nv;
  verts[nv * 3] := a.x; verts[nv * 3 + 1] := a.y; verts[nv * 3 + 2] := a.z; Inc(nv);
  verts[nv * 3] := b.x; verts[nv * 3 + 1] := b.y; verts[nv * 3 + 2] := b.z; Inc(nv);
  verts[nv * 3] := c.x; verts[nv * 3 + 1] := c.y; verts[nv * 3 + 2] := c.z; Inc(nv);
  verts[nv * 3] := d.x; verts[nv * 3 + 1] := d.y; verts[nv * 3 + 2] := d.z; Inc(nv);
  norms[base * 3] := n.x; norms[base * 3 + 1] := n.y; norms[base * 3 + 2] := n.z;
  norms[(base + 1) * 3] := n.x; norms[(base + 1) * 3 + 1] := n.y; norms[(base + 1) * 3 + 2] := n.z;
  norms[(base + 2) * 3] := n.x; norms[(base + 2) * 3 + 1] := n.y; norms[(base + 2) * 3 + 2] := n.z;
  norms[(base + 3) * 3] := n.x; norms[(base + 3) * 3 + 1] := n.y; norms[(base + 3) * 3 + 2] := n.z;
  uvs[base * 2] := 0; uvs[base * 2 + 1] := 0;
  uvs[(base + 1) * 2] := 1; uvs[(base + 1) * 2 + 1] := 0;
  uvs[(base + 2) * 2] := 1; uvs[(base + 2) * 2 + 1] := 1;
  uvs[(base + 3) * 2] := 0; uvs[(base + 3) * 2 + 1] := 1;
  idx[ni] := base; idx[ni + 1] := base + 1; idx[ni + 2] := base + 2;
  idx[ni + 3] := base; idx[ni + 4] := base + 2; idx[ni + 5] := base + 3;
  ni := ni + 6;
end;

procedure BuildCubeMesh;
var
  verts, norms: array[0..71] of Single;
  uvs: array[0..47] of Single;
  idx: array[0..35] of Word;
  nv, ni: Integer;
begin
  nv := 0; ni := 0;
  AddFace(verts, norms, uvs, idx, nv, ni, V3(0.5, -0.5, 0.5), V3(0.5, -0.5, -0.5), V3(0.5, 0.5, -0.5), V3(0.5, 0.5, 0.5), V3(1, 0, 0));
  AddFace(verts, norms, uvs, idx, nv, ni, V3(-0.5, -0.5, -0.5), V3(-0.5, -0.5, 0.5), V3(-0.5, 0.5, 0.5), V3(-0.5, 0.5, -0.5), V3(-1, 0, 0));
  AddFace(verts, norms, uvs, idx, nv, ni, V3(-0.5, 0.5, 0.5), V3(0.5, 0.5, 0.5), V3(0.5, 0.5, -0.5), V3(-0.5, 0.5, -0.5), V3(0, 1, 0));
  AddFace(verts, norms, uvs, idx, nv, ni, V3(-0.5, -0.5, -0.5), V3(0.5, -0.5, -0.5), V3(0.5, -0.5, 0.5), V3(-0.5, -0.5, 0.5), V3(0, -1, 0));
  AddFace(verts, norms, uvs, idx, nv, ni, V3(-0.5, -0.5, 0.5), V3(0.5, -0.5, 0.5), V3(0.5, 0.5, 0.5), V3(-0.5, 0.5, 0.5), V3(0, 0, 1));
  AddFace(verts, norms, uvs, idx, nv, ni, V3(-0.5, -0.5, -0.5), V3(-0.5, 0.5, -0.5), V3(0.5, 0.5, -0.5), V3(0.5, -0.5, -0.5), V3(0, 0, -1));
  gCube := Default(TMesh);
  gCube.vertexCount := 24;
  gCube.triangleCount := 12;
  gCube.vertices := GetMem(24 * 3 * SizeOf(Single));
  gCube.normals := GetMem(24 * 3 * SizeOf(Single));
  gCube.texcoords := GetMem(24 * 2 * SizeOf(Single));
  gCube.indices := GetMem(36 * SizeOf(Word));
  Move(verts[0], gCube.vertices^, 24 * 3 * SizeOf(Single));
  Move(norms[0], gCube.normals^, 24 * 3 * SizeOf(Single));
  Move(uvs[0], gCube.texcoords^, 24 * 2 * SizeOf(Single));
  Move(idx[0], gCube.indices^, 36 * SizeOf(Word));
  UploadMesh(gCube, False);
end;

// low-poly sphere (radius r, rings x slices), centered origin
procedure BuildSphereMesh(r: Single; rings, slices: Integer);
var
  verts, norms, uvs: array of Single;
  idx: array of Word;
  i, j, nv, ni: Integer;
  phi0, phi1, th0, th1: Single;
  v00, v01, v10, v11: TVector3;
  function SV(phi, th: Single): TVector3;
  begin
    Result.x := r * Sin(phi) * Cos(th);
    Result.y := r * Sin(phi) * Sin(th);
    Result.z := r * Cos(phi);
  end;
  procedure PushV(v: TVector3; u, vv: Single);
  begin
    SetLength(verts, Length(verts) + 3);
    verts[High(verts) - 2] := v.x; verts[High(verts) - 1] := v.y; verts[High(verts)] := v.z;
    SetLength(norms, Length(norms) + 3);
    norms[High(norms) - 2] := v.x / r; norms[High(norms) - 1] := v.y / r; norms[High(norms)] := v.z / r;
    SetLength(uvs, Length(uvs) + 2);
    uvs[High(uvs) - 1] := u; uvs[High(uvs)] := vv;
    Inc(nv);
  end;
  procedure PushT(a, b, c: Integer);
  begin
    SetLength(idx, Length(idx) + 3);
    idx[High(idx) - 2] := a; idx[High(idx) - 1] := b; idx[High(idx)] := c;
    ni := ni + 3;
  end;
begin
  verts := nil; norms := nil; uvs := nil; idx := nil;
  nv := 0; ni := 0;
  for i := 0 to rings - 1 do
  begin
    phi0 := Pi * i / rings;
    phi1 := Pi * (i + 1) / rings;
    for j := 0 to slices - 1 do
    begin
      th0 := 2 * Pi * j / slices;
      th1 := 2 * Pi * (j + 1) / slices;
      v00 := SV(phi0, th0); v01 := SV(phi0, th1);
      v10 := SV(phi1, th0); v11 := SV(phi1, th1);
      if i > 0 then
      begin
        PushV(v00, j / slices, i / rings); PushV(v10, j / slices, (i + 1) / rings);
        PushV(v11, (j + 1) / slices, (i + 1) / rings);
        PushT(nv - 3, nv - 2, nv - 1);
      end;
      if i < rings - 1 then
      begin
        PushV(v00, j / slices, i / rings); PushV(v11, (j + 1) / slices, (i + 1) / rings);
        PushV(v01, (j + 1) / slices, i / rings);
        PushT(nv - 3, nv - 2, nv - 1);
      end;
    end;
  end;
  gSphere := Default(TMesh);
  gSphere.vertexCount := nv;
  gSphere.triangleCount := ni div 3;
  gSphere.vertices := GetMem(nv * 3 * SizeOf(Single));
  gSphere.normals := GetMem(nv * 3 * SizeOf(Single));
  gSphere.texcoords := GetMem(nv * 2 * SizeOf(Single));
  gSphere.indices := GetMem(ni * SizeOf(Word));
  if nv > 0 then
  begin
    Move(verts[0], gSphere.vertices^, nv * 3 * SizeOf(Single));
    Move(norms[0], gSphere.normals^, nv * 3 * SizeOf(Single));
    Move(uvs[0], gSphere.texcoords^, nv * 2 * SizeOf(Single));
    Move(idx[0], gSphere.indices^, ni * SizeOf(Word));
  end;
  UploadMesh(gSphere, False);
end;

// cylinder along Z (z-up world), radius r, height h, centered origin
procedure BuildCylMesh(r, h: Single; slices: Integer);
var
  verts, norms, uvs: array of Single;
  idx: array of Word;
  j, nv, ni: Integer;
  th0, th1: Single;
  procedure PushV(x, y, z, nx, ny, nz, u, vv: Single);
  begin
    SetLength(verts, Length(verts) + 3);
    verts[High(verts) - 2] := x; verts[High(verts) - 1] := y; verts[High(verts)] := z;
    SetLength(norms, Length(norms) + 3);
    norms[High(norms) - 2] := nx; norms[High(norms) - 1] := ny; norms[High(norms)] := nz;
    SetLength(uvs, Length(uvs) + 2);
    uvs[High(uvs) - 1] := u; uvs[High(uvs)] := vv;
    Inc(nv);
  end;
  procedure PushT(a, b, c: Integer);
  begin
    SetLength(idx, Length(idx) + 3);
    idx[High(idx) - 2] := a; idx[High(idx) - 1] := b; idx[High(idx)] := c;
    ni := ni + 3;
  end;
begin
  verts := nil; norms := nil; uvs := nil; idx := nil;
  nv := 0; ni := 0;
  for j := 0 to slices - 1 do
  begin
    th0 := 2 * Pi * j / slices;
    th1 := 2 * Pi * (j + 1) / slices;
    // side quad
    PushV(r * Cos(th0), r * Sin(th0), -h / 2, Cos(th0), Sin(th0), 0, j / slices, 0);
    PushV(r * Cos(th1), r * Sin(th1), -h / 2, Cos(th1), Sin(th1), 0, (j + 1) / slices, 0);
    PushV(r * Cos(th1), r * Sin(th1), h / 2, Cos(th1), Sin(th1), 0, (j + 1) / slices, 1);
    PushV(r * Cos(th0), r * Sin(th0), h / 2, Cos(th0), Sin(th0), 0, j / slices, 1);
    PushT(nv - 4, nv - 3, nv - 2); PushT(nv - 4, nv - 2, nv - 1);
    // top cap
    PushV(0, 0, h / 2, 0, 0, 1, 0.5, 0.5);
    PushV(r * Cos(th0), r * Sin(th0), h / 2, 0, 0, 1, 0.5 + 0.5 * Cos(th0), 0.5 + 0.5 * Sin(th0));
    PushV(r * Cos(th1), r * Sin(th1), h / 2, 0, 0, 1, 0.5 + 0.5 * Cos(th1), 0.5 + 0.5 * Sin(th1));
    PushT(nv - 3, nv - 2, nv - 1);
    // bottom cap
    PushV(0, 0, -h / 2, 0, 0, -1, 0.5, 0.5);
    PushV(r * Cos(th1), r * Sin(th1), -h / 2, 0, 0, -1, 0.5 + 0.5 * Cos(th1), 0.5 + 0.5 * Sin(th1));
    PushV(r * Cos(th0), r * Sin(th0), -h / 2, 0, 0, -1, 0.5 + 0.5 * Cos(th0), 0.5 + 0.5 * Sin(th0));
    PushT(nv - 3, nv - 2, nv - 1);
  end;
  gCyl := Default(TMesh);
  gCyl.vertexCount := nv;
  gCyl.triangleCount := ni div 3;
  gCyl.vertices := GetMem(nv * 3 * SizeOf(Single));
  gCyl.normals := GetMem(nv * 3 * SizeOf(Single));
  gCyl.texcoords := GetMem(nv * 2 * SizeOf(Single));
  gCyl.indices := GetMem(ni * SizeOf(Word));
  if nv > 0 then
  begin
    Move(verts[0], gCyl.vertices^, nv * 3 * SizeOf(Single));
    Move(norms[0], gCyl.normals^, nv * 3 * SizeOf(Single));
    Move(uvs[0], gCyl.texcoords^, nv * 2 * SizeOf(Single));
    Move(idx[0], gCyl.indices^, ni * SizeOf(Word));
  end;
  UploadMesh(gCyl, False);
end;

// flat 1x1 quad in XZ plane at z=0 (for glow decals)
procedure BuildQuadMesh;
var
  verts, norms: array[0..11] of Single;
  uvs: array[0..7] of Single;
  idx: array[0..5] of Word;
begin
  verts[0] := -0.5; verts[1] := -0.5; verts[2] := 0;
  verts[3] := 0.5;  verts[4] := -0.5; verts[5] := 0;
  verts[6] := 0.5;  verts[7] := 0.5;  verts[8] := 0;
  verts[9] := -0.5; verts[10] := 0.5; verts[11] := 0;
  norms[0] := 0; norms[1] := 0; norms[2] := 1;
  norms[3] := 0; norms[4] := 0; norms[5] := 1;
  norms[6] := 0; norms[7] := 0; norms[8] := 1;
  norms[9] := 0; norms[10] := 0; norms[11] := 1;
  uvs[0] := 0; uvs[1] := 0; uvs[2] := 1; uvs[3] := 0; uvs[4] := 1; uvs[5] := 1; uvs[6] := 0; uvs[7] := 1;
  idx[0] := 0; idx[1] := 1; idx[2] := 2; idx[3] := 0; idx[4] := 2; idx[5] := 3;
  gQuad := Default(TMesh);
  gQuad.vertexCount := 4;
  gQuad.triangleCount := 2;
  gQuad.vertices := GetMem(12 * SizeOf(Single));
  gQuad.normals := GetMem(12 * SizeOf(Single));
  gQuad.texcoords := GetMem(8 * SizeOf(Single));
  gQuad.indices := GetMem(6 * SizeOf(Word));
  Move(verts[0], gQuad.vertices^, 12 * SizeOf(Single));
  Move(norms[0], gQuad.normals^, 12 * SizeOf(Single));
  Move(uvs[0], gQuad.texcoords^, 8 * SizeOf(Single));
  Move(idx[0], gQuad.indices^, 6 * SizeOf(Word));
  UploadMesh(gQuad, False);
end;

{ ================= shaders ================= }

const
  LIT_VS: string =
    '#version 330' + #10 +
    'in vec3 vertexPosition;' + #10 +
    'in vec2 vertexTexCoord;' + #10 +
    'in vec3 vertexNormal;' + #10 +
    'uniform mat4 mvp;' + #10 +
    'uniform mat4 matModel;' + #10 +
    'uniform mat4 shadowVP;' + #10 +
    'out vec2 vUv;' + #10 +
    'out vec3 vN;' + #10 +
    'out vec3 vW;' + #10 +
    'out vec4 vSh;' + #10 +
    'void main(){' + #10 +
    '  vec4 w = matModel * vec4(vertexPosition, 1.0);' + #10 +
    '  vW = w.xyz;' + #10 +
    '  vUv = vertexTexCoord;' + #10 +
    '  vN = normalize(mat3(matModel) * vertexNormal);' + #10 +
    '  vSh = shadowVP * w;' + #10 +
    '  gl_Position = mvp * vec4(vertexPosition, 1.0);' + #10 +
    '}';

  LIT_FS: string =
    '#version 330' + #10 +
    'in vec2 vUv;' + #10 +
    'in vec3 vN;' + #10 +
    'in vec3 vW;' + #10 +
    'in vec4 vSh;' + #10 +
    'uniform sampler2D texture0;' + #10 +
    'uniform vec4 colDiffuse;' + #10 +
    'uniform vec3 lightDir;' + #10 +
    'uniform vec3 lightColor;' + #10 +
    'uniform vec3 ambient;' + #10 +
    'uniform vec3 viewPos;' + #10 +
    'uniform sampler2D shadowMap;' + #10 +
    'out vec4 fragColor;' + #10 +
    'void main(){' + #10 +
    '  vec4 alb = texture(texture0, vUv) * colDiffuse;' + #10 +
    '  if (alb.a < 0.04) discard;' + #10 +
    '  vec3 N = normalize(vN);' + #10 +
    '  vec3 L = normalize(lightDir);' + #10 +
    '  float diff = max(dot(N, L), 0.0);' + #10 +
    '  float shadow = 1.0;' + #10 +
    '  vec3 sc = vSh.xyz / vSh.w * 0.5 + 0.5;' + #10 +
    '  if (sc.x >= 0.0 && sc.x <= 1.0 && sc.y >= 0.0 && sc.y <= 1.0 && sc.z <= 1.0) {' + #10 +
    '    vec4 s = texture(shadowMap, sc.xy);' + #10 +
    '    float d = s.r + s.g / 256.0 + s.b / 65536.0;' + #10 +
    '    float bias = 0.0028 + 0.008 * (1.0 - diff);' + #10 +
    '    if (sc.z - bias > d) shadow = 0.34;' + #10 +
    '  }' + #10 +
    '  vec3 V = normalize(viewPos - vW);' + #10 +
    '  vec3 H = normalize(L + V);' + #10 +
    '  float spec = pow(max(dot(N, H), 0.0), 24.0) * 0.18;' + #10 +
    '  vec3 col = alb.rgb * (ambient + lightColor * diff * shadow) + lightColor * spec * shadow;' + #10 +
    '  fragColor = vec4(col, alb.a);' + #10 +
    '}';

  DEPTH_VS: string =
    '#version 330' + #10 +
    'in vec3 vertexPosition;' + #10 +
    'uniform mat4 mvp;' + #10 +
    'void main(){ gl_Position = mvp * vec4(vertexPosition, 1.0); }';

  DEPTH_FS: string =
    '#version 330' + #10 +
    'out vec4 fragColor;' + #10 +
    'void main(){' + #10 +
    '  float d = gl_FragCoord.z;' + #10 +
    '  fragColor = vec4(d, fract(d * 256.0), fract(d * 65536.0), 1.0);' + #10 +
    '}';

procedure InitShaders;
begin
  gLitShader := LoadShaderFromMemory(PAnsiChar(LIT_VS), PAnsiChar(LIT_FS));
  gDepthShader := LoadShaderFromMemory(PAnsiChar(DEPTH_VS), PAnsiChar(DEPTH_FS));
  if (gLitShader.id = 0) or (gDepthShader.id = 0) then
    Fatal('shader compile failed (lit/depth) — loud, no fallback');
  locLightDir := GetShaderLocation(gLitShader, 'lightDir');
  locLightColor := GetShaderLocation(gLitShader, 'lightColor');
  locAmbient := GetShaderLocation(gLitShader, 'ambient');
  locViewPos := GetShaderLocation(gLitShader, 'viewPos');
  locShadowVP := GetShaderLocation(gLitShader, 'shadowVP');
  locShadowMap := GetShaderLocation(gLitShader, 'shadowMap');
  shadowRT := LoadRenderTexture(SHADOW_SIZE, SHADOW_SIZE);
  sunDir := V3Norm(V3(SUN_DIR[0], SUN_DIR[1], SUN_DIR[2]));
  Log('shaders ready: lit(dir+ambient+shadowmap) + depth-encode, shadowRT ' + I2S(SHADOW_SIZE));
end;

{ ================= materials / assets ================= }

function NewMat(tex: TTexture2D; tint: TColor): TMaterial;
begin
  Result := LoadMaterialDefault;
  Result.shader := gLitShader;
  SetMaterialTexture(@Result, MATERIAL_MAP_ALBEDO, tex);
  Result.maps[0].color := tint;
end;

procedure InitWorldAssets;
begin
  rlDisableBackfaceCulling; // hand-built meshes: don't rely on winding
  InitShaders;
  BuildCubeMesh;
  BuildSphereMesh(0.5, 5, 7);
  BuildCylMesh(0.5, 1.0, 7);
  BuildQuadMesh;
  gMatRock := NewMat(GenTexRock(MkCol(128, 118, 106)), WHITE);
  gMatTrunk := NewMat(GenTexWood(MkCol(96, 72, 48)), WHITE);
  gMatCanopy := NewMat(GenTexGround(MkCol(34, 92, 42), MkCol(22, 62, 28)), WHITE);
  gMatWater := NewMat(GenTexWater, Fade(WHITE, 0.8));
  gMatPortal := NewMat(GenTexGround(MkCol(255, 203, 0), MkCol(255, 240, 150)), WHITE);
  gMatUnder := NewMat(GenTexGround(MkCol(14, 12, 18), MkCol(30, 26, 36)), WHITE);
  gMatBody := NewMat(GenTexCloth(MkCol(150, 150, 160)), WHITE);
  gMatSkin := NewMat(GenTexGround(MkCol(235, 205, 170), MkCol(210, 180, 145)), WHITE);
  gMatWeapon := NewMat(GenTexGround(MkCol(120, 125, 135), MkCol(80, 84, 92)), WHITE);
  gMatTrim := NewMat(GenTexGround(MkCol(90, 70, 40), MkCol(60, 46, 28)), WHITE);
  gMatGlow := NewMat(GenTexGlow, WHITE);
  gFloorMat[0] := NewMat(GenTexGround(MkCol(126, 110, 96), MkCol(74, 62, 54)), WHITE);
  gWallMat[0] := NewMat(GenTexBrick(MkCol(78, 66, 60), MkCol(36, 30, 27)), MkCol(255, 230, 214));
  gFloorMat[1] := NewMat(GenTexGround(MkCol(58, 98, 62), MkCol(36, 68, 42)), WHITE);
  gWallMat[1] := NewMat(GenTexBrick(MkCol(64, 72, 52), MkCol(30, 36, 24)), WHITE);
  gFloorMat[2] := NewMat(GenTexGlass, WHITE);
  gWallMat[2] := NewMat(GenTexRock(MkCol(140, 162, 174)), MkCol(230, 245, 255));
  gFloorMat[3] := NewMat(GenTexGround(MkCol(92, 118, 140), MkCol(58, 82, 106)), WHITE);
  gWallMat[3] := NewMat(GenTexBrick(MkCol(112, 122, 136), MkCol(48, 56, 68)), MkCol(210, 225, 240));
  gFloorMat[4] := NewMat(GenTexSnow, WHITE);
  gWallMat[4] := NewMat(GenTexRock(MkCol(168, 182, 202)), MkCol(235, 242, 255));
  gFloorMat[5] := NewMat(GenTexGround(MkCol(100, 132, 68), MkCol(66, 98, 46)), WHITE);
  gWallMat[5] := NewMat(GenTexRock(MkCol(112, 102, 86)), WHITE);
  Log('world assets v3 ready: meshes (cube/sphere/cyl/quad), 6 tilesets, lit materials');
end;

{ ================= draw helper (shader swap into material) ================= }

procedure DrawMeshS(var mesh: TMesh; var mat: TMaterial; const model: TMatrix);
var
  saved: TShader;
begin
  saved := mat.shader;
  mat.shader := gActiveShader;
  DrawMesh(mesh, mat, model);
  mat.shader := saved;
end;

procedure DrawBox(var mat: TMaterial; x, y, z, sx, sy, sz, rz: Single);
var
  tm, ts, tr: TMatrix;
begin
  // raylib matrices are row-major (v*M, LEFT operand applied first):
  // model = Scale * Rotate * Translate
  ts := MatrixScale(sx, sy, sz);
  if rz <> 0 then
  begin
    tr := MatrixRotateZ(rz);
    ts := MatrixMultiply(ts, tr);
  end;
  tm := MatrixMultiply(ts, MatrixTranslate(x, y, z));
  DrawMeshS(gCube, mat, tm);
end;

{ ================= terrain height field ================= }

function TileH(x, y: Integer): Single;
var
  ch: Char;
  d, lvl: Integer;
begin
  if (x < 0) or (y < 0) or (x >= GMap.w) or (y >= GMap.h) then Exit(1.3);
  ch := GMap.rows[y][x + 1];
  if ch = '#' then Exit(1.3);
  if ch = '~' then Exit(0.0);
  // Coherent height field (per-tile noise reads as rubble at iso zoom):
  //  - hubs: raised rim around a flat bowl -> town plateau, cliff + ramp at the drop
  //  - areas/dungeons: broad terraced bands (sin fields) -> cliffs at steps, ramps at edges
  if GMap.kind = 'hub' then
  begin
    d := x; if y < d then d := y;
    if (GMap.w - 1 - x) < d then d := GMap.w - 1 - x;
    if (GMap.h - 1 - y) < d then d := GMap.h - 1 - y;
    if d <= 2 then Exit(0.42) else Exit(0.0);
  end;
  lvl := Round(1.1 + 1.15 * Sin(x * 0.19 + y * 0.13) + 0.85 * Sin(x * 0.061 - y * 0.083 + 1.7));
  lvl := ClampI(lvl, 0, 2);
  Result := lvl * 0.42;
end;

function WalkableTile(x, y: Integer): Boolean;
var
  ch: Char;
begin
  if (x < 0) or (y < 0) or (x >= GMap.w) or (y >= GMap.h) then Exit(False);
  ch := GMap.rows[y][x + 1];
  Result := not (ch in ['#', 'T', '^']);
end;

{ ================= camera ================= }

procedure UpdateCamera;
var
  d, phi, ch, sh, sx, sy: Single;
begin
  d := CAM_DIST;
  curFovy := CAM_FOVY / (1 + zoomLevel * 0.45);
  if tiltOn then phi := 38.0 else phi := 26.565;
  phi := phi * Pi / 180;
  ch := Cos(phi) * 0.7071;
  sh := Sin(phi);
  sx := 0; sy := 0;
  if optShake and (shake > 0) then
  begin
    // NB: NextRnd is UInt64 — cast BEFORE subtracting or the underflow flies the camera to 1e17
    sx := (Integer(NextRnd mod 100) - 50) / 100 * shake * 0.35;
    sy := (Integer(NextRnd mod 100) - 50) / 100 * shake * 0.35;
  end;
  cam3.position := V3(GPlayer.x + ch * d + sx, GPlayer.y + ch * d + sy, sh * d);
  cam3.target := V3(GPlayer.x, GPlayer.y, 0.3);
  cam3.up := V3(0, 0, 1);
  cam3.fovy := curFovy;
  cam3.projection := CAMERA_ORTHOGRAPHIC;
end;

procedure UpdateLightCam;
var
  cx, cy, s: Single;
begin
  cx := GMap.w / 2; cy := GMap.h / 2;
  s := Max(GMap.w, GMap.h) * 0.75 + 6;
  lightCam3.position := V3(cx + sunDir.x * 60, cy + sunDir.y * 60, sunDir.z * 60);
  lightCam3.target := V3(cx, cy, 0);
  lightCam3.up := V3(0, 0, 1);
  lightCam3.fovy := 2 * s;
  lightCam3.projection := CAMERA_ORTHOGRAPHIC;
  shadowVP := MatrixMultiply(MatrixLookAt(lightCam3.position, lightCam3.target, lightCam3.up), MatrixOrtho(-s, s, -s, s, 0.01, 200));
end;

procedure MouseToWorld(mx, my: Single; out wx, wy: Single);
var
  ray: TRay;
  t: Single;
begin
  ray := GetScreenToWorldRay(MkV(mx, my), cam3);
  if Abs(ray.direction.z) < 1e-6 then
  begin
    wx := GPlayer.x; wy := GPlayer.y;
    Exit;
  end;
  t := (0.02 - ray.position.z) / ray.direction.z;
  wx := ray.position.x + ray.direction.x * t;
  wy := ray.position.y + ray.direction.y * t;
end;

procedure DrawGroundRing(cx, cy, r, z: Single; col: TColor);
var
  i: Integer;
  a0, a1: Single;
begin
  for i := 0 to 27 do
  begin
    a0 := i / 28 * 2 * Pi;
    a1 := (i + 1) / 28 * 2 * Pi;
    DrawLine3D(V3(cx + Cos(a0) * r, cy + Sin(a0) * r, z), V3(cx + Cos(a1) * r, cy + Sin(a1) * r, z), col);
  end;
end;

// additive soft glow quad on the ground
procedure DrawGlow(x, y, z, r: Single; col: TColor);
var
  tm: TMatrix;
begin
  gMatGlow.maps[0].color := col;
  tm := MatrixMultiply(MatrixScale(r * 2, r * 2, 1), MatrixTranslate(x, y, z));
  DrawMeshS(gQuad, gMatGlow, tm);
end;

{ ================= body plans / character rigs ================= }

function BodyPlan(const classId: string): TBodyPlan;
begin
  Result.scale := 1.12; Result.shoulder := 0.24; Result.torsoH := 0.5;
  Result.weapLen := 0.7; Result.helm := False; Result.robe := False;
  if classId = 'wardancer' then begin Result.scale := 0.95; Result.shoulder := 0.24; Result.weapLen := 0.72; end
  else if classId = 'emberweaver' then begin Result.robe := True; Result.weapLen := 0.95; end
  else if classId = 'runeforger' then begin Result.shoulder := 0.28; Result.robe := True; Result.weapLen := 0.6; end
  else if classId = 'shadowpact' then begin Result.scale := 0.95; Result.robe := True; Result.weapLen := 0.66; end
  else if classId = 'wardens_hound' then begin Result.scale := 1.32; Result.shoulder := 0.36; Result.torsoH := 0.62; Result.helm := True; Result.weapLen := 0.85; end
  else if classId = 'lightbinder' then begin Result.scale := 0.95; Result.robe := True; Result.weapLen := 0.5; end;
end;

// draw a humanoid rig from primitives; base = world matrix at feet; anim: phase (walk), atk (0..1 swing), dead (0..1 fall)
procedure DrawRig(const base: TMatrix; plan: TBodyPlan; bodyCol, skinCol: TColor;
  walkPhase, atk, dead: Single; moving: Boolean; boss: Boolean);
var
  m, m2, rot: TMatrix;
  swing, bob, armSwing, legSwing: Single;
  s: Single;
begin
  s := plan.scale;
  swing := 0;
  if moving then swing := Sin(walkPhase) * 0.55;
  if moving then bob := Abs(Sin(walkPhase)) * 0.05 else bob := Sin(animT * 2 + 1) * 0.02;
  // attack swing overrides right arm
  armSwing := -swing * 0.8;
  if atk > 0 then armSwing := -2.3 + atk * 3.0;
  legSwing := swing;
  gMatBody.maps[0].color := bodyCol;
  gMatSkin.maps[0].color := skinCol;
  // NOTE: raylib TMatrix is row-major (v*M, LEFT operand applied first), so every
  // chain below is built as Scale * offset * rotation * base (scale applied first,
  // world base last). Verified empirically — see AGENTS.md.
  // legs (pivot at hip z=0.46*s)
  m := MatrixMultiply(MatrixTranslate(0.11 * s, 0, 0.46 * s), base);
  m := MatrixMultiply(MatrixRotateX(legSwing), m);
  m := MatrixMultiply(MatrixTranslate(0, 0, -0.21 * s), m);
  DrawMeshS(gCube, gMatBody, MatrixMultiply(MatrixScale(0.14 * s, 0.14 * s, 0.44 * s), m));
  m := MatrixMultiply(MatrixTranslate(-0.11 * s, 0, 0.46 * s), base);
  m := MatrixMultiply(MatrixRotateX(-legSwing), m);
  m := MatrixMultiply(MatrixTranslate(0, 0, -0.21 * s), m);
  DrawMeshS(gCube, gMatBody, MatrixMultiply(MatrixScale(0.14 * s, 0.14 * s, 0.44 * s), m));
  // torso
  m := MatrixMultiply(MatrixTranslate(0, 0, (0.46 + plan.torsoH / 2) * s + bob), base);
  DrawMeshS(gCube, gMatBody, MatrixMultiply(MatrixScale((plan.shoulder * 2 + 0.08) * s, 0.22 * s, plan.torsoH * s), m));
  // robe (casters/npcs): cone-ish cylinder over torso+legs
  if plan.robe then
  begin
    m := MatrixMultiply(MatrixTranslate(0, 0, 0.5 * s + bob), base);
    DrawMeshS(gCyl, gMatBody, MatrixMultiply(MatrixScale(0.34 * s, 0.34 * s, 1.0 * s), m));
  end;
  // arms (pivot at shoulder z=0.88*s)
  m := MatrixMultiply(MatrixTranslate(plan.shoulder * s + 0.06 * s, 0, 0.88 * s + bob), base);
  m := MatrixMultiply(MatrixRotateX(-legSwing * 0.8), m);
  m := MatrixMultiply(MatrixTranslate(0, 0, -0.2 * s), m);
  DrawMeshS(gCube, gMatBody, MatrixMultiply(MatrixScale(0.11 * s, 0.11 * s, 0.42 * s), m));
  // right arm + weapon
  m := MatrixMultiply(MatrixTranslate(-(plan.shoulder * s + 0.06 * s), 0, 0.88 * s + bob), base);
  m := MatrixMultiply(MatrixRotateX(armSwing), m);
  m := MatrixMultiply(MatrixTranslate(0, 0, -0.2 * s), m);
  DrawMeshS(gCube, gMatBody, MatrixMultiply(MatrixScale(0.11 * s, 0.11 * s, 0.42 * s), m));
  // weapon in right hand
  m2 := MatrixMultiply(MatrixTranslate(-(plan.shoulder * s + 0.06 * s), 0, 0.88 * s + bob), base);
  m2 := MatrixMultiply(MatrixRotateX(armSwing), m2);
  m2 := MatrixMultiply(MatrixTranslate(0, 0, -0.42 * s), m2);
  DrawMeshS(gCube, gMatWeapon, MatrixMultiply(MatrixScale(0.05 * s, 0.05 * s, plan.weapLen * s), m2));
  // head
  m := MatrixMultiply(MatrixTranslate(0, 0, (0.46 + plan.torsoH + 0.16) * s + bob), base);
  DrawMeshS(gSphere, gMatSkin, MatrixMultiply(MatrixScale(0.3 * s, 0.3 * s, 0.32 * s), m));
  // helm
  if plan.helm then
  begin
    m := MatrixMultiply(MatrixTranslate(0, 0, (0.46 + plan.torsoH + 0.3) * s + bob), base);
    DrawMeshS(gCube, gMatWeapon, MatrixMultiply(MatrixScale(0.34 * s, 0.34 * s, 0.16 * s), m));
  end;
  // boss horns
  if boss then
  begin
    m := MatrixMultiply(MatrixTranslate(0.12 * s, 0, (0.46 + plan.torsoH + 0.32) * s + bob), base);
    rot := MatrixRotate(V3Norm(V3(0.3, 0.8, 1)), 0.5);
    DrawMeshS(gCube, gMatTrim, MatrixMultiply(MatrixScale(0.07 * s, 0.07 * s, 0.3 * s), MatrixMultiply(rot, m)));
    m := MatrixMultiply(MatrixTranslate(-0.12 * s, 0, (0.46 + plan.torsoH + 0.32) * s + bob), base);
    rot := MatrixRotate(V3Norm(V3(-0.3, 0.8, 1)), 0.5);
    DrawMeshS(gCube, gMatTrim, MatrixMultiply(MatrixScale(0.07 * s, 0.07 * s, 0.3 * s), MatrixMultiply(rot, m)));
  end;
end;

{ ================= scene geometry (drawn in shadow pass + main pass) ================= }

procedure DrawTerrainAndProps;
var
  x, y, i, v: Integer;
  ts: Integer;
  rng: Single;
  x0, x1, y0, y1: Integer;
  ch: Char;
  h, h2: Single;
  dx, dy: Integer;
  axis: TVector3;
  ang: Single;
  tm: TMatrix;
begin
  ts := TilesetIdx(GMap.tileset);
  rng := curFovy * 0.5 * (1 + ScrW / ScrH) * 0.9 + 4;
  x0 := ClampI(Trunc(GPlayer.x - rng), 0, GMap.w - 1);
  x1 := ClampI(Trunc(GPlayer.x + rng), 0, GMap.w - 1);
  y0 := ClampI(Trunc(GPlayer.y - rng), 0, GMap.h - 1);
  y1 := ClampI(Trunc(GPlayer.y + rng), 0, GMap.h - 1);
  // void skirt
  DrawBox(gMatUnder, GMap.w / 2, GMap.h / 2, -0.35, GMap.w + 16, GMap.h + 16, 0.5, 0);
  // tiles (boxes from z=0 to h -> cliff faces at transitions)
  for y := y0 to y1 do
    for x := x0 to x1 do
    begin
      ch := TileAt(x, y);
      h := TileH(x, y);
      if ch = '~' then
        DrawBox(gMatWater, x + 0.5, y + 0.5, -0.07, 1, 1, 0.14, 0) // sunken channel, flush top
      else
      begin
        v := (x * 73 + y * 151) mod 3;
        DrawBox(gFloorMat[ts], x + 0.5, y + 0.5, h / 2, 1, 1, h, v * 0.19);
        if ch = 'o' then
          DrawBox(gMatRock, x + 0.42 + v * 0.12, y + 0.45 + v * 0.1, h + 0.22, 0.5, 0.5, 0.44, v * 0.68);
      end;
    end;
  // ramps at height transitions between walkable tiles
  for y := y0 to y1 do
    for x := x0 to x1 do
    begin
      if not WalkableTile(x, y) then Continue;
      h := TileH(x, y);
      for i := 0 to 1 do
      begin
        dx := 0; dy := 0;
        if i = 0 then dx := 1 else dy := 1;
        if not WalkableTile(x + dx, y + dy) then Continue;
        h2 := TileH(x + dx, y + dy);
        if Abs(h2 - h) > 0.25 then
        begin
          axis := V3Norm(V3Cross(V3(0, 0, 1), V3(dx, dy, 0)));
          // ramp top surface must run from h (own tile) up/down to h2 (neighbor):
          // with axis = z x d, a NEGATIVE angle raises the +d end when h2 > h
          ang := -ArcSin(ClampF((h2 - h) / 1.4, -0.95, 0.95));
          tm := MatrixMultiply(MatrixScale(1.4, 1.15, 0.12),
                 MatrixMultiply(MatrixRotate(axis, ang), MatrixTranslate(x + 0.5 + dx * 0.5, y + 0.5 + dy * 0.5, (h + h2) / 2)));
          DrawMeshS(gCube, gFloorMat[ts], tm);
        end;
      end;
    end;
  // walls + props
  for y := y0 to y1 do
    for x := x0 to x1 do
    begin
      ch := TileAt(x, y);
      v := (x * 73 + y * 151) mod 3;
      h := TileH(x, y);
      case ch of
        '#':
          DrawBox(gWallMat[ts], x + 0.5, y + 0.5, h / 2, 1, 1, h, v * 0.12);
        'T':
          begin
            DrawBox(gMatTrunk, x + 0.5, y + 0.5, h + 0.5, 0.3, 0.3, 1.0, v * 0.23);
            DrawMeshS(gSphere, gMatCanopy, MatrixMultiply(MatrixScale(1.3 + v * 0.2, 1.3 + v * 0.2, 1.0 + v * 0.2), MatrixTranslate(x + 0.5, y + 0.55, h + 1.15)));
            DrawMeshS(gSphere, gMatCanopy, MatrixMultiply(MatrixScale(0.9, 0.9, 0.8), MatrixTranslate(x + 0.4 + v * 0.1, y + 0.45, h + 1.55)));
          end;
        '^':
          DrawMeshS(gSphere, gMatRock, MatrixMultiply(MatrixScale(0.95, 0.95, 0.6), MatrixTranslate(x + 0.5, y + 0.5, h + 0.25)));
        'P':
          begin
            DrawBox(gMatPortal, x + 0.5, y + 0.5, h + 0.08, 0.95, 0.95, 0.16, 0);
            DrawMeshS(gCyl, gMatPortal, MatrixMultiply(MatrixScale(0.62, 0.62, 1.7), MatrixTranslate(x + 0.5, y + 0.5, h + 0.85)));
            DrawBox(gMatPortal, x + 0.5, y + 0.5, h + 1.75, 0.8, 0.8, 0.18, animT * 0.35);
          end;
      end;
    end;
end;

procedure SyncFx;
var
  i: Integer;
begin
  if Length(entFx) <> Length(GEnts) then
  begin
    SetLength(entFx, Length(GEnts));
    for i := 0 to High(entFx) do
    begin
      entFx[i].phase := 0; entFx[i].atk := 0; entFx[i].dead := 0;
      entFx[i].seed := i * 1.37; entFx[i].lastState := -1;
    end;
  end;
end;

procedure DrawEntities;
var
  i: Integer;
  e: TEnt;
  efx: PFx;
  dt, gh: Single;
  base, fallRot: TMatrix;
  plan: TBodyPlan;
  bodyCol: TColor;
  moving: Boolean;
  wx, wy: Single;
begin
  SyncFx;
  dt := animT - lastAnimT;
  if dt < 0 then dt := 0;
  if dt > 0.1 then dt := 0.1;
  for i := 0 to High(GEnts) do
  begin
    e := GEnts[i];
    efx := PFx(@entFx[i]);
    if (e.kind = ekMonster) and (not e.alive) then
    begin
      // fallen corpse: draw rig lying down, grayed
      if efx^.dead < 1 then efx^.dead := Min(1, efx^.dead + dt * 2.5);
      gh := TileH(Trunc(e.x), Trunc(e.y));
      base := MatrixMultiply(MatrixRotateX(-efx^.dead * 1.5), MatrixTranslate(e.x, e.y, gh + 0.05));
      gMatBody.maps[0].color := Fade(DARKGRAY, 0.9);
      plan.scale := 0.9 + e.size * 0.4; plan.shoulder := 0.24; plan.torsoH := 0.5;
      plan.weapLen := 0.6; plan.helm := False; plan.robe := False;
      DrawRig(base, plan, Fade(DARKGRAY, 0.9), DARKGRAY, 0, 0, efx^.dead, False, e.boss);
      Continue;
    end;
    if not e.alive then Continue;
    if e.kind = ekProjectile then
    begin
      gMatGlow.maps[0].color := ElemCol(e.pelement);
      DrawMeshS(gSphere, gMatGlow, MatrixMultiply(MatrixScale(0.3, 0.3, 0.3), MatrixTranslate(e.x, e.y, 0.32)));
      Continue;
    end;
    if (e.kind in [ekChest, ekLore, ekMarker]) and e.used then Continue;
    gh := TileH(Trunc(e.x), Trunc(e.y));
    // anim state
    moving := (e.kind = ekMonster) and (e.state in [1, 3]);
    if moving then efx^.phase := efx^.phase + dt * 7;
    if (e.kind = ekMonster) and (e.state = 3) and (efx^.lastState <> 3) then efx^.atk := 1;
    efx^.lastState := e.state;
    if efx^.atk > 0 then efx^.atk := Max(0, efx^.atk - dt * 3.2);
    // npc ambient wander (visual only)
    wx := e.x; wy := e.y;
    if e.kind = ekNpc then
    begin
      efx^.phase := efx^.phase + dt * 5;
      wx := e.x + Cos(animT * 0.35 + efx^.seed) * 0.35;
      wy := e.y + Sin(animT * 0.35 + efx^.seed) * 0.35;
      moving := True;
    end;
    base := MatrixMultiply(MatrixRotateZ(e.facing), MatrixTranslate(wx, wy, gh));
    case e.kind of
      ekMonster:
        begin
          plan.scale := 1.02 + e.size * 0.55; plan.shoulder := 0.24 + e.size * 0.15;
          plan.torsoH := 0.5 + e.size * 0.2; plan.weapLen := 0.6 + e.size * 0.3;
          plan.helm := e.boss; plan.robe := False;
          if e.element <> '' then bodyCol := ElemCol(e.element) else bodyCol := RED;
          if e.boss then bodyCol := MAROON;
          if e.enraged then bodyCol := ORANGE;
          DrawRig(base, plan, bodyCol, MkCol(220, 190, 160), efx^.phase, efx^.atk, 0, moving, e.boss);
        end;
      ekNpc:
        begin
          plan.scale := 1.12; plan.shoulder := 0.22; plan.torsoH := 0.5; plan.weapLen := 0; plan.helm := False; plan.robe := True;
          DrawRig(base, plan, MkCol(30, 110, 50), MkCol(240, 210, 170), efx^.phase, 0, 0, moving, False);
        end;
      ekChest:
        DrawBox(gMatTrunk, wx, wy, gh + 0.25, 0.6, 0.6, 0.5, 0);
      ekLore:
        DrawBox(gMatBody, wx, wy, gh + 0.3, 0.4, 0.06, 0.55, animT);
      ekMarker:
        begin
          DrawMeshS(gCyl, gMatPortal, MatrixMultiply(MatrixScale(0.3, 0.3, 0.8), MatrixTranslate(wx, wy, gh + 0.4)));
        end;
      ekStore:
        begin
          DrawBox(gMatTrunk, wx, wy, gh + 0.4, 1.1, 0.9, 0.8, 0);
          DrawBox(gMatPortal, wx, wy, gh + 0.9, 1.2, 1.0, 0.14, 0);
        end;
      ekCorpse:
        DrawRig(MatrixMultiply(MatrixRotateX(-1.5), MatrixTranslate(wx, wy, gh + 0.05)), plan, DARKGRAY, DARKGRAY, 0, 0, 1, False, False);
    end;
  end;
  // player
  if not GPlayer.dead then
  begin
    if PointDist(GPlayer.x, GPlayer.y, lastPX, lastPY) > 0.002 then
    begin
      pFxPhase := pFxPhase + dt * 8;
      lastPX := GPlayer.x; lastPY := GPlayer.y;
    end;
    if GPlayer.atkCd > 0.1 then pFxAtk := 1 - GPlayer.atkCd / 0.45 else pFxAtk := Max(0, pFxAtk - dt * 3.2);
    plan := BodyPlan(GPlayer.classId);
    base := MatrixMultiply(MatrixRotateZ(GPlayer.facing), MatrixTranslate(GPlayer.x, GPlayer.y, TileH(Trunc(GPlayer.x), Trunc(GPlayer.y))));
    DrawRig(base, plan, MkCol(70, 130, 220), MkCol(240, 210, 170), pFxPhase, pFxAtk, 0,
      (hasMove or (attackTgt >= 0) or (interactTgt >= 0)) and (PointDist(GPlayer.x, GPlayer.y, lastPX, lastPY) > 0.001), False);
  end
  else
  begin
    if pFxDead < 1 then pFxDead := Min(1, pFxDead + dt * 2.5);
    plan := BodyPlan(GPlayer.classId);
    base := MatrixMultiply(MatrixRotateX(-pFxDead * 1.5), MatrixTranslate(GPlayer.x, GPlayer.y, TileH(Trunc(GPlayer.x), Trunc(GPlayer.y)) + 0.05));
    DrawRig(base, plan, Fade(SKYBLUE, 0.7), DARKGRAY, 0, 0, pFxDead, False, False);
  end;
end;

{ ================= world draw ================= }

procedure DrawWorld;
var
  i: Integer;
  e: TEnt;
  sp: TVector2;
  ppu, r, hpw: Single;
  col: TColor;
  lightDir, lightColor, ambient, viewPos: TVector3;
begin
  UpdateLightCam;
  // ---- shadow pass ----
  BeginTextureMode(shadowRT);
  ClearBackground(WHITE);
  BeginMode3D(lightCam3);
  gActiveShader := gDepthShader;
  DrawTerrainAndProps;
  DrawEntities;
  EndMode3D;
  EndTextureMode;
  // ---- main pass ----
  ClearBackground(MkCol(24, 22, 34));
  BeginMode3D(cam3);
  gActiveShader := gLitShader;
  BeginShaderMode(gLitShader);
  lightDir := sunDir;
  lightColor := V3(1.05, 0.98, 0.86);
  ambient := V3(0.48, 0.48, 0.56);
  viewPos := cam3.position;
  SetShaderValue(gLitShader, locLightDir, @lightDir, SHADER_UNIFORM_VEC3);
  SetShaderValue(gLitShader, locLightColor, @lightColor, SHADER_UNIFORM_VEC3);
  SetShaderValue(gLitShader, locAmbient, @ambient, SHADER_UNIFORM_VEC3);
  SetShaderValue(gLitShader, locViewPos, @viewPos, SHADER_UNIFORM_VEC3);
  SetShaderValueMatrix(gLitShader, locShadowVP, shadowVP);
  rlActiveTextureSlot(1);
  rlEnableTexture(shadowRT.texture.id);
  rlSetUniformSampler(locShadowMap, 1);
  DrawTerrainAndProps;
  DrawEntities;
  EndShaderMode;
  // ---- glow decals (additive, unlit) ----
  BeginBlendMode(BLEND_ADDITIVE);
  if optTelegraph then
    for i := 0 to High(GEnts) do
    begin
      e := GEnts[i];
      if (e.kind = ekMonster) and e.alive and (e.state = 2) then
      begin
        r := e.attackRange;
        DrawGlow(e.x, e.y, TileH(Trunc(e.x), Trunc(e.y)) + 0.06, r, Fade(ORANGE, 0.55 + 0.25 * Sin(animT * 18)));
        DrawGlow(e.x, e.y, TileH(Trunc(e.x), Trunc(e.y)) + 0.07, Max(0.08, r * e.stateT / Max(0.001, e.windup)), Fade(RED, 0.9));
      end;
    end;
  for i := 0 to High(moveMarks) do
    with moveMarks[i] do
      DrawGlow(x, y, TileH(Trunc(x), Trunc(y)) + 0.06, 0.3 + 0.08 * Sin(animT * 10), Fade(GOLD, ClampF(t / 0.6, 0, 1) * 0.9));
  // portal glow rings
  for i := 0 to High(GMap.portals) do
    with GMap.portals[i] do
      DrawGlow(x + 0.5, y + 0.5, TileH(x, y) + 0.1, 0.55, Fade(GOLD, 0.4 + 0.2 * Sin(animT * 4)));
  EndBlendMode;
  // telegraph outlines
  if optTelegraph then
    for i := 0 to High(GEnts) do
    begin
      e := GEnts[i];
      if (e.kind = ekMonster) and e.alive and (e.state = 2) then
      begin
        DrawGroundRing(e.x, e.y, e.attackRange, TileH(Trunc(e.x), Trunc(e.y)) + 0.06, Fade(ORANGE, 0.9));
      end;
    end;
  EndMode3D;
  // ---- 2D label pass ----
  lastAnimT := animT;
  ppu := ScrH / curFovy;
  for i := 0 to High(GEnts) do
  begin
    e := GEnts[i];
    if not e.alive and (e.kind <> ekMonster) then Continue;
    if e.kind = ekProjectile then Continue;
    if (e.kind in [ekChest, ekLore, ekMarker]) and e.used then Continue;
    sp := GetWorldToScreen(V3(e.x, e.y, TileH(Trunc(e.x), Trunc(e.y)) + 0.1), cam3);
    if e.kind = ekMonster then
    begin
      r := (0.35 + e.size * 0.3) * ppu;
      if e.boss then r := r * 1.5;
      hpw := r * 2;
      DrawRectangle(Round(sp.x - r), Round(sp.y - 2 * r - 10), Round(hpw), 5, Fade(BLACK, 0.8));
      DrawRectangle(Round(sp.x - r), Round(sp.y - 2 * r - 10), Round(hpw * Max(0, e.hp / Max(1, e.maxhp))), 5, LIME);
      if e.boss then Text(Round(sp.x - TextW(e.name, 14) / 2), Round(sp.y - 2 * r - 26), 14, e.name, GOLD);
    end;
    if e.kind = ekNpc then
    begin
      Text(Round(sp.x - TextW(e.name, 13) / 2), Round(sp.y - 40), 13, e.name, RAYWHITE);
      if HasQuestFor(e.id) then
        Text(Round(sp.x + 8), Round(sp.y - 46), 20, '!', GOLD);
    end;
    if e.kind = ekMarker then
      Text(Round(sp.x - TextW(e.caption, 12) / 2), Round(sp.y + 6), 12, e.caption, RAYWHITE);
    if e.kind = ekStore then
      Text(Round(sp.x - 20), Round(sp.y - 34), 16, 'STORE', GOLD);
    if e.kind = ekCorpse then
      Text(Round(sp.x - TextW('corpse', 12) / 2), Round(sp.y + 4), 12, 'corpse (' + I2S(GPlayer.lostXP) + ' xp)', GRAY);
    if i = hoverEnt then
    begin
      r := 0.45 * ppu;
      DrawCircleLinesV(MkV(sp.x, sp.y - 8), r, GOLD);
    end;
    if i = kbTgt then
    begin
      r := 0.55 * ppu;
      DrawCircleLinesV(MkV(sp.x, sp.y - 8), r, PURPLE);
    end;
  end;
  if not GPlayer.dead then
  begin
    sp := GetWorldToScreen(V3(GPlayer.x, GPlayer.y, TileH(Trunc(GPlayer.x), Trunc(GPlayer.y)) + 0.1), cam3);
    Text(Round(sp.x - TextW(GPlayer.name, 13) / 2), Round(sp.y - 46), 13, GPlayer.name, RAYWHITE);
  end;
  if optDmgNum then
    for i := 0 to High(GDmgNums) do
      with GDmgNums[i] do
      begin
        sp := GetWorldToScreen(V3(x, y, TileH(Trunc(x), Trunc(y)) + 0.9 + t * 0.8), cam3);
        if crit then col := GOLD else col := RAYWHITE;
        Text(Round(sp.x - TextW(txt, 16) / 2), Round(sp.y - t * 30), 16, txt, Fade(col, 1 - t / 1.2));
      end;
end;

function ElemCol(const elem: string): TColor;
var
  ei: Integer;
begin
  ei := FindElement(elem);
  if ei >= 0 then Result := GetColor(GElements[ei].hex) else Result := GRAY;
end;

function HasQuestFor(const npcId: string): Boolean;
var
  i, qi: Integer;
begin
  for i := 0 to High(GPlayer.quests) do
    if GPlayer.quests[i].state = 'available' then
    begin
      qi := FindQuest(GPlayer.quests[i].id);
      if (qi >= 0) and (GQuests[qi].giver = npcId) then Exit(True);
    end;
  Result := False;
end;

{ ---------------- HUD ---------------- }
{ ---------------- HUD ---------------- }
{ ---------------- HUD ---------------- }

procedure DrawBar(x, y, w: Integer; frac: Single; col: TColor; const lab: string);
begin
  DrawRectangle(x, y, w, 14, BLACK);
  DrawRectangle(x, y, Round(w * ClampF(frac, 0, 1)), 14, col);
  DrawRectangleLines(x, y, w, 14, DARKGRAY);
  Text(x + 4, y + 1, 12, lab, WHITE);
end;

procedure DrawMinimap;
var
  mw, mh, x, y, i, xx: Integer;
  c: TColor;
  ex, ey: Single;
begin
  mw := 170; mh := 130;
  x := ScrW - mw - 10; y := 10;
  DrawRectangle(x - 4, y - 4, mw + 8, mh + 8, Fade(BLACK, 0.7));
  for i := 0 to GMap.h - 1 do
    for xx := 0 to GMap.w - 1 do
    begin
      case TileAt(xx, i) of
        '#', 'T', '^': c := DARKGRAY;
        '~': c := BLUE;
        'P': c := GOLD;
      else c := GRAY;
      end;
      DrawRectangle(x + xx * mw div GMap.w, y + i * mh div GMap.h, Max(1, mw div GMap.w), Max(1, mh div GMap.h), c);
    end;
  for i := 0 to High(GEnts) do
    if GEnts[i].kind = ekMonster then DrawRectangle(x + Round(GEnts[i].x * mw / GMap.w), y + Round(GEnts[i].y * mh / GMap.h), 3, 3, RED);
  DrawRectangle(x + Round(GPlayer.x * mw / GMap.w) - 2, y + Round(GPlayer.y * mh / GMap.h) - 2, 5, 5, SKYBLUE);
  Text(x, y + mh + 6, 12, GMap.name + ' (' + RegionOfMap(GMap.id) + ')', RAYWHITE);
end;

procedure DrawHUD;
var
  i, o: Integer;
  y0: Integer;
  qx, qy: Integer;
  qi: Integer;
  sp: TSpell;
  si: Integer;
  mw: TVector2;
  ccol: TColor;
  clab: string;
begin
  y0 := ScrH - 96;
  // bars
  DrawBar(10, y0, 240, GPlayer.hp / Max(1, GetStat(GPlayer, 'max_hp')), RED, 'HP ' + F2S(GPlayer.hp, 0) + '/' + F2S(GetStat(GPlayer, 'max_hp'), 0));
  DrawBar(10, y0 + 18, 240, GPlayer.mana / Max(1, GetStat(GPlayer, 'max_mana')), BLUE, 'MP ' + F2S(GPlayer.mana, 0) + '/' + F2S(GetStat(GPlayer, 'max_mana'), 0));
  DrawBar(10, y0 + 36, 240, GPlayer.stamina / Max(1, GetStat(GPlayer, 'max_stamina')), GREEN, 'ST ' + F2S(GPlayer.stamina, 0) + '/' + F2S(GetStat(GPlayer, 'max_stamina'), 0));
  // xp bar
  DrawBar(10, y0 + 54, 240, GPlayer.xp / Max(1, XPNeed(GPlayer.level)), GOLD, 'LV ' + I2S(GPlayer.level) + '  xp ' + I2S(GPlayer.xp) + '/' + I2S(XPNeed(GPlayer.level)));
  // quickbar
  for i := 0 to QUICK_SLOTS - 1 do
  begin
    DrawRectangle(260 + i * 52, y0 + 8, 46, 46, Fade(DARKGRAY, 0.9));
    DrawRectangleLines(260 + i * 52, y0 + 8, 46, 46, RAYWHITE);
    Text(264 + i * 52, y0 + 40, 11, I2S(i + 1), GRAY);
    if GPlayer.quickbar[i] <> '' then
    begin
      si := FindSpell(GPlayer.quickbar[i]);
      if si >= 0 then
      begin
        sp := GSpells[si];
        Text(264 + i * 52, y0 + 12, 12, sp.name, ElemCol(sp.element));
      end
      else
        Text(264 + i * 52, y0 + 12, 12, 'Attack', RAYWHITE);
    end;
  end;
  // gold / points
  Text(690, y0 + 40, 14, 'Gold: ' + I2S(GPlayer.gold) + '  Attr pts: ' + I2S(GPlayer.attrPoints) + '  Skill pts: ' + I2S(GPlayer.skillPoints), GOLD);
  // quest tracker
  qx := 10; qy := 10;
  Text(qx, qy, 16, 'QUESTS (Q)', GOLD);
  Inc(qy, 20);
  for i := 0 to High(GPlayer.quests) do
    if GPlayer.quests[i].state = 'active' then
    begin
      qi := FindQuest(GPlayer.quests[i].id);
      if qi >= 0 then
      begin
        Text(qx, qy, 13, '- ' + GQuests[qi].title, RAYWHITE);
        Inc(qy, 16);
        for o := 0 to High(GQuests[qi].objectives) do
          with GQuests[qi].objectives[o] do
            Text(qx + 10, qy, 12, kind + ' ' + target + ' ' + I2S(Min(GPlayer.quests[i].obj[o], count)) + '/' + I2S(count), GRAY);
        Inc(qy, 14);
      end;
    end;
  // build evidence: version + map + act/region + fps, EVERY frame
  Text(10, ScrH - 18, 13,
    'PLAMEN ' + VERSION_STAMP + ' | map=' + GMap.id + ' "' + GMap.name + '" | region=' + RegionOfMap(GMap.id) +
    ' act=' + FlagGet(GPlayer.flags, 'act') + ' | fps=' + I2S(GetFPS()) + ' | ents=' + I2S(Length(GEnts)),
    GOLD);
  // message toast
  if msgT > 0 then TextC(ScrW div 2, 60, 18, msg, YELLOW);
  DrawMinimap;
  // pointer cursor state (point-and-click): colored ring + label at cursor
  mw := GetMousePosition;
  case cursorState of
    1: begin ccol := RED; clab := 'attack'; end;
    2: begin ccol := GOLD; clab := 'talk'; end;
    3: begin ccol := GREEN; clab := 'interact'; end;
    4: begin ccol := DARKGRAY; clab := '--'; end;
  else begin ccol := RAYWHITE; clab := 'move'; end;
  end;
  DrawRing(mw, 9, 12, 0, 360, 24, ccol);
  Text(Round(mw.x) + 16, Round(mw.y) + 10, 12, clab, ccol);
  if (hoverEnt >= 0) and (hoverEnt <= High(GEnts)) then
    Text(Round(mw.x) + 16, Round(mw.y) + 24, 12, GEnts[hoverEnt].name, RAYWHITE);
end;

{ ---------------- screens ---------------- }

procedure EnterMap(const id: string; tx, ty: Integer); forward;

procedure DrawTitle;
var
  items: array[0..3] of string;
  i: Integer;
  sel: Integer;
begin
  ClearBackground(BLACK);
  TextC(ScrW div 2, 120, 64, 'PLAMEN', GOLD);
  TextC(ScrW div 2, 200, 20, 'A hardcore high fantasy isometric action RPG', RAYWHITE);
  TextC(ScrW div 2, 226, 16, 'commit ' + VERSION_STAMP + '  built ' + BUILD_TIME, GRAY);
  items[0] := 'New Game';
  items[1] := 'Continue (autosave)';
  items[2] := 'Quit';
  sel := listCursor;
  if IsKeyPressed(KEY_DOWN) then sel := (sel + 1) mod 3;
  if IsKeyPressed(KEY_UP) then sel := (sel + 2) mod 3;
  listCursor := sel;
  for i := 0 to 2 do
  begin
    if (i = 1) and (Length(SaveSlots) = 0) then
    begin
      TextC(ScrW div 2, 304 + i * 40, 20, items[i] + ' (no save)', DARKGRAY);
    end
    else
    begin
      if i = sel then DrawRectangle(ScrW div 2 - 100, 300 + i * 40, 200, 32, DARKGRAY);
      TextC(ScrW div 2, 304 + i * 40, 20, items[i], IIfC(i = sel, YELLOW, RAYWHITE));
    end;
  end;
  if IsKeyPressed(KEY_ENTER) or IsKeyPressed(KEY_KP_ENTER) then
  begin
    if listCursor = 0 then
    begin
      state := gsCharGen; cgName := ''; cgRace := 0; cgClass := 0; cgHardcore := False; cgCursor := 0; listCursor := 0;
    end
    else if listCursor = 1 then
    begin
      if LoadGame(GPlayer, 'autosave', autosaveErr) then
      begin
        EnterMap(GPlayer.mapId, -1, -1);
        state := gsGame;
        Say('Loaded autosave. commit ' + VERSION_STAMP);
      end
      else
        Say('No valid autosave: ' + autosaveErr);
    end
    else
    begin
      CloseWindow; Halt(0);
    end;
  end;
end;

procedure DrawCharGen;
var
  ch: Integer;
  i: Integer;
  sel: Integer;
  labels: array[0..4] of string;
begin
  ClearBackground(BLACK);
  TextC(ScrW div 2, 60, 40, 'CREATE CHARACTER', GOLD);
  labels[0] := 'Name: ' + cgName + '_';
  labels[1] := 'Race: < ' + GRaces[cgRace].name + ' >';
  labels[2] := 'Class: < ' + GClasses[cgClass].name + ' >';
  labels[3] := 'Hardcore (1 save, death=reload): ' + BoolToStr(cgHardcore, True);
  labels[4] := 'BEGIN';
  sel := cgCursor;
  if IsKeyPressed(KEY_DOWN) then sel := (sel + 1) mod 5;
  if IsKeyPressed(KEY_UP) then sel := (sel + 4) mod 5;
  cgCursor := sel;
  // name input
  if sel = 0 then
  begin
    ch := GetCharPressed;
    while ch > 0 do
    begin
      if (ch >= 32) and (ch < 127) and (Length(cgName) < 16) then cgName := cgName + Chr(ch);
      if (ch = 8) and (Length(cgName) > 0) then Delete(cgName, Length(cgName), 1);
      ch := GetCharPressed;
    end;
  end;
  if sel = 1 then
  begin
    if IsKeyPressed(KEY_LEFT) then cgRace := (cgRace + High(GRaces)) mod Length(GRaces);
    if IsKeyPressed(KEY_RIGHT) then cgRace := (cgRace + 1) mod Length(GRaces);
  end;
  if sel = 2 then
  begin
    if IsKeyPressed(KEY_LEFT) then cgClass := (cgClass + High(GClasses)) mod Length(GClasses);
    if IsKeyPressed(KEY_RIGHT) then cgClass := (cgClass + 1) mod Length(GClasses);
  end;
  if (sel = 3) and IsKeyPressed(KEY_ENTER) then cgHardcore := not cgHardcore;
  for i := 0 to 4 do
  begin
    if i = sel then DrawRectangle(ScrW div 2 - 220, 140 + i * 44, 440, 36, DARKGRAY);
    TextC(ScrW div 2, 146 + i * 44, 20, labels[i], IIfC(i = sel, YELLOW, RAYWHITE));
  end;
  // descriptions
  TextC(ScrW div 2, 380, 14, GRaces[cgRace].desc, GRAY);
  TextC(ScrW div 2, 402, 14, GClasses[cgClass].desc, GRAY);
  if (sel = 4) and (IsKeyPressed(KEY_ENTER) or IsKeyPressed(KEY_KP_ENTER)) then
  begin
    if cgName = '' then cgName := 'Nameless';
    NewPlayer(GPlayer, cgName, GRaces[cgRace].id, GClasses[cgClass].id, cgHardcore);
    EnterMap('cinderhold', -1, -1);
    state := gsGame;
    Say('Welcome to Plamen, ' + cgName + '. commit ' + VERSION_STAMP);
  end;
end;

{ ---------------- dialog ---------------- }

procedure LoadDialog(const npc, sec: string);
var
  cl: TStrArray;
  raw: TStrArray;
  i, j: Integer;
  parts: TStrArray;
  line: TDlgLine;
begin
  dlgNpc := npc; dlgSec := sec;
  raw := DataGetAll(GDB, 'data/dialog.dat', 'dialog:' + npc + ':' + sec, 'line');
  if Length(raw) = 0 then FatalF('no dialog section dialog:%s:%s', [npc, sec]);
  dlgLines := nil;
  for i := 0 to High(raw) do
  begin
    parts := Split(raw[i], '|');
    line.cond := ''; line.text := ''; line.choices := nil;
    if Length(parts) > 0 then line.cond := parts[0];
    if Length(parts) > 1 then line.text := parts[1];
    if Length(parts) > 2 then
    begin
      cl := Split(parts[2], ',');
      for j := 0 to High(cl) do
        if Trim(cl[j]) <> '' then
        begin
          SetLength(line.choices, Length(line.choices) + 1);
          line.choices[High(line.choices)] := Trim(cl[j]);
        end;
    end;
    SetLength(dlgLines, Length(dlgLines) + 1);
    dlgLines[High(dlgLines)] := line;
  end;
  dlgCursor := 0;
end;

function DialogCondOK(const cond: string): Boolean;
var
  kv: TStrArray;
begin
  if cond = '' then Exit(True);
  kv := SplitStr(cond, '==');
  if Length(kv) <> 2 then Exit(False);
  if kv[0] = 'act' then Result := FlagGet(GPlayer.flags, 'act') = kv[1]
  else Result := FlagGet(GPlayer.flags, kv[0]) = kv[1];
end;

procedure OpenStore(const sid: string); forward;

procedure DialogApplyChoice(const choice: string);
var
  eq: Integer;
  lab, actions: string;
  acts: TStrArray;
  i: Integer;
  kv: TStrArray;
begin
  eq := Pos('=>', choice);
  if eq < 1 then Exit;
  lab := Copy(choice, 1, eq - 1);
  actions := Copy(choice, eq + 2, Length(choice));
  acts := Split(actions, ';');
  for i := 0 to High(acts) do
  begin
    if StartsWith(acts[i], 'goto:') then dlgSec := Copy(acts[i], 6, Length(acts[i]))
    else if StartsWith(acts[i], 'set:') then
    begin
      kv := SplitStr(Copy(acts[i], 5, Length(acts[i])), '=');
      if Length(kv) = 2 then
      begin
        FlagSet(GPlayer.flags, kv[0], kv[1]);
        FireRules(GPlayer, 'flag:' + kv[0]);
      end;
    end
    else if StartsWith(acts[i], 'quest:') then QuestAccept(GPlayer, Copy(acts[i], 7, Length(acts[i])))
    else if acts[i] = 'store' then OpenStore(GMap.store)
    else if acts[i] = 'end' then overlay := ovNone;
  end;
  if overlay <> ovNone then LoadDialog(dlgNpc, dlgSec);
  QuestRefresh(GPlayer);
end;

procedure OpenDialog(const npcId: string);
var
  qi: Integer;
  i: Integer;
begin
  QuestEvent(GPlayer, 'talk', npcId);
  // auto-accept available quests from this giver
  for i := 0 to High(GPlayer.quests) do
    if GPlayer.quests[i].state = 'available' then
    begin
      qi := FindQuest(GPlayer.quests[i].id);
      if (qi >= 0) and (GQuests[qi].giver = npcId) then
      begin
        QuestAccept(GPlayer, GPlayer.quests[i].id);
        Say('Quest accepted: ' + GQuests[qi].title);
      end;
    end;
  LoadDialog(npcId, 'start');
  overlay := ovDialog;
end;

procedure DrawDialog;
var
  i, y, c: Integer;
  line: TDlgLine;
  kv: TStrArray;
  choiceCount: Integer;
  visibleChoices: array of string;
begin
  Panel(140, ScrH - 320, ScrW - 280, 300, 'Dialog — ' + dlgNpc);
  y := ScrH - 290;
  for i := 0 to High(dlgLines) do
  begin
    line := dlgLines[i];
    if not DialogCondOK(line.cond) then Continue;
    Text(160, y, 17, Subst(line.text), RAYWHITE);
    Inc(y, 26);
  end;
  // choices
  visibleChoices := nil;
  for i := 0 to High(dlgLines) do
  begin
    line := dlgLines[i];
    if not DialogCondOK(line.cond) then Continue;
    for c := 0 to High(line.choices) do
    begin
      SetLength(visibleChoices, Length(visibleChoices) + 1);
      visibleChoices[High(visibleChoices)] := line.choices[c];
    end;
  end;
  choiceCount := Length(visibleChoices);
  if choiceCount = 0 then
  begin
    SetLength(visibleChoices, 1);
    visibleChoices[0] := 'Leave=>end';
    choiceCount := 1;
  end;
  if IsKeyPressed(KEY_DOWN) then dlgCursor := (dlgCursor + 1) mod choiceCount;
  if IsKeyPressed(KEY_UP) then dlgCursor := (dlgCursor + choiceCount - 1) mod choiceCount;
  y := ScrH - 120;
  for i := 0 to High(visibleChoices) do
  begin
    kv := SplitStr(visibleChoices[i], '=>');
    if i = dlgCursor then DrawRectangle(160, y - 2, 500, 20, DARKGRAY);
    Text(168, y, 15, '> ' + kv[0], IIfC(i = dlgCursor, YELLOW, RAYWHITE));
    Inc(y, 22);
  end;
  if IsKeyPressed(KEY_ENTER) or IsKeyPressed(KEY_KP_ENTER) then
    DialogApplyChoice(visibleChoices[dlgCursor]);
end;

{ ---------------- store ---------------- }

procedure OpenStore(const sid: string);
var
  si: Integer;
begin
  si := FindStore(sid);
  if si < 0 then FatalF('unknown store %s', [sid]);
  storeCursor := 0; storeMode := 0;
  overlay := ovStore;
end;

procedure DrawStore;
var
  si, i, y, n, k, vis: Integer;
  st: TStore;
  price: Integer;
  mx, my: TVector2;
  click: Boolean;
begin
  si := FindStore(GMap.store);
  if si < 0 then begin overlay := ovNone; Exit; end;
  st := GStores[si];
  Panel(80, 60, ScrW - 160, ScrH - 140, st.name + '  (Compact trust: ' + FlagGet(GPlayer.flags, 'compact.trust') + ')  [Tab: buy/sell]  gold=' + I2S(GPlayer.gold));
  if IsKeyPressed(KEY_TAB) then storeMode := 1 - storeMode;
  Text(100, 96, 16, IIfS2(storeMode = 0, 'BUY', 'SELL'), YELLOW);
  y := 126;
  n := 0;
  if storeMode = 0 then
  begin
    for i := 0 to High(st.stock) do
    begin
      if not StoreStockVisible(GPlayer, st, i) then Continue;
      price := StorePrice(GPlayer, GMap.id, st.stock[i].itemId);
      if i = storeCursor then DrawRectangle(96, y - 3, ScrW - 200, 20, DARKGRAY);
      Text(104, y, 15, GItems[FindItem(st.stock[i].itemId)].name + '  x' + I2S(st.stock[i].qty) + '   ' + I2S(price) + 'g', IIfC(i = storeCursor, YELLOW, RAYWHITE));
      Inc(y, 22);
      Inc(n);
    end;
    if n = 0 then Text(104, y, 15, '(no stock visible at your trust level)', GRAY);
  end
  else
  begin
    for i := 0 to High(GPlayer.inv) do
    begin
      if i = storeCursor then DrawRectangle(96, y - 3, ScrW - 200, 20, DARKGRAY);
      Text(104, y, 15, GPlayer.inv[i].name + '   sell ' + I2S(SellPrice(GPlayer, GMap.id, GPlayer.inv[i])) + 'g', IIfC(i = storeCursor, YELLOW, RAYWHITE));
      Inc(y, 22);
      Inc(n);
    end;
    if n = 0 then Text(104, y, 15, '(inventory empty)', GRAY);
  end;
  if n > 0 then
  begin
    if IsKeyPressed(KEY_DOWN) then storeCursor := (storeCursor + 1) mod n;
    if IsKeyPressed(KEY_UP) then storeCursor := (storeCursor + n - 1) mod n;
    if IsKeyPressed(KEY_ENTER) or IsKeyPressed(KEY_KP_ENTER) then
    begin
      if storeMode = 0 then
      begin
        // buy
        vis := -1;
        for k := 0 to High(st.stock) do
          if StoreStockVisible(GPlayer, st, k) then
          begin
            Inc(vis);
            if vis = storeCursor then
            begin
              price := StorePrice(GPlayer, GMap.id, st.stock[k].itemId);
              if GPlayer.gold >= price then
              begin
                GPlayer.gold := GPlayer.gold - price;
                InvAdd(GPlayer, MakeItem(st.stock[k].itemId, RndRange(0, 1 + Ord(StrToIntDef(FlagGet(GPlayer.flags, 'compact.trust'), 0) >= 3)), GPlayer.level));
                Say('Bought ' + GItems[FindItem(st.stock[k].itemId)].name);
                if st.stock[k].qty > 0 then Dec(st.stock[k].qty);
              end
              else Say('Not enough gold.');
              Break;
            end;
          end;
      end
      else
      begin
        if storeCursor <= High(GPlayer.inv) then
        begin
          price := SellPrice(GPlayer, GMap.id, GPlayer.inv[storeCursor]);
          GPlayer.gold := GPlayer.gold + price;
          Say('Sold ' + GPlayer.inv[storeCursor].name + ' for ' + I2S(price) + 'g');
          Delete(GPlayer.inv, storeCursor, 1);
          if storeCursor > High(GPlayer.inv) then storeCursor := Max(0, High(GPlayer.inv));
        end;
      end;
    end;
  end;
  Text(100, ScrH - 120, 14, 'ENTER buy/sell — ESC close', GRAY);
  // mouse click support
  mx := GetMousePosition; click := IsMouseButtonPressed(MOUSE_BUTTON_LEFT);
  if click then
  begin
    if (mx.y > 120) and (mx.y < y) and (mx.x > 96) and (mx.x < ScrW - 104) then
      storeCursor := ClampI(Round((mx.y - 126) / 22), 0, n - 1);
  end;
end;

{ ---------------- inventory / char / quests / lore ---------------- }

function RARITY_COL(r: Integer): TColor; forward;

procedure DrawInventory;
var
  i, y, slotIdx: Integer;
  it: TItemInst;
  equipped: TItemInst;
begin
  Panel(60, 50, 640, ScrH - 120, 'INVENTORY  (ENTER equip, ESC close)  carry ' + I2S(Length(GPlayer.inv)) + '/' + F2S(GetStat(GPlayer, 'carry'), 0));
  y := 86;
  for i := 0 to High(GPlayer.inv) do
  begin
    it := GPlayer.inv[i];
    if i = listCursor then DrawRectangle(76, y - 3, 600, 20, DARKGRAY);
    Text(84, y, 14, RARITY_NAMES[it.rarity] + ' ' + it.name + '  [' + it.slot + ']  ' + I2S(it.price) + 'g', RARITY_COL(it.rarity));
    Inc(y, 21);
  end;
  if High(GPlayer.inv) >= 0 then
  begin
    if IsKeyPressed(KEY_DOWN) then listCursor := (listCursor + 1) mod (Length(GPlayer.inv));
    if IsKeyPressed(KEY_UP) then listCursor := (listCursor + Length(GPlayer.inv) - 1) mod (Length(GPlayer.inv));
    if IsKeyPressed(KEY_ENTER) or IsKeyPressed(KEY_KP_ENTER) then
    begin
      EquipFromInv(GPlayer, listCursor);
      if listCursor > High(GPlayer.inv) then listCursor := Max(0, High(GPlayer.inv));
      Say('Equipped.');
    end;
    // comparison tooltip
    it := GPlayer.inv[listCursor];
    slotIdx := -1;
    for i := 0 to SLOT_COUNT - 1 do
      if SLOTS[i] = it.slot then slotIdx := i;
    Text(720, 86, 14, '--- ' + it.name + ' ---', RARITY_COL(it.rarity));
    Text(720, 108, 13, 'stats: ' + it.stats, RAYWHITE);
    if (slotIdx >= 0) and (GPlayer.gear[slotIdx].base <> '') then
    begin
      equipped := GPlayer.gear[slotIdx];
      Text(720, 130, 14, 'equipped: ' + equipped.name, RARITY_COL(equipped.rarity));
      Text(720, 150, 13, 'stats: ' + equipped.stats, GRAY);
    end;
  end;
  // equipped panel
  Text(720, 200, 14, '--- EQUIPPED ---', GOLD);
  y := 222;
  for i := 0 to SLOT_COUNT - 1 do
  begin
    if GPlayer.gear[i].base <> '' then
      Text(720, y, 13, SLOTS[i] + ': ' + GPlayer.gear[i].name, RARITY_COL(GPlayer.gear[i].rarity))
    else
      Text(720, y, 13, SLOTS[i] + ': -', GRAY);
    Inc(y, 18);
  end;
end;

function RARITY_COL(r: Integer): TColor;
begin
  case r of
    0: Result := GRAY; 1: Result := RAYWHITE; 2: Result := SKYBLUE;
    3: Result := GREEN; 4: Result := PURPLE; 5: Result := GOLD;
  else Result := WHITE;
  end;
end;

procedure DrawCharSheet;
var
  taken: Boolean;
  hasReq: Boolean;
  already: Boolean;
  i, y: Integer;
  si: Integer;
begin
  Panel(60, 50, ScrW - 120, ScrH - 120, 'CHARACTER — ' + GPlayer.name + '  ' + GRaces[FindRace(GPlayer.raceId)].name + ' ' + GClasses[FindClass(GPlayer.classId)].name + '  lv ' + I2S(GPlayer.level) + '  pts: attr ' + I2S(GPlayer.attrPoints) + ' skill ' + I2S(GPlayer.skillPoints));
  y := 90;
  for i := 0 to 4 do
  begin
    Text(80, y, 15, ATTR_LABEL[i] + ': ' + I2S(GPlayer.attrs[i]) + IIfS2(GPlayer.attrPoints > 0, '  [+]', ''), RAYWHITE);
    if (GPlayer.attrPoints > 0) and (listCursor = i) and IsKeyPressed(KEY_ENTER) then
    begin
      Inc(GPlayer.attrs[i]); Dec(GPlayer.attrPoints); RecalcStats(GPlayer);
      GPlayer.hp := GetStat(GPlayer, 'max_hp');
    end;
    Inc(y, 22);
  end;
  // derived stats
  Text(80, y + 6, 14, '--- derived ---', GOLD);
  Inc(y, 26);
  for i := 0 to High(GPlayer.statCache) do
  begin
    Text(80, y, 13, GStats[FindStat(GPlayer.statCache[i].id)].name + ': ' + F2S(GPlayer.statCache[i].val, 1), RAYWHITE);
    Inc(y, 17);
    if y > ScrH - 200 then Break;
  end;
  // skills
  Text(560, 90, 14, '--- skill trees (ENTER buy if affordable & prereq) ---', GOLD);
  y := 112;
  for si := 0 to High(GSkills) do
  begin
    if (GSkills[si].tree = GPlayer.classId) or (GSkills[si].tree = 'movement') or (GSkills[si].tree = 'crafting') or (GSkills[si].tree = 'arcana') then
    begin
      taken := False;
      for i := 0 to High(GPlayer.skills) do
        if GPlayer.skills[i] = GSkills[si].id then taken := True;
      if not taken then
      begin
        if y > ScrH - 130 then Break;
        if listCursor = si then DrawRectangle(556, y - 3, ScrW - 640, 18, DARKGRAY);
        Text(564, y, 13, GSkills[si].tree + ' T' + I2S(GSkills[si].tier) + ' ' + GSkills[si].name + ' (cost ' + I2S(GSkills[si].cost) + ', req ' + GSkills[si].requires + ')', IIfC(listCursor = si, YELLOW, GRAY));
        Inc(y, 18);
      end;
    end;
  end;
  if IsKeyPressed(KEY_DOWN) then listCursor := (listCursor + 1) mod Max(1, Length(GSkills));
  if IsKeyPressed(KEY_UP) then listCursor := (listCursor + Length(GSkills) - 1) mod Max(1, Length(GSkills));
  if IsKeyPressed(KEY_ENTER) then
  begin
    si := listCursor;
    if (si <= High(GSkills)) and (GSkills[si].tree = GPlayer.classId) or ((si <= High(GSkills)) and ((GSkills[si].tree = 'movement') or (GSkills[si].tree = 'crafting') or (GSkills[si].tree = 'arcana'))) then
    begin
      if (GPlayer.skillPoints >= GSkills[si].cost) then
      begin
        hasReq := GSkills[si].requires = '';
        for i := 0 to High(GPlayer.skills) do
          if GPlayer.skills[i] = GSkills[si].requires then hasReq := True;
        already := False;
        for i := 0 to High(GPlayer.skills) do
          if GPlayer.skills[i] = GSkills[si].id then already := True;
        if hasReq and not already then
        begin
          GPlayer.skillPoints := GPlayer.skillPoints - GSkills[si].cost;
          SetLength(GPlayer.skills, Length(GPlayer.skills) + 1);
          GPlayer.skills[High(GPlayer.skills)] := GSkills[si].id;
          // unlock_spell effects
          for i := 0 to High(GSkills[si].effects) do
            if GSkills[si].effects[i].kind = 'unlock_spell' then
            begin
              SetLength(GPlayer.spells, Length(GPlayer.spells) + 1);
              GPlayer.spells[High(GPlayer.spells)] := GSkills[si].effects[i].a1;
            end;
          RecalcStats(GPlayer);
          Say('Learned ' + GSkills[si].name);
        end
        else Say('Requirements not met.');
      end
      else Say('Not enough skill points.');
    end;
  end;
end;

procedure DrawQuestLog;
var
  i, y, qi, o: Integer;
begin
  Panel(60, 50, ScrW - 120, ScrH - 120, 'QUEST LOG (ESC close)');
  y := 86;
  for i := 0 to High(GPlayer.quests) do
  begin
    if GPlayer.quests[i].state = 'locked' then Continue;
    qi := FindQuest(GPlayer.quests[i].id);
    if qi < 0 then Continue;
    Text(80, y, 14, '[' + GPlayer.quests[i].state + '] ' + GQuests[qi].title + '  (act ' + GQuests[qi].act + ')', IIfC(GPlayer.quests[i].state = 'active', YELLOW, RAYWHITE));
    Inc(y, 18);
    for o := 0 to High(GQuests[qi].objectives) do
      with GQuests[qi].objectives[o] do
      begin
        Text(96, y, 12, kind + ': ' + target + '  ' + I2S(Min(GPlayer.quests[i].obj[o], count)) + '/' + I2S(count), GRAY);
        Inc(y, 15);
      end;
    Inc(y, 6);
    if y > ScrH - 90 then Break;
  end;
end;

procedure DrawLoreLog;
var
  i, y, li, k: Integer;
begin
  Panel(60, 50, ScrW - 120, ScrH - 120, 'LORE LOG (ESC close) — reading is optional, the world does not force-feed');
  y := 86;
  for i := 0 to High(GPlayer.lore) do
  begin
    li := -1;
    for k := 0 to High(GLore) do
      if GLore[k].id = GPlayer.lore[i] then li := k;
    if li < 0 then Continue;
    Text(80, y, 14, GLore[li].title + IIfS2(GLore[li].contradicts <> '', '  [contradicts ' + GLore[li].contradicts + ']', ''), GOLD);
    Inc(y, 17);
    Text(96, y, 12, Copy(GLore[li].text, 1, 110), RAYWHITE);
    Inc(y, 22);
    if y > ScrH - 90 then Break;
  end;
end;

procedure DrawPause;
var
  i: Integer;
  items: array[0..4] of string;
begin
  Panel(ScrW div 2 - 200, 200, 400, 260, 'PAUSED');
  items[0] := 'Resume';
  items[1] := 'Save game (autosave slot)';
  items[2] := 'Toggles: shake=' + BoolToStr(optShake, True) + ' telegraphs=' + BoolToStr(optTelegraph, True) + ' dmgnum=' + BoolToStr(optDmgNum, True);
  items[3] := 'Screenshot (shot.png)';
  items[4] := 'Quit to title';
  if IsKeyPressed(KEY_DOWN) then listCursor := (listCursor + 1) mod 5;
  if IsKeyPressed(KEY_UP) then listCursor := (listCursor + 4) mod 5;
  for i := 0 to 4 do
  begin
    if i = listCursor then DrawRectangle(ScrW div 2 - 180, 240 + i * 36, 360, 30, DARKGRAY);
    TextC(ScrW div 2, 245 + i * 36, 16, items[i], IIfC(i = listCursor, YELLOW, RAYWHITE));
  end;
  if IsKeyPressed(KEY_ENTER) or IsKeyPressed(KEY_KP_ENTER) then
  begin
    case listCursor of
      0: overlay := ovNone;
      1: if SaveGame(GPlayer, 'autosave', autosaveErr) then Say('Saved.') else Say('Save failed: ' + autosaveErr);
      2: begin optShake := not optShake; optTelegraph := not optTelegraph; optDmgNum := not optDmgNum; end;
      3: begin TakeScreenshot('shot.png'); Say('Screenshot saved.'); end;
      4: begin overlay := ovNone; state := gsTitle; end;
    end;
  end;
end;

procedure DrawDeath;
var
  hub: string;
  i: Integer;
  items: array[0..2] of string;
  cost: Integer;
begin
  DrawRectangle(0, 0, ScrW, ScrH, Fade(MAROON, 0.55));
  TextC(ScrW div 2, 140, 56, 'YOU DIED', RED);
  TextC(ScrW div 2, 210, 18, 'Death is punished. The world does not scale to you.', RAYWHITE);
  TextC(ScrW div 2, 236, 16, 'Lost XP on corpse: ' + I2S(GPlayer.lostXP) + IIfS2(GPlayer.corpseLooted, '  (corpse looted by monsters — a grave robber may have your things)', ''), GRAY);
  cost := GPlayer.level * 50;
  items[0] := 'Run to your corpse (recover the XP)';
  items[1] := 'Dagny resurrect at hub (' + I2S(cost) + 'g)';
  items[2] := 'Reload autosave' + IIfS2(GPlayer.hardcore, ' (hardcore: the only option that keeps the run)', '');
  if IsKeyPressed(KEY_DOWN) then listCursor := (listCursor + 1) mod 3;
  if IsKeyPressed(KEY_UP) then listCursor := (listCursor + 2) mod 3;
  for i := 0 to 2 do
  begin
    if i = listCursor then DrawRectangle(ScrW div 2 - 260, 300 + i * 44, 520, 36, DARKGRAY);
    TextC(ScrW div 2, 306 + i * 44, 19, items[i], IIfC(i = listCursor, YELLOW, RAYWHITE));
  end;
  if IsKeyPressed(KEY_ENTER) or IsKeyPressed(KEY_KP_ENTER) then
  begin
    case listCursor of
      0: begin
        GPlayer.dead := False;
        if GPlayer.corpseMap <> GMap.id then EnterMap(GPlayer.corpseMap, -1, -1);
        GPlayer.x := GPlayer.corpseX; GPlayer.y := GPlayer.corpseY;
        GPlayer.hp := GetStat(GPlayer, 'max_hp') * 0.5;
        AddXP(GPlayer, GPlayer.lostXP);
        GPlayer.lostXP := 0;
        GPlayer.corpseMap := '';
        state := gsGame;
        Say('You reclaim your corpse.');
      end;
      1: begin
        if GPlayer.gold >= cost then
        begin
          GPlayer.gold := GPlayer.gold - cost;
          GPlayer.dead := False;
          hub := FlagGet(GPlayer.flags, 'region.emberfall.hub');
          if hub = '' then hub := 'cinderhold';
          EnterMap(hub, -1, -1);
          GPlayer.hp := GetStat(GPlayer, 'max_hp');
          GPlayer.lostXP := 0;
          state := gsGame;
          Say('Dagny knits you back together. The Choir takes its tithe.');
        end
        else Say('Not enough gold for Dagny.');
      end;
      2: begin
        if LoadGame(GPlayer, 'autosave', autosaveErr) then
        begin
          EnterMap(GPlayer.mapId, -1, -1);
          state := gsGame;
          Say('Reloaded autosave.');
        end
        else
          Fatal('autosave missing/corrupt and reload requested (hardcore law): ' + autosaveErr);
      end;
    end;
  end;
end;

procedure DrawHelp;
begin
  Panel(120, 60, ScrW - 240, ScrH - 140, 'HELP / KEYBINDS');
  Text(140, 96, 15, 'LMB click: move / attack enemy / talk-interact (context). Hold LMB on ground = sweep-move (gold ring marker).', RAYWHITE);
  Text(140, 120, 15, 'RMB on enemy = attack, hold RMB or K = block. SPACE = dodge-step (i-frames). 1-8 = quickbar aimed at cursor.', RAYWHITE);
  Text(140, 144, 15, 'Keyboard path: TAB cycle targets, ENTER/J act, E interact nearest. I C Q L F1 panels, ESC pause. F11/Alt+Enter fullscreen, wheel zoom.', RAYWHITE);
  Text(140, 168, 15, 'Cursor ring shows state: white=move red=attack gold=talk green=interact gray=unavailable. Hover shows target name.', RAYWHITE);
  Text(140, 176, 15, 'Walk onto gold portals (P) to travel. The world map connects the five regions. Wrong way = death. Intended.', GOLD);
  Text(140, 208, 15, 'Death: corpse-run, Dagny (gold), or reload. Corpses can be looted by monsters.', RAYWHITE);
  Text(140, 240, 15, 'Stores are run by the Gilded Compact: prices follow your trust and consequence flags.', RAYWHITE);
  if IsKeyPressed(KEY_ESCAPE) or IsKeyPressed(KEY_F1) then overlay := ovNone;
end;

{ ---------------- map / travel ---------------- }

procedure EnterMap(const id: string; tx, ty: Integer);
var
  err: string;
begin
  LoadMap(id);
  GMapId := id;
  GPlayer.mapId := id;
  hasMove := False; attackTgt := -1; interactTgt := -1; kbTgt := -1; moveMarks := nil;
  if (tx >= 0) and (ty >= 0) then
  begin
    GPlayer.x := tx + 0.5;
    GPlayer.y := ty + 0.5;
  end
  else
  begin
    GPlayer.x := GMap.spawnX + 0.5;
    GPlayer.y := GMap.spawnY + 0.5;
  end;
  SpawnMapEntities;
  QuestEvent(GPlayer, 'reach', id);
  QuestRefresh(GPlayer);
  if SaveGame(GPlayer, 'autosave', err) then Log('autosave ok') else Log('autosave FAILED: ' + err);
end;

{ ---------------- point-and-click input layer ----------------
  PRIMARY control: pointer-driven (Diablo/PoE style). LMB click = context order:
  enemy -> chase+attack, interactable -> walk-then-act (or act now if close),
  ground -> click-to-move (gold ring indicator, hold LMB = sweep-move).
  RMB press on enemy = attack, RMB hold (or K) = block. SPACE = dodge-step
  (i-frames). 1-8 quickbar aimed at cursor. TAB cycles nearest targets, ENTER/J
  acts on the keyboard target (pure-keyboard path). E = interact nearest.
  NO WASD/arrow movement — pointer orders only. }

procedure ClearOrders;
begin
  hasMove := False;
  attackTgt := -1;
  interactTgt := -1;
end;

function FindWalkable(var x, y: Single): Boolean;
var
  r, a: Integer;
  aa, nx, ny: Single;
begin
  if not IsBlocked(x, y) then Exit(True);
  for r := 1 to 5 do
    for a := 0 to 11 do
    begin
      aa := a / 12 * 2 * Pi;
      nx := x + Cos(aa) * r * 0.5;
      ny := y + Sin(aa) * r * 0.5;
      if (nx >= 0.2) and (ny >= 0.2) and (nx < GMap.w - 0.2) and (ny < GMap.h - 0.2) and (not IsBlocked(nx, ny)) then
      begin
        x := nx; y := ny;
        Exit(True);
      end;
    end;
  Result := False;
end;

procedure CmdMoveTo(x, y: Single);
var
  tx, ty: Single;
begin
  tx := ClampF(x, 0.2, GMap.w - 0.2);
  ty := ClampF(y, 0.2, GMap.h - 0.2);
  if not FindWalkable(tx, ty) then Exit; // blocked: cursor shows 'unavailable', no order
  moveTX := tx; moveTY := ty;
  hasMove := True;
  attackTgt := -1;
  interactTgt := -1;
  SetLength(moveMarks, Length(moveMarks) + 1);
  moveMarks[High(moveMarks)].x := tx;
  moveMarks[High(moveMarks)].y := ty;
  moveMarks[High(moveMarks)].t := 0.6;
end;

procedure CmdAttackEnt(i: Integer);
begin
  attackTgt := i;
  interactTgt := -1;
  hasMove := False;
end;

procedure CmdInteractEnt(i: Integer);
begin
  interactTgt := i;
  attackTgt := -1;
  hasMove := False;
end;

procedure ActOnEnt(i: Integer);
var
  e: TEnt;
begin
  if (i < 0) or (i > High(GEnts)) then Exit;
  e := GEnts[i];
  case e.kind of
    ekNpc: OpenDialog(e.id);
    ekStore: OpenStore(e.id);
    ekMarker, ekChest, ekLore, ekCorpse: InteractAt(GPlayer, e.x, e.y);
  end;
end;

procedure WalkToward(tx, ty, dt: Single);
var
  sp, d, nx, ny: Single;
begin
  d := PointDist(GPlayer.x, GPlayer.y, tx, ty);
  if d < 1e-4 then Exit;
  sp := GetStat(GPlayer, 'move_speed') * dt;
  nx := GPlayer.x + (tx - GPlayer.x) / d * sp;
  ny := GPlayer.y + (ty - GPlayer.y) / d * sp;
  if not IsBlocked(nx, GPlayer.y) then GPlayer.x := nx;
  if not IsBlocked(GPlayer.x, ny) then GPlayer.y := ny;
  GPlayer.facing := ArcTan2(ty - GPlayer.y, tx - GPlayer.x);
end;

procedure UpdateHover;
var
  mw: TVector2;
  i: Integer;
  best, d, r: Single;
  sp: TVector2;
  e: TEnt;
  ppu: Single;
begin
  mw := GetMousePosition;
  MouseToWorld(mw.x, mw.y, mouseWX, mouseWY);
  lastMX := mw.x; lastMY := mw.y;
  mouseActive := True;
  GPlayer.facing := ArcTan2(mouseWY - GPlayer.y, mouseWX - GPlayer.x);
  hoverEnt := -1;
  cursorState := 0;
  if (mouseWX < 0) or (mouseWY < 0) or (mouseWX >= GMap.w) or (mouseWY >= GMap.h) then
    cursorState := 4
  else
  begin
    ppu := ScrH / curFovy;
    best := 1e9;
    for i := 0 to High(GEnts) do
    begin
      e := GEnts[i];
      if not e.alive then Continue;
      if e.kind = ekProjectile then Continue;
      if (e.kind in [ekChest, ekLore, ekMarker]) and e.used then Continue;
      sp := GetWorldToScreen(V3(e.x, e.y, 0.12), cam3);
      r := (0.4 + e.size * 0.25) * ppu;
      if e.boss then r := r * 1.5;
      d := PointDist(mw.x, mw.y, sp.x, sp.y - 8);
      if (d < r + 6) and (d < best) then
      begin
        best := d;
        hoverEnt := i;
      end;
    end;
    if hoverEnt >= 0 then
    begin
      e := GEnts[hoverEnt];
      case e.kind of
        ekMonster: cursorState := 1;
        ekNpc: cursorState := 2;
      else cursorState := 3;
      end;
    end
    else if IsBlocked(mouseWX, mouseWY) then cursorState := 4;
  end;
end;

procedure UpdateGame(dt: Single);
var
  sp, nx, ny: Single;
  i, j, n, tmp: Integer;
  mw: TVector2;
  portal: TPortal;
  nearest, nd: Integer;
  e: TEnt;
  d: Single;
begin
  if overlay <> ovNone then Exit;
  if GPlayer.dead then begin state := gsDeath; listCursor := 0; Exit; end;
  UpdateHover;
  // ---- pointer orders ----
  if IsMouseButtonPressed(MOUSE_BUTTON_LEFT) then
  begin
    if hoverEnt >= 0 then
    begin
      e := GEnts[hoverEnt];
      d := PointDist(GPlayer.x, GPlayer.y, e.x, e.y);
      if e.kind = ekMonster then
        CmdAttackEnt(hoverEnt)
      else if d < 2.2 then
        ActOnEnt(hoverEnt)
      else
        CmdInteractEnt(hoverEnt);
    end
    else
      CmdMoveTo(mouseWX, mouseWY);
  end;
  // hold LMB on ground = sweep-move
  if IsMouseButtonDown(MOUSE_BUTTON_LEFT) and (attackTgt < 0) and (interactTgt < 0) and (hoverEnt < 0) then
    if hasMove and (PointDist(mouseWX, mouseWY, moveTX, moveTY) > 0.35) then
      CmdMoveTo(mouseWX, mouseWY);
  // RMB: press on enemy = attack; hold = block (K also blocks)
  if IsMouseButtonPressed(MOUSE_BUTTON_RIGHT) and (hoverEnt >= 0) and (GEnts[hoverEnt].kind = ekMonster) then
    CmdAttackEnt(hoverEnt);
  GPlayer.blockHeld := IsMouseButtonDown(MOUSE_BUTTON_RIGHT) or IsKeyDown(KEY_K);
  // dodge-step (i-frames), toward facing
  if IsKeyPressed(KEY_SPACE) then
  begin
    nx := GPlayer.x + Cos(GPlayer.facing) * 1.1;
    ny := GPlayer.y + Sin(GPlayer.facing) * 1.1;
    if not IsBlocked(nx, GPlayer.y) then GPlayer.x := nx;
    if not IsBlocked(GPlayer.x, ny) then GPlayer.y := ny;
    GPlayer.dodgeT := 0.28;
    ClearOrders;
  end;
  // quickbar 1-8, aimed at cursor
  for i := 0 to QUICK_SLOTS - 1 do
    if IsKeyPressed(KEY_ONE + i) then CastQuickbar(GPlayer, i, mouseWX, mouseWY);
  // ---- keyboard path ----
  // POINT-AND-CLICK ONLY: no WASD/arrow movement exists (deleted per contract —
  // dead movement paths are a silent-fallback risk). Keyboard remains for
  // targeting/actions/panels: TAB cycles nearest-first targets, ENTER/J acts,
  // E interacts nearest, 1-8 quickbar, SPACE dodge, RMB/K block.
  // TAB cycles nearest-first targets (pure-keyboard targeting)
  if IsKeyPressed(KEY_TAB) then
  begin
    n := 0;
    kbList := nil;
    for i := 0 to High(GEnts) do
    begin
      e := GEnts[i];
      if not e.alive then Continue;
      if e.kind = ekProjectile then Continue;
      if (e.kind in [ekChest, ekLore, ekMarker]) and e.used then Continue;
      if (e.kind = ekMonster) or (e.kind in [ekNpc, ekStore, ekChest, ekLore, ekMarker, ekCorpse]) then
      begin
        SetLength(kbList, n + 1);
        kbList[n] := i;
        Inc(n);
      end;
    end;
    for i := 1 to n - 1 do
    begin
      j := i;
      while (j > 0) and (PointDist(GPlayer.x, GPlayer.y, GEnts[kbList[j]].x, GEnts[kbList[j]].y) <
             PointDist(GPlayer.x, GPlayer.y, GEnts[kbList[j - 1]].x, GEnts[kbList[j - 1]].y)) do
      begin
        tmp := kbList[j]; kbList[j] := kbList[j - 1]; kbList[j - 1] := tmp;
        Dec(j);
      end;
    end;
    if n > 0 then
    begin
      kbSel := kbSel + 1;
      if kbSel >= n then kbSel := 0;
      kbTgt := kbList[kbSel];
    end;
  end;
  // ENTER/J: act on keyboard target, else hovered, else nearest monster
  if IsKeyPressed(KEY_ENTER) or IsKeyPressed(KEY_KP_ENTER) or IsKeyPressed(KEY_J) then
  begin
    i := kbTgt;
    if i < 0 then i := hoverEnt;
    if i < 0 then
    begin
      nearest := -1; nd := 6;
      for j := 0 to High(GEnts) do
        if (GEnts[j].kind = ekMonster) and GEnts[j].alive then
          if PointDist(GPlayer.x, GPlayer.y, GEnts[j].x, GEnts[j].y) < nd then
          begin
            nd := Round(PointDist(GPlayer.x, GPlayer.y, GEnts[j].x, GEnts[j].y) * 10);
            nearest := j;
          end;
      i := nearest;
    end;
    if i >= 0 then
    begin
      e := GEnts[i];
      d := PointDist(GPlayer.x, GPlayer.y, e.x, e.y);
      if e.kind = ekMonster then
      begin
        if d <= 1.7 + e.size + 0.4 then
        begin
          PlayerAttack(GPlayer, e.x, e.y);
          if optShake then shake := 2;
        end
        else
          CmdAttackEnt(i);
      end
      else if d < 2.2 then
        ActOnEnt(i)
      else
        CmdInteractEnt(i);
    end;
  end;
  // E: interact nearest
  if IsKeyPressed(KEY_E) then
  begin
    nearest := -1; nd := 2;
    for i := 0 to High(GEnts) do
    begin
      e := GEnts[i];
      if e.alive and (e.kind in [ekNpc, ekMarker, ekChest, ekLore, ekStore, ekCorpse]) then
        if PointDist(GPlayer.x, GPlayer.y, e.x, e.y) < nd then
        begin
          nd := Round(PointDist(GPlayer.x, GPlayer.y, e.x, e.y) * 10);
          nearest := i;
        end;
    end;
    if nearest >= 0 then ActOnEnt(nearest)
    else
    begin
      nearest := -1; nd := 1000000;
      for i := 0 to High(GEnts) do
      begin
        e := GEnts[i];
        if e.alive and (e.kind in [ekNpc, ekMarker, ekChest, ekLore, ekStore, ekCorpse]) then
          if PointDist(GPlayer.x, GPlayer.y, e.x, e.y) < nd then
          begin
            nd := Round(PointDist(GPlayer.x, GPlayer.y, e.x, e.y));
            nearest := i;
          end;
      end;
      if nearest >= 0 then CmdInteractEnt(nearest);
    end;
  end;
  // ---- execute movement orders ----
  if attackTgt >= 0 then
  begin
    if (attackTgt > High(GEnts)) or (not GEnts[attackTgt].alive) or (GEnts[attackTgt].kind <> ekMonster) then
      attackTgt := -1
    else
    begin
      e := GEnts[attackTgt];
      d := PointDist(GPlayer.x, GPlayer.y, e.x, e.y);
      if d > 1.7 + e.size + 0.4 then
        WalkToward(e.x, e.y, dt)
      else
      begin
        GPlayer.facing := ArcTan2(e.y - GPlayer.y, e.x - GPlayer.x);
        PlayerAttack(GPlayer, e.x, e.y);
        if optShake then shake := 2;
      end;
      if d > 16 then attackTgt := -1; // leash
    end;
  end
  else if interactTgt >= 0 then
  begin
    if (interactTgt > High(GEnts)) or (not GEnts[interactTgt].alive) then
      interactTgt := -1
    else
    begin
      e := GEnts[interactTgt];
      d := PointDist(GPlayer.x, GPlayer.y, e.x, e.y);
      if d < 2.0 then
      begin
        ActOnEnt(interactTgt);
        interactTgt := -1;
      end
      else
        WalkToward(e.x, e.y, dt);
    end;
  end
  else if hasMove then
  begin
    d := PointDist(GPlayer.x, GPlayer.y, moveTX, moveTY);
    if d < 0.25 then hasMove := False
    else WalkToward(moveTX, moveTY, dt);
  end;
  // stuck detection: clear orders if we haven't moved
  if (attackTgt >= 0) or (interactTgt >= 0) or hasMove then
  begin
    if PointDist(GPlayer.x, GPlayer.y, stuckX, stuckY) < 0.02 then stuckT := stuckT + dt else stuckT := 0;
    stuckX := GPlayer.x; stuckY := GPlayer.y;
    if stuckT > 0.9 then ClearOrders;
  end;
  // move markers fade
  for i := High(moveMarks) downto 0 do
  begin
    moveMarks[i].t := moveMarks[i].t - dt;
    if moveMarks[i].t <= 0 then Delete(moveMarks, i, 1);
  end;
  // overlays hotkeys
  if IsKeyPressed(KEY_I) then begin if overlay = ovInv then overlay := ovNone else begin overlay := ovInv; listCursor := 0; end; end;
  if IsKeyPressed(KEY_C) then begin if overlay = ovChar then overlay := ovNone else begin overlay := ovChar; listCursor := 0; end; end;
  if IsKeyPressed(KEY_Q) then begin if overlay = ovQuests then overlay := ovNone else overlay := ovQuests; end;
  if IsKeyPressed(KEY_L) then begin if overlay = ovLore then overlay := ovNone else overlay := ovLore; end;
  if IsKeyPressed(KEY_F1) then begin if overlay = ovHelp then overlay := ovNone else overlay := ovHelp; end;
  if IsKeyPressed(KEY_ESCAPE) then begin if overlay = ovNone then begin overlay := ovPause; listCursor := 0; end else overlay := ovNone; end;
  if IsKeyPressed(KEY_F3) then optShake := not optShake;
  if IsKeyPressed(KEY_F4) then optTelegraph := not optTelegraph;
  if IsKeyPressed(KEY_F5) then optDmgNum := not optDmgNum;
  if IsKeyPressed(KEY_F10) then TakeScreenshot('shot.png');
  // camera zoom (wheel / PgUp PgDn / + -) and tilt toggle (T)
  if GetMouseWheelMove > 0 then zoomLevel := Max(0, zoomLevel - 1)
  else if GetMouseWheelMove < 0 then zoomLevel := Min(2, zoomLevel + 1);
  if IsKeyPressed(KEY_PAGE_UP) or IsKeyPressed(KEY_EQUAL) then zoomLevel := Max(0, zoomLevel - 1);
  if IsKeyPressed(KEY_PAGE_DOWN) or IsKeyPressed(KEY_MINUS) then zoomLevel := Min(2, zoomLevel + 1);
  if IsKeyPressed(KEY_T) then tiltOn := not tiltOn;
  // portals
  for i := 0 to High(GMap.portals) do
  begin
    portal := GMap.portals[i];
    if (Trunc(GPlayer.x) = portal.x) and (Trunc(GPlayer.y) = portal.y) then
    begin
      Say('Traveling to ' + portal.target + '...');
      EnterMap(portal.target, portal.tx, portal.ty);
      Exit;
    end;
  end;
  UpdateCombat(GPlayer, dt);
  if shake > 0 then shake := shake - dt * 6;
  if msgT > 0 then msgT := msgT - dt;
end;

// windowed-fullscreen toggle (borderless window covering the current monitor).
// Works without restart; restores the exact previous window rect on exit.
procedure ToggleWindowedFullscreen;
var
  m: Integer;
begin
  if not IsWindowReady then Exit;
  if not gFullscreen then
  begin
    gPrevWW := GetScreenWidth();
    gPrevWH := GetScreenHeight();
    gPrevWX := Round(GetWindowPosition.x);
    gPrevWY := Round(GetWindowPosition.y);
    gPrevMon := GetCurrentMonitor();
    m := gPrevMon;
    SetWindowState(FLAG_WINDOW_UNDECORATED);
    SetWindowMonitor(m);
    SetWindowSize(GetMonitorWidth(m), GetMonitorHeight(m));
    SetWindowPosition(0, 0);
    gFullscreen := True;
    Log('windowed-fullscreen ON: monitor ' + I2S(m) + ' ' + I2S(GetMonitorWidth(m)) + 'x' + I2S(GetMonitorHeight(m)));
  end
  else
  begin
    ClearWindowState(FLAG_WINDOW_UNDECORATED);
    SetWindowMonitor(gPrevMon);
    SetWindowSize(gPrevWW, gPrevWH);
    SetWindowPosition(gPrevWX, gPrevWY);
    gFullscreen := False;
    Log('windowed-fullscreen OFF: restored ' + I2S(gPrevWW) + 'x' + I2S(gPrevWH) + ' @' + I2S(gPrevWX) + ',' + I2S(gPrevWY));
  end;
end;

{ ---------------- main ---------------- }

procedure RunGame(shot: Boolean);
var
  dt: Single;
  frame: Integer;
  bi, i: Integer;
  bd: Single;
  shot2done: Boolean;
  shot2frame, teleOK: Integer;
begin
  shotMode := shot;
  shot2done := False; shot2frame := 0; teleOK := 0; zoomLevel := 0; tiltOn := False;
  optShake := True; optTelegraph := True; optDmgNum := True;
  LoadAllData;
  SetTraceLogLevel(LOG_WARNING);
  SetConfigFlags(FLAG_WINDOW_RESIZABLE or FLAG_VSYNC_HINT);
  InitWindow(INIT_W, INIT_H, PAnsiChar('PLAMEN ' + VERSION_STAMP));
  if not IsWindowReady then Fatal('raylib window init failed (no GL context?)');
  SetTargetFPS(60);
  SetExitKey(KEY_NULL);
  LoadGameFont;
  InitWorldAssets;
  if shotMode then
  begin
    // scripted smoke run: title + chargen screenshots, then create char, hub, fight
    state := gsTitle;
  end;
  frame := 0;
  while not WindowShouldClose do
  begin
    dt := GetFrameTime;
    animT := animT + dt;
    if shotMode and (frame > 61) then
    begin
      // screenshot harness god-mode: acceptance shots must show combat, not the death screen
      GPlayer.hp := GetStat(GPlayer, 'max_hp');
      GPlayer.mana := GetStat(GPlayer, 'max_mana');
      if GPlayer.dead then
      begin
        GPlayer.dead := False;
        state := gsGame;
      end;
    end;
    BeginDrawing;
    case state of
      gsTitle: DrawTitle;
      gsCharGen: DrawCharGen;
      gsGame:
      begin
        UpdateCamera;
        UpdateGame(dt);
        if state = gsGame then
        begin
          DrawWorld;
          DrawHUD;
          case overlay of
            ovStore: DrawStore;
            ovDialog: DrawDialog;
            ovInv: DrawInventory;
            ovQuests: DrawQuestLog;
            ovLore: DrawLoreLog;
            ovChar: DrawCharSheet;
            ovHelp: DrawHelp;
            ovPause: DrawPause;
          end;
        end;
      end;
      gsDeath: begin UpdateCamera; DrawWorld; DrawHUD; DrawDeath; end;
    end;
    // global escape
    if IsKeyPressed(KEY_F10) then TakeScreenshot('shot.png');
    // windowed-fullscreen toggle: F11 or Alt+Enter, any state, no restart
    if IsKeyPressed(KEY_F11) or
       (((IsKeyDown(KEY_LEFT_ALT)) or (IsKeyDown(KEY_RIGHT_ALT))) and IsKeyPressed(KEY_ENTER)) then
      ToggleWindowedFullscreen;
    EndDrawing;
    Inc(frame);
    if shotMode then
    begin
      if (frame = 30) then TakeScreenshot('shot_title.png');
      if (frame = 31) then begin state := gsCharGen; cgName := 'Smoke'; cgRace := 0; cgClass := 0; cgHardcore := False; cgCursor := 4; end;
      if (frame = 60) then TakeScreenshot('shot_chargen.png');
      if (frame = 61) then
      begin
        NewPlayer(GPlayer, cgName, GRaces[cgRace].id, GClasses[cgClass].id, cgHardcore);
        EnterMap('cinderhold', -1, -1);
        state := gsGame;
      end;
      if (frame = 148) then CmdMoveTo(GPlayer.x + 2.5, GPlayer.y + 1.5); // click-move indicator demo
      if (frame = 150) then TakeScreenshot('shot_hub.png');           // 16:9 1280x720
      // item 5 proof: non-16:9 window, native-res render, no squish
      if (frame = 152) then SetWindowSize(1152, 864);                  // 4:3
      if (frame = 162) then TakeScreenshot('shot_aspect43.png');
      if (frame = 164) then SetWindowSize(INIT_W, INIT_H);             // back to 16:9
      // item 6 proof: windowed-fullscreen toggle without restart (F11/Alt+Enter path)
      if (frame = 170) then ToggleWindowedFullscreen;
      if (frame = 180) then TakeScreenshot('shot_fullscreen.png');
      if (frame = 182) then ToggleWindowedFullscreen;                  // back to windowed
      // item 7 proof: zoom steps 1 and 2, camera math intact at each step
      if (frame = 190) then zoomLevel := 1;
      if (frame = 196) then TakeScreenshot('shot_zoom1.png');
      if (frame = 198) then zoomLevel := 2;
      if (frame = 204) then TakeScreenshot('shot_zoom2.png');
      if (frame = 206) then zoomLevel := 0;
      if (frame = 210) then EnterMap('emberfall_area1', -1, -1);
      if frame > 210 then
      begin
        // drive the real point-and-click path: click the nearest monster, keep swinging
        bi := -1; bd := 1e9;
        for i := 0 to High(GEnts) do
          if (GEnts[i].kind = ekMonster) and GEnts[i].alive then
            if PointDist(GPlayer.x, GPlayer.y, GEnts[i].x, GEnts[i].y) < bd then
            begin
              bd := PointDist(GPlayer.x, GPlayer.y, GEnts[i].x, GEnts[i].y);
              bi := i;
            end;
        if bi >= 0 then
        begin
          // harness: keep the player in the fray next to the target so the swing
          // anim + telegraph are captured in-frame (screenshot driver only)
          GPlayer.x := GEnts[bi].x + 1.3;
          GPlayer.y := GEnts[bi].y + 0.4;
          if GPlayer.atkCd <= 0 then CmdAttackEnt(bi);
          // pin the nearest monster in windup so the telegraph decal is visible in shot 2
          GEnts[bi].state := 2;
          GEnts[bi].stateT := 0.55;
          GEnts[bi].windup := 1.1;
        end;
        // acceptance shot 2: player mid-attack-swing while a monster telegraphs (default zoom).
        // TakeScreenshot captures the last PRESENTED frame, so require the swing+telegraph
        // condition to hold for several consecutive frames before shooting.
        if (not shot2done) and (GPlayer.atkCd > 0.18) and (bi >= 0) then Inc(teleOK) else teleOK := 0;
        if (not shot2done) and (teleOK >= 3) then
        begin
          TakeScreenshot('shot_combat.png');
          shot2done := True;
          shot2frame := frame;
        end;
        if (not shot2done) and (frame >= 260) then
        begin
          TakeScreenshot('shot_combat.png'); // fallback
          shot2done := True;
          shot2frame := frame;
        end;
        // acceptance shot 3: SAME scene a few frames later at max zoom
        if shot2done then
        begin
          if frame = shot2frame + 14 then zoomLevel := 2;
          if frame = shot2frame + 24 then TakeScreenshot('shot_zoom.png');
          if frame >= shot2frame + 40 then
          begin
            Log('shot mode done');
            Break;
          end;
        end;
      end;
    end;
  end;
  CloseWindow;
  Log('PLAMEN exit ok');
end;

end.
