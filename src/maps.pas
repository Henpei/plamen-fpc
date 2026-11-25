unit maps;
{$mode objfpc}{$H+}
{ Map loading from data/maps/<id>.map (ASCII grid + key=value header),
  collision, isometric projection, entity spawning from markers. }
interface

uses core, data, reg, sim;

const
  TILE_W = 64;
  TILE_H = 32;

type
  TPortal = record x, y: Integer; target: string; tx, ty: Integer; end;
  TSpawn = record mid: string; count, radius: Integer; x, y: Integer; end;
  TChestM = record x, y: Integer; table: string; end;
  TLoreM = record x, y: Integer; doc: string; end;
  TMarkerM = record x, y: Integer; id, caption: string; end;
  TMap = record
    id, name, region, act, kind, tileset: string;
    w, h: Integer;
    rows: array of string;
    portals: array of TPortal;
    spawns: array of TSpawn;
    boss: string;
    bossX, bossY: Integer;
    chests: array of TChestM;
    lores: array of TLoreM;
    markers: array of TMarkerM;
    store: string;
    spawnX, spawnY: Integer;
  end;

var
  GMap: TMap;

procedure LoadMap(const id: string);   // FATAL on missing/corrupt map (law: loud)
function TileAt(x, y: Integer): Char;
function IsBlocked(x, y: Single): Boolean;
procedure WorldToScreen(x, y: Single; out sx, sy: Single);
procedure ScreenToWorld(sx, sy: Single; out wx, wy: Single);
procedure SpawnMapEntities;            // fills GEnts from GMap + npcs + corpse
function RegionOfMap(const mapId: string): string;
function MapAct(const mapId: string): string;

implementation

uses SysUtils, Math;

procedure LoadMap(const id: string);
var
  path: string;
  txt: string;
  lines: TStrArray;
  i, j, eq: Integer;
  headerDone: Boolean;
  key, val: string;
  portalDefs, spawnDefs, chestDefs, loreDefs, markerDefs: TStrArray;
  np, ns, nc, nl, nm: Integer;
  gx, gy: Integer;
  ch: Char;
  line: string;
  sp: TStrArray;
  iv, fv: Integer;
