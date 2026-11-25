unit render;
{$mode objfpc}{$H+}
{ All raylib rendering, input, screens, HUD. The only unit besides plamen.dpr
  that touches raylib — everything else is headless-testable. }
interface

procedure RunGame(shot: Boolean);

implementation

uses SysUtils, Math, core, data, reg, sim, maps, raylib;

const
  SCREEN_W = 1280;
  SCREEN_H = 720;

type
  TGameState = (gsTitle, gsCharGen, gsGame, gsDeath);
  TOverlay = (ovNone, ovStore, ovDialog, ovInv, ovQuests, ovLore, ovChar, ovHelp, ovPause);

  TDlgLine = record cond, text: string; choices: TStrArray; end;

var
  font: TFont;
  state: TGameState = gsTitle;
  overlay: TOverlay = ovNone;
  camTarget: TVector2;
  shake: Single = 0;
  optShake, optTelegraph, optDmgNum: Boolean;
  shotMode: Boolean;
  shotFrame: Integer;
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

function MkRec(x, y, w, h: Single): TRectangle;
begin
  Result.x := x; Result.y := y; Result.width := w; Result.height := h;
end;

function MkV(x, y: Single): TVector2;
begin
  Result.x := x; Result.y := y;
end;

function MkCam: TCamera2D;
begin
  Result.offset := MkV(SCREEN_W / 2, SCREEN_H / 2);
  Result.target := camTarget;
  Result.rotation := 0;
  Result.zoom := 1;
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


{ ---------------- world ---------------- }

function TileColor(ch: Char; ts: string; x, y: Integer): TColor;
var
  v: Integer;
  r, g, b: Integer;
  procedure SetC(rr, gg, bb: Integer);
  begin
    v := (x * 73 + y * 151) mod 3;
    r := ClampI(rr + v * 4, 0, 255); g := ClampI(gg + v * 4, 0, 255); b := ClampI(bb + v * 4, 0, 255);
    Result := MkCol(r, g, b);
  end;
begin
  if ts = 'emberfall' then
    case ch of
      '#': SetC(28, 24, 22); 'o': SetC(96, 84, 72); '^': SetC(44, 38, 34);
      ',': SetC(74, 64, 56); else SetC(58, 50, 46);
    end
  else if ts = 'veil' then
    case ch of
      '#': SetC(24, 20, 18); 'T': SetC(18, 42, 22); '~': SetC(30, 90, 60);
      ',': SetC(42, 76, 44); else SetC(32, 62, 34);
    end
  else if ts = 'glass' then
    case ch of
      '#': SetC(48, 58, 64); '^': SetC(96, 116, 126); ',': SetC(150, 178, 188);
      else SetC(122, 148, 158);
    end
  else if ts = 'maren' then
    case ch of
      '#': SetC(22, 38, 56); '~': SetC(28, 108, 158); ',': SetC(48, 92, 122);
      else SetC(38, 78, 108);
    end
  else if ts = 'crown' then
    case ch of
      '#': SetC(88, 98, 118); '^': SetC(126, 146, 166); '~': SetC(58, 118, 168);
      ',': SetC(186, 198, 214); else SetC(206, 216, 228);
    end
  else
    case ch of
      '#': SetC(30, 26, 22); ',': SetC(96, 84, 70); else SetC(84, 72, 60);
    end;
end;









procedure DrawTileDiamond(sx, sy: Single; col: TColor);
var
  top, right, bottom, left: TVector2;
begin
  top := MkV(sx + 32, sy);
  right := MkV(sx + 64, sy + 16);
  bottom := MkV(sx + 32, sy + 32);
  left := MkV(sx, sy + 16);
  DrawTriangle(top, left, bottom, col);
  DrawTriangle(top, bottom, right, col);
end;




function ElemCol(const elem: string): TColor; forward;
function HasQuestFor(const npcId: string): Boolean; forward;

procedure DrawWorld;
var
  x, y, i, j: Integer;
  sx, sy: Single;
  ch: Char;
  idx: array of Integer;
  tmp: Integer;
  e: TEnt;
  ex, ey: Single;
  r: Single;
  hpw: Single;
  col: TColor;
begin
  // camera follows player (+shake)
  WorldToScreen(GPlayer.x, GPlayer.y, camTarget.x, camTarget.y);
  if optShake and (shake > 0) then
  begin
    camTarget.x := camTarget.x + (RndUInt64 mod 100 - 50) / 100 * shake * 8;
    camTarget.y := camTarget.y + (RndUInt64 mod 100 - 50) / 100 * shake * 6;
  end;
  // tiles
  BeginMode2D(MkCam);
  for y := 0 to GMap.h - 1 do
    for x := 0 to GMap.w - 1 do
    begin
      WorldToScreen(x, y, sx, sy);
      ch := TileAt(x, y);
      DrawTileDiamond(sx, sy, TileColor(ch, GMap.tileset, x, y));
      if ch = 'P' then
        DrawPoly(MkV(sx + 32, sy + 16), 4, 20, 45, Fade(GOLD, 0.35 + 0.25 * Sin(GTime * 4)));
    end;
  // telegraphs (under entities)
  if optTelegraph then
    for i := 0 to High(GEnts) do
    begin
      e := GEnts[i];
      if (e.kind = ekMonster) and e.alive and (e.state = 2) then
      begin
        WorldToScreen(e.x, e.y, ex, ey);
        ex := ex + 32; ey := ey + 22;
        r := e.attackRange * TILE_W / 2;
        DrawCircleV(MkV(ex, ey), r, Fade(ORANGE, 0.22 + 0.15 * Sin(GTime * 18)));
        DrawCircleLinesV(MkV(ex, ey), r, ORANGE);
        // windup shrinking ring
        DrawRing(MkV(ex, ey), r * Max(0.05, e.stateT / e.windup), r, 0, 360, 32, Fade(RED, 0.8));
      end;
    end;
  // entities sorted by x+y (painter)
  SetLength(idx, Length(GEnts));
  for i := 0 to High(idx) do idx[i] := i;
  for i := 0 to High(idx) - 1 do
    for j := i + 1 to High(idx) do
      if (GEnts[idx[j]].x + GEnts[idx[j]].y) < (GEnts[idx[i]].x + GEnts[idx[i]].y) then
      begin
        tmp := idx[i]; idx[i] := idx[j]; idx[j] := tmp;
      end;
  for i := 0 to High(idx) do
  begin
    e := GEnts[idx[i]];
    WorldToScreen(e.x, e.y, ex, ey);
    ex := ex + 32; ey := ey + 24;
    case e.kind of
      ekMonster:
        if e.alive then
        begin
          r := 13 * e.scale + e.size * 8;
          if e.boss then col := MAROON else col := RED;
          if e.enraged then col := ORANGE;
          DrawCircleV(MkV(ex, ey - r), r, col);
          DrawCircleLinesV(MkV(ex, ey - r), r, BLACK);
          // facing tick
          DrawLineEx(MkV(ex, ey - r), MkV(ex + Cos(e.facing) * (r + 6), ey - r + Sin(e.facing) * (r + 6)), 3, WHITE);
          // hp bar
          hpw := r * 2;
          DrawRectangle(Round(ex - r), Round(ey - 2 * r - 8), Round(hpw), 5, BLACK);
          DrawRectangle(Round(ex - r), Round(ey - 2 * r - 8), Round(hpw * Max(0, e.hp / e.maxhp)), 5, LIME);
          if e.boss then Text(Round(ex - TextW(e.name, 14) / 2), Round(ey - 2 * r - 24), 14, e.name, GOLD);
        end;
      ekProjectile:
        if e.alive then
        begin
          col := ElemCol(e.pelement);
          DrawCircleV(MkV(ex, ey), 5, col);
          DrawCircleLinesV(MkV(ex, ey), 5, WHITE);
        end;
      ekNpc:
      begin
        DrawCircleV(MkV(ex, ey - 8), 11, GREEN);
        DrawCircleLinesV(MkV(ex, ey - 8), 11, BLACK);
        Text(Round(ex - TextW(e.name, 13) / 2), Round(ey - 30), 13, e.name, RAYWHITE);
        // quest marker
        if HasQuestFor(e.id) then
          Text(Round(ex + 6), Round(ey - 34), 20, '!', GOLD);
      end;
      ekChest:
        if not e.used then
        begin
          DrawRectangle(Round(ex - 10), Round(ey - 14), 20, 14, BROWN);
          DrawRectangleLines(Round(ex - 10), Round(ey - 14), 20, 14, GOLD);
        end;
      ekLore:
        if not e.used then
        begin
          DrawRectangle(Round(ex - 7), Round(ey - 12), 14, 12, SKYBLUE);
          Text(Round(ex - 4), Round(ey - 12), 12, 'i', BLACK);
        end;
      ekMarker:
        if not e.used then
        begin
          DrawPoly(MkV(ex, ey - 12), 5, 9, 0, GOLD);
          Text(Round(ex - TextW(e.caption, 12) / 2), Round(ey + 2), 12, e.caption, RAYWHITE);
        end;
      ekStore:
        Text(Round(ex - 20), Round(ey - 30), 16, 'STORE', GOLD);
      ekCorpse:
        begin
          DrawCircleV(MkV(ex, ey - 6), 10, DARKGRAY);
          Text(Round(ex - TextW('corpse', 12) / 2), Round(ey + 4), 12, 'corpse (' + I2S(GPlayer.lostXP) + ' xp)', GRAY);
        end;
    end;
  end;
  // player
  WorldToScreen(GPlayer.x, GPlayer.y, ex, ey);
  ex := ex + 32; ey := ey + 24;
  if GPlayer.dodgeT > 0 then col := Fade(SKYBLUE, 0.5) else col := SKYBLUE;
  DrawCircleV(MkV(ex, ey - 10), 12, col);
  DrawCircleLinesV(MkV(ex, ey - 10), 12, WHITE);
  DrawLineEx(MkV(ex, ey - 10), MkV(ex + Cos(GPlayer.facing) * 20, ey - 10 + Sin(GPlayer.facing) * 20), 4, WHITE);
  Text(Round(ex - TextW(GPlayer.name, 13) / 2), Round(ey - 34), 13, GPlayer.name, RAYWHITE);
  // damage numbers
  if optDmgNum then
    for i := 0 to High(GDmgNums) do
      with GDmgNums[i] do
      begin
        WorldToScreen(x, y, ex, ey);
        if crit then col := GOLD else col := RAYWHITE;
        Text(Round(ex + 32 - TextW(txt, 16) / 2), Round(ey + 16 - t * 30), 16, txt, Fade(col, 1 - t / 1.2));
      end;
  EndMode2D;
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
  x := SCREEN_W - mw - 10; y := 10;
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
begin
  y0 := SCREEN_H - 96;
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
  Text(10, SCREEN_H - 18, 13,
    'PLAMEN ' + VERSION_STAMP + ' | map=' + GMap.id + ' "' + GMap.name + '" | region=' + RegionOfMap(GMap.id) +
    ' act=' + FlagGet(GPlayer.flags, 'act') + ' | fps=' + I2S(GetFPS()) + ' | ents=' + I2S(Length(GEnts)),
    GOLD);
  // message toast
  if msgT > 0 then TextC(SCREEN_W div 2, 60, 18, msg, YELLOW);
  DrawMinimap;
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
  TextC(SCREEN_W div 2, 120, 64, 'PLAMEN', GOLD);
  TextC(SCREEN_W div 2, 200, 20, 'A hardcore high fantasy isometric action RPG', RAYWHITE);
  TextC(SCREEN_W div 2, 226, 16, 'commit ' + VERSION_STAMP + '  built ' + BUILD_TIME, GRAY);
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
      TextC(SCREEN_W div 2, 304 + i * 40, 20, items[i] + ' (no save)', DARKGRAY);
    end
    else
    begin
      if i = sel then DrawRectangle(SCREEN_W div 2 - 100, 300 + i * 40, 200, 32, DARKGRAY);
      TextC(SCREEN_W div 2, 304 + i * 40, 20, items[i], IIfC(i = sel, YELLOW, RAYWHITE));
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
  TextC(SCREEN_W div 2, 60, 40, 'CREATE CHARACTER', GOLD);
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
    if i = sel then DrawRectangle(SCREEN_W div 2 - 220, 140 + i * 44, 440, 36, DARKGRAY);
    TextC(SCREEN_W div 2, 146 + i * 44, 20, labels[i], IIfC(i = sel, YELLOW, RAYWHITE));
  end;
  // descriptions
  TextC(SCREEN_W div 2, 380, 14, GRaces[cgRace].desc, GRAY);
  TextC(SCREEN_W div 2, 402, 14, GClasses[cgClass].desc, GRAY);
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
  Panel(140, SCREEN_H - 320, SCREEN_W - 280, 300, 'Dialog — ' + dlgNpc);
  y := SCREEN_H - 290;
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
  y := SCREEN_H - 120;
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
  Panel(80, 60, SCREEN_W - 160, SCREEN_H - 140, st.name + '  (Compact trust: ' + FlagGet(GPlayer.flags, 'compact.trust') + ')  [Tab: buy/sell]  gold=' + I2S(GPlayer.gold));
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
      if i = storeCursor then DrawRectangle(96, y - 3, SCREEN_W - 200, 20, DARKGRAY);
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
      if i = storeCursor then DrawRectangle(96, y - 3, SCREEN_W - 200, 20, DARKGRAY);
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
  Text(100, SCREEN_H - 120, 14, 'ENTER buy/sell — ESC close', GRAY);
  // mouse click support
  mx := GetMousePosition; click := IsMouseButtonPressed(MOUSE_BUTTON_LEFT);
  if click then
  begin
    if (mx.y > 120) and (mx.y < y) and (mx.x > 96) and (mx.x < SCREEN_W - 104) then
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
  Panel(60, 50, 640, SCREEN_H - 120, 'INVENTORY  (ENTER equip, ESC close)  carry ' + I2S(Length(GPlayer.inv)) + '/' + F2S(GetStat(GPlayer, 'carry'), 0));
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
  Panel(60, 50, SCREEN_W - 120, SCREEN_H - 120, 'CHARACTER — ' + GPlayer.name + '  ' + GRaces[FindRace(GPlayer.raceId)].name + ' ' + GClasses[FindClass(GPlayer.classId)].name + '  lv ' + I2S(GPlayer.level) + '  pts: attr ' + I2S(GPlayer.attrPoints) + ' skill ' + I2S(GPlayer.skillPoints));
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
    if y > SCREEN_H - 200 then Break;
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
        if y > SCREEN_H - 130 then Break;
        if listCursor = si then DrawRectangle(556, y - 3, SCREEN_W - 640, 18, DARKGRAY);
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
  Panel(60, 50, SCREEN_W - 120, SCREEN_H - 120, 'QUEST LOG (ESC close)');
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
    if y > SCREEN_H - 90 then Break;
  end;