begin
  path := 'data/maps/' + id + '.map';
  txt := ReadTextFile(path);  // loud if missing
  lines := Split(txt, #10);
  GMap := Default(TMap);
  GMap.id := id;
  GMap.spawnX := -1; GMap.spawnY := -1;
  GMap.bossX := -1; GMap.bossY := -1;
  portalDefs := nil; spawnDefs := nil; chestDefs := nil; loreDefs := nil; markerDefs := nil;
  headerDone := False;
  SetLength(GMap.rows, 0);
  for i := 0 to High(lines) do
  begin
    if not headerDone then
    begin
      line := Trim(lines[i]);
      if line = '' then Continue;
      if line[1] <> '#' then
      begin
        // grid row? header keys contain '='; grid rows are map chars
        eq := Pos('=', line);
        if eq > 0 then
        begin
          key := Trim(Copy(line, 1, eq - 1));
          val := Trim(Copy(line, eq + 1, Length(line)));
          case key of
            'name': GMap.name := val;
            'region': GMap.region := val;
            'act': GMap.act := val;
            'kind': GMap.kind := val;
            'tileset': GMap.tileset := val;
            'w': if not ParseIntStrict(val, GMap.w) then FatalF('%s:%d bad w', [path, i + 1]);
            'h': if not ParseIntStrict(val, GMap.h) then FatalF('%s:%d bad h', [path, i + 1]);
          else
            if StartsWith(key, 'portal.') then begin SetLength(portalDefs, Length(portalDefs) + 1); portalDefs[High(portalDefs)] := val; end
            else if StartsWith(key, 'spawn.') then begin SetLength(spawnDefs, Length(spawnDefs) + 1); spawnDefs[High(spawnDefs)] := val; end
            else if StartsWith(key, 'chest.') then begin SetLength(chestDefs, Length(chestDefs) + 1); chestDefs[High(chestDefs)] := val; end
            else if StartsWith(key, 'lore.') then begin SetLength(loreDefs, Length(loreDefs) + 1); loreDefs[High(loreDefs)] := val; end
            else if StartsWith(key, 'marker.') then begin SetLength(markerDefs, Length(markerDefs) + 1); markerDefs[High(markerDefs)] := Copy(key, 8, Length(key)) + '=' + val; end
            else if key = 'boss' then GMap.boss := val
            else if key = 'store' then GMap.store := val;
          end;
          Continue;
        end;
      end;
      headerDone := True;
    end;
    // grid row (skip blank trailing lines)
    if Trim(lines[i]) = '' then Continue;
    if Length(lines[i]) <> GMap.w then
      FatalF('%s:%d grid row width %d != w=%d', [path, i + 1, Length(lines[i]), GMap.w]);
    SetLength(GMap.rows, Length(GMap.rows) + 1);
    GMap.rows[High(GMap.rows)] := lines[i];
  end;
  if Length(GMap.rows) <> GMap.h then
    FatalF('%s: grid rows %d != h=%d', [path, Length(GMap.rows), GMap.h]);
  if (GMap.name = '') or (GMap.region = '') then FatalF('%s: missing name/region header', [path]);
  // scan grid for marker chars
  np := 0; ns := 0; nc := 0; nl := 0; nm := 0;
  for gy := 0 to GMap.h - 1 do
    for gx := 0 to GMap.w - 1 do
    begin
      ch := GMap.rows[gy][gx];
      case ch of
        'S': begin GMap.spawnX := gx; GMap.spawnY := gy; end;
        'P': begin
          if np >= Length(portalDefs) then FatalF('%s: portal char without portal.%d def', [path, np + 1]);
          sp := Split(portalDefs[np], ':');
          if Length(sp) <> 3 then FatalF('%s: bad portal def %s', [path, portalDefs[np]]);
          SetLength(GMap.portals, Length(GMap.portals) + 1);
          with GMap.portals[High(GMap.portals)] do
          begin
            x := gx; y := gy; target := sp[0];
            if not ParseIntStrict(sp[1], tx) then FatalF('%s: bad portal tx', [path]);
            if not ParseIntStrict(sp[2], ty) then FatalF('%s: bad portal ty', [path]);
          end;
          Inc(np);
        end;
        'M': begin
          if ns >= Length(spawnDefs) then FatalF('%s: spawn char without spawn.%d def', [path, ns + 1]);
          sp := Split(spawnDefs[ns], ':');
          if Length(sp) <> 3 then FatalF('%s: bad spawn def %s', [path, spawnDefs[ns]]);
          SetLength(GMap.spawns, Length(GMap.spawns) + 1);
          with GMap.spawns[High(GMap.spawns)] do
          begin
            x := gx; y := gy; mid := sp[0];
            if not ParseIntStrict(sp[1], count) then FatalF('%s: bad spawn count', [path]);
            if not ParseIntStrict(sp[2], radius) then FatalF('%s: bad spawn radius', [path]);
            if FindMonster(mid) < 0 then FatalF('%s: unknown monster %s', [path, mid]);
          end;
          Inc(ns);
        end;
        'B': begin GMap.bossX := gx; GMap.bossY := gy; end;
        'C': begin
          if nc >= Length(chestDefs) then FatalF('%s: chest char without chest.%d def', [path, nc + 1]);
          SetLength(GMap.chests, Length(GMap.chests) + 1);
          with GMap.chests[High(GMap.chests)] do
          begin
            x := gx; y := gy; table := chestDefs[nc];
            if FindDropTable(table) < 0 then FatalF('%s: unknown chest table %s', [path, table]);
          end;
          Inc(nc);
        end;
        'L': begin
          if nl >= Length(loreDefs) then FatalF('%s: lore char without lore.%d def', [path, nl + 1]);
          SetLength(GMap.lores, Length(GMap.lores) + 1);
          with GMap.lores[High(GMap.lores)] do
          begin
            x := gx; y := gy; doc := loreDefs[nl];
          end;
          Inc(nl);
        end;
        'I': begin
          if nm >= Length(markerDefs) then FatalF('%s: marker char without marker def', [path]);
          sp := SplitStr(markerDefs[nm], '=');
          if Length(sp) <> 2 then FatalF('%s: bad marker def %s', [path, markerDefs[nm]]);
          SetLength(GMap.markers, Length(GMap.markers) + 1);
          with GMap.markers[High(GMap.markers)] do
          begin
            x := gx; y := gy; id := sp[0]; caption := sp[1];
          end;
          Inc(nm);
        end;
      end;
    end;
  if GMap.spawnX < 0 then FatalF('%s: no S spawn marker', [path]);
  if (GMap.boss <> '') and ((GMap.bossX < 0) or (FindMonster(GMap.boss) < 0)) then
    FatalF('%s: bad boss', [path]);
  Log(Format('map loaded: %s (%s/%s, %dx%d, %d portals, %d spawns, boss=%s)', [GMap.name, GMap.region, GMap.kind, GMap.w, GMap.h, Length(GMap.portals), Length(GMap.spawns), GMap.boss]));
end;

function TileAt(x, y: Integer): Char;
begin
  if (x < 0) or (y < 0) or (x >= GMap.w) or (y >= GMap.h) then Exit('#');
  Result := GMap.rows[y][x + 1];
end;

function IsBlocked(x, y: Single): Boolean;
var
  ch: Char;
  swim: Boolean;
begin
  ch := TileAt(Trunc(x), Trunc(y));
  case ch of
    '#', 'T', '^': Result := True;
    '~': begin
      swim := RaceFlag(GPlayer, 'swim') = '1';
      Result := not swim;
    end;
  else Result := False;
  end;
end;

procedure WorldToScreen(x, y: Single; out sx, sy: Single);
begin
  sx := (x - y) * (TILE_W / 2);
  sy := (x + y) * (TILE_H / 2);
end;

procedure ScreenToWorld(sx, sy: Single; out wx, wy: Single);
var
  a, b: Single;
begin
  a := sx / (TILE_W / 2);
  b := sy / (TILE_H / 2);
  wx := (a + b) / 2;
  wy := (b - a) / 2;
end;

procedure SpawnMapEntities;
var
  i, j: Integer;
  e: TEnt;
  nx, ny: Single;
begin
  GEnts := nil;
  // npcs placed on this map
  for i := 0 to High(GNpcs) do
    if (GNpcs[i].map = GMap.id) and (GNpcs[i].x >= 0) then
    begin
      // skip NPCs removed by flags (e.g. dead)
      if FlagEq(GPlayer.flags, 'npc.' + GNpcs[i].id, 'dead') then Continue;
      SetLength(GEnts, Length(GEnts) + 1);
      e := Default(TEnt);
      e.kind := ekNpc;
      e.id := GNpcs[i].id;
      e.name := GNpcs[i].name;
      e.caption := GNpcs[i].title;
      e.x := GNpcs[i].x; e.y := GNpcs[i].y;
      e.alive := True;
      GEnts[High(GEnts)] := e;
    end;
  // monsters
  for i := 0 to High(GMap.spawns) do
    for j := 0 to GMap.spawns[i].count - 1 do
    begin
      nx := GMap.spawns[i].x + RndRange(-GMap.spawns[i].radius, GMap.spawns[i].radius) / 2;
      ny := GMap.spawns[i].y + RndRange(-GMap.spawns[i].radius, GMap.spawns[i].radius) / 2;
      if not IsBlocked(nx, ny) then SpawnMonster(GMap.spawns[i].mid, nx, ny);
    end;
  // boss
  if GMap.boss <> '' then
    SpawnMonster(GMap.boss, GMap.bossX + 0.5, GMap.bossY + 0.5);
  // chests
  for i := 0 to High(GMap.chests) do
  begin
    SetLength(GEnts, Length(GEnts) + 1);
    e := Default(TEnt);
    e.kind := ekChest;
    e.id := GMap.chests[i].table;
    e.name := 'Chest';
    e.x := GMap.chests[i].x + 0.5; e.y := GMap.chests[i].y + 0.5;
    e.alive := True;
    GEnts[High(GEnts)] := e;
  end;
  // lore docs
  for i := 0 to High(GMap.lores) do
  begin
    SetLength(GEnts, Length(GEnts) + 1);
    e := Default(TEnt);
    e.kind := ekLore;
    e.id := GMap.lores[i].doc;
    e.name := 'Document';
    e.x := GMap.lores[i].x + 0.5; e.y := GMap.lores[i].y + 0.5;
    e.alive := True;
    // already read?
    for j := 0 to High(GPlayer.lore) do
      if GPlayer.lore[j] = e.id then e.used := True;
    GEnts[High(GEnts)] := e;
  end;
  // interact markers
  for i := 0 to High(GMap.markers) do
  begin
    SetLength(GEnts, Length(GEnts) + 1);
    e := Default(TEnt);
    e.kind := ekMarker;
    e.id := GMap.markers[i].id;
    e.name := GMap.markers[i].caption;
    e.caption := GMap.markers[i].caption;
    e.x := GMap.markers[i].x + 0.5; e.y := GMap.markers[i].y + 0.5;
    e.alive := True;
    GEnts[High(GEnts)] := e;
  end;
  // store
  if GMap.store <> '' then
  begin
    SetLength(GEnts, Length(GEnts) + 1);
    e := Default(TEnt);
    e.kind := ekStore;
    e.id := GMap.store;
    e.name := 'Store';
    e.x := -1; e.y := -1;
    e.alive := True;
    GEnts[High(GEnts)] := e;
  end;
  // corpse
  if (GPlayer.corpseMap = GMap.id) and (GPlayer.dead or (GPlayer.lostXP > 0)) then
  begin
    SetLength(GEnts, Length(GEnts) + 1);
    e := Default(TEnt);
    e.kind := ekCorpse;
    e.id := 'corpse';
    e.name := GPlayer.name + '''s corpse';
    e.x := GPlayer.corpseX; e.y := GPlayer.corpseY;
    e.alive := True;
    GEnts[High(GEnts)] := e;
  end;
end;

function RegionOfMap(const mapId: string): string;
var
  i, j: Integer;
begin
  Result := '';
  for i := 0 to High(GRegions) do
    for j := 0 to High(GRegions[i].maps) do
      if GRegions[i].maps[j] = mapId then Exit(GRegions[i].id);
  if mapId = 'worldmap' then Result := 'world';
end;

function MapAct(const mapId: string): string;
begin
  if GMap.id = mapId then Exit(GMap.act);
  Result := '1';
end;

end.