end;

procedure DrawLoreLog;
var
  i, y, li, k: Integer;
begin
  Panel(60, 50, SCREEN_W - 120, SCREEN_H - 120, 'LORE LOG (ESC close) — reading is optional, the world does not force-feed');
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
    if y > SCREEN_H - 90 then Break;
  end;
end;

procedure DrawPause;
var
  i: Integer;
  items: array[0..4] of string;
begin
  Panel(SCREEN_W div 2 - 200, 200, 400, 260, 'PAUSED');
  items[0] := 'Resume';
  items[1] := 'Save game (autosave slot)';
  items[2] := 'Toggles: shake=' + BoolToStr(optShake, True) + ' telegraphs=' + BoolToStr(optTelegraph, True) + ' dmgnum=' + BoolToStr(optDmgNum, True);
  items[3] := 'Screenshot (shot.png)';
  items[4] := 'Quit to title';
  if IsKeyPressed(KEY_DOWN) then listCursor := (listCursor + 1) mod 5;
  if IsKeyPressed(KEY_UP) then listCursor := (listCursor + 4) mod 5;
  for i := 0 to 4 do
  begin
    if i = listCursor then DrawRectangle(SCREEN_W div 2 - 180, 240 + i * 36, 360, 30, DARKGRAY);
    TextC(SCREEN_W div 2, 245 + i * 36, 16, items[i], IIfC(i = listCursor, YELLOW, RAYWHITE));
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
  DrawRectangle(0, 0, SCREEN_W, SCREEN_H, Fade(MAROON, 0.55));
  TextC(SCREEN_W div 2, 140, 56, 'YOU DIED', RED);
  TextC(SCREEN_W div 2, 210, 18, 'Death is punished. The world does not scale to you.', RAYWHITE);
  TextC(SCREEN_W div 2, 236, 16, 'Lost XP on corpse: ' + I2S(GPlayer.lostXP) + IIfS2(GPlayer.corpseLooted, '  (corpse looted by monsters — a grave robber may have your things)', ''), GRAY);
  cost := GPlayer.level * 50;
  items[0] := 'Run to your corpse (recover the XP)';
  items[1] := 'Dagny resurrect at hub (' + I2S(cost) + 'g)';
  items[2] := 'Reload autosave' + IIfS2(GPlayer.hardcore, ' (hardcore: the only option that keeps the run)', '');
  if IsKeyPressed(KEY_DOWN) then listCursor := (listCursor + 1) mod 3;
  if IsKeyPressed(KEY_UP) then listCursor := (listCursor + 2) mod 3;
  for i := 0 to 2 do
  begin
    if i = listCursor then DrawRectangle(SCREEN_W div 2 - 260, 300 + i * 44, 520, 36, DARKGRAY);
    TextC(SCREEN_W div 2, 306 + i * 44, 19, items[i], IIfC(i = listCursor, YELLOW, RAYWHITE));
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
  Panel(120, 60, SCREEN_W - 240, SCREEN_H - 140, 'HELP / KEYBINDS');
  Text(140, 96, 15, 'WASD/arrows move   mouse aims   J or LMB attack (combo)   K hold block   SPACE/RMB dodge (i-frames)', RAYWHITE);
  Text(140, 120, 15, '1-8 quickbar (attack + spells)   E interact/talk   I inventory   C character/build   Q quest log   L lore', RAYWHITE);
  Text(140, 144, 15, 'ESC pause   F3 shake  F4 telegraphs  F5 damage numbers   F10 screenshot   pure keyboard works: facing follows movement', RAYWHITE);
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

{ ---------------- game update ---------------- }

procedure UpdateGame(dt: Single);
var
  dx, dy, sp, nx, ny: Single;
  i: Integer;
  aimX, aimY: Single;
  mw: TVector2;
  portal: TPortal;
  nearest, nd: Integer;
  e: TEnt;
begin
  if overlay <> ovNone then Exit;
  if GPlayer.dead then begin state := gsDeath; listCursor := 0; Exit; end;
  // movement
  dx := Ord(IsKeyDown(KEY_D) or IsKeyDown(KEY_RIGHT)) - Ord(IsKeyDown(KEY_A) or IsKeyDown(KEY_LEFT));
  dy := Ord(IsKeyDown(KEY_S) or IsKeyDown(KEY_DOWN)) - Ord(IsKeyDown(KEY_W) or IsKeyDown(KEY_UP));
  if (dx <> 0) or (dy <> 0) then
  begin
    sp := Sqrt(dx * dx + dy * dy);
    dx := dx / sp; dy := dy / sp;
    sp := GetStat(GPlayer, 'move_speed');
    nx := GPlayer.x + dx * sp * dt;
    ny := GPlayer.y + dy * sp * dt;
    if not IsBlocked(nx, GPlayer.y) then GPlayer.x := nx;
    if not IsBlocked(GPlayer.x, ny) then GPlayer.y := ny;
    if not mouseActive then GPlayer.facing := ArcTan2(dy, dx);
  end;
  // mouse aim
  mw := GetMousePosition;
  if (Abs(mw.x - mouseWX) > 0.5) or (Abs(mw.y - mouseWY) > 0.5) or IsMouseButtonPressed(MOUSE_BUTTON_LEFT) or IsMouseButtonPressed(MOUSE_BUTTON_RIGHT) then
  begin
    mouseActive := True;
    ScreenToWorld(mw.x - SCREEN_W / 2 + camTarget.x, mw.y - SCREEN_H / 2 + camTarget.y, mouseWX, mouseWY);
    GPlayer.facing := ArcTan2(mouseWY - GPlayer.y, mouseWX - GPlayer.x);
  end;
  aimX := GPlayer.x + Cos(GPlayer.facing) * 2;
  aimY := GPlayer.y + Sin(GPlayer.facing) * 2;
  if mouseActive then begin aimX := mouseWX; aimY := mouseWY; end;
  // attack / block / dodge
  if IsKeyPressed(KEY_J) or IsMouseButtonPressed(MOUSE_BUTTON_LEFT) then
  begin
    PlayerAttack(GPlayer, aimX, aimY);
    if optShake then shake := 2;
  end;
  GPlayer.blockHeld := IsKeyDown(KEY_K);
  if IsKeyPressed(KEY_SPACE) or IsMouseButtonPressed(MOUSE_BUTTON_RIGHT) then
  begin
    // dodge dash in facing dir with i-frames
    nx := GPlayer.x + Cos(GPlayer.facing) * 1.1;
    ny := GPlayer.y + Sin(GPlayer.facing) * 1.1;
    if not IsBlocked(nx, GPlayer.y) then GPlayer.x := nx;
    if not IsBlocked(GPlayer.x, ny) then GPlayer.y := ny;
    GPlayer.dodgeT := 0.28;
    if RaceFlag(GPlayer, 'dodge_chance') <> '' then ; // stat handled in DamagePlayer via dodge_chance? keep simple
  end;
  // quickbar
  for i := 0 to QUICK_SLOTS - 1 do
    if IsKeyPressed(KEY_ONE + i) then CastQuickbar(GPlayer, i, aimX, aimY);
  // interact
  if IsKeyPressed(KEY_E) then
  begin
    nearest := -1; nd := 2;
    for i := 0 to High(GEnts) do
    begin
      e := GEnts[i];
      if e.alive and (e.kind in [ekNpc, ekMarker, ekChest, ekLore, ekStore]) then
        if PointDist(GPlayer.x, GPlayer.y, e.x, e.y) < nd then
        begin
          nd := Round(PointDist(GPlayer.x, GPlayer.y, e.x, e.y) * 10);
          nearest := i;
        end;
    end;
    if nearest >= 0 then
    begin
      e := GEnts[nearest];
      case e.kind of
        ekNpc: OpenDialog(e.id);
        ekStore: OpenStore(e.id);
        ekMarker, ekChest, ekLore: InteractAt(GPlayer, e.x, e.y);
      end;
    end;
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

{ ---------------- main ---------------- }

procedure RunGame(shot: Boolean);
var
  dt: Single;
  frame: Integer;
  bi, i: Integer;
  bd, ex, ey, nx, ny: Single;
begin
  shotMode := shot;
  optShake := True; optTelegraph := True; optDmgNum := True;
  LoadAllData;
  SetTraceLogLevel(LOG_WARNING);
  SetConfigFlags(FLAG_WINDOW_RESIZABLE or FLAG_VSYNC_HINT);
  InitWindow(SCREEN_W, SCREEN_H, PAnsiChar('PLAMEN ' + VERSION_STAMP));
  if not IsWindowReady then Fatal('raylib window init failed (no GL context?)');
  SetTargetFPS(60);
  SetExitKey(KEY_NULL);
  LoadGameFont;
  if shotMode then
  begin
    // scripted smoke run: title + chargen screenshots, then create char, hub, fight
    state := gsTitle;
  end;
  frame := 0;
  while not WindowShouldClose do
  begin
    dt := GetFrameTime;
    BeginDrawing;
    case state of
      gsTitle: DrawTitle;
      gsCharGen: DrawCharGen;
      gsGame:
      begin
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
      gsDeath: begin DrawWorld; DrawHUD; DrawDeath; end;
    end;
    // global escape
    if IsKeyPressed(KEY_F10) then TakeScreenshot('shot.png');
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
      if (frame = 150) then TakeScreenshot('shot_hub.png');
      if (frame = 151) then EnterMap('emberfall_area1', -1, -1);
      if frame > 91 then
      begin
        // walk toward nearest monster and attack
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
          ex := GEnts[bi].x; ey := GEnts[bi].y;
          GPlayer.facing := ArcTan2(ey - GPlayer.y, ex - GPlayer.x);
          mouseWX := ex; mouseWY := ey; mouseActive := True;
          if bd > 1.6 then
          begin
            nx := GPlayer.x + Cos(GPlayer.facing) * GetStat(GPlayer, 'move_speed') * dt;
            ny := GPlayer.y + Sin(GPlayer.facing) * GetStat(GPlayer, 'move_speed') * dt;
            if not IsBlocked(nx, GPlayer.y) then GPlayer.x := nx;
            if not IsBlocked(GPlayer.x, ny) then GPlayer.y := ny;
          end
          else
            PlayerAttack(GPlayer, ex, ey);
          UpdateCombat(GPlayer, dt);
        end;
        if frame = 400 then TakeScreenshot('shot_combat.png');
        if frame >= 430 then
        begin
          Log('shot mode done');
          Break;
        end;
      end;
    end;
  end;
  CloseWindow;
  Log('PLAMEN exit ok');
end;

end.
