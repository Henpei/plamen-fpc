unit sim;
{$mode objfpc}{$H+}
{ Pure game logic. NO raylib here — selftest runs headless against this unit.
  Stats: one shared data-driven formula system (stats.dat). Quest state: one
  flag DB (brief 2.5). Loot/store/combat all data-driven via reg.pas. }
interface

uses core, data, reg;

const
  LEVEL_CAP = 30;
  QUICK_SLOTS = 8;
  MAX_ENTS = 512;
  MAX_INV = 60;

type
  TItemInst = record
    base: string;      // item base id ('' = empty slot)
    uid: string;       // unique id or ''
    name: string;
    slot: string;
    rarity: Integer;
    aff1, aff2: string;
    val1, val2: Single;
    stats: string;     // resolved 'stat=value|...' (base + affixes + unique)
    price: Integer;
    lvl: Integer;
    seed: UInt64;
  end;
  TQuestState = record
    id, state: string;          // locked|available|active|complete|failed
    obj: array of Integer;
  end;
  PKill = ^TKill;
  TKill = record mid: string; n: Integer; end;

  TPlayer = record
    name: string;
    raceId, classId: string;
    attrs: array[0..4] of Integer;       // base attributes
    level, xp: Integer;
    attrPoints, skillPoints: Integer;
    gold: Integer;
    hp, mana, stamina: Single;
    x, y: Single;
    mapId: string;
    facing: Single;
    dodgeT: Single;        // i-frames remaining
    atkCd: Single;
    combo: Integer;
    blockHeld: Boolean;
    dead: Boolean;
    deaths: Integer;
    hardcore: Boolean;
    gear: array[0..SLOT_COUNT-1] of TItemInst;
    inv: array of TItemInst;
    quickbar: array[0..QUICK_SLOTS-1] of string;
    spells: array of string;
    skills: array of string;
    flags: TFlagDB;
    quests: array of TQuestState;
    lore: array of string;
    kills: array of TKill;
    corpseMap: string;
    corpseX, corpseY: Single;
    lostXP: Integer;
    corpseLooted: Boolean;
    day: Integer;
    playTime: Single;
    rngSeed: UInt64;
    statCache: array of record id: string; val: Single; end;
  end;

  TEntKind = (ekMonster, ekProjectile, ekCorpse, ekMarker, ekChest, ekLore, ekPortal, ekStore, ekNpc);
  TEnt = record
    kind: TEntKind;
    id: string;            // monster id / marker id / doc id / npc id / table id
    name: string;
    x, y: Single;
    vx, vy: Single;
    hp, maxhp: Single;
    alive: Boolean;
    // monster combat
    behavior, element: string;
    dmg, speed, aggro, attackRange, windup: Single;
    armor, size, scale: Single;
    state: Integer;        // 0 idle 1 chase 2 windup 3 strike 4 cooldown
    stateT: Single;
    atkCd: Single;
    facing: Single;
    xp, goldMin, goldMax: Single;
    dropTable: string;
    boss: Boolean;
    abilities: TStrArray;
    enraged: Boolean;
    // projectile
    pdmg: Single;
    pelement: string;
    plife: Single;
    fromPlayer: Boolean;
    // marker/chest/lore
    caption: string;
    used: Boolean;
  end;

  TDmgNum = record x, y: Single; val: Single; crit: Boolean; t: Single; txt: string; end;
  TSymbol = record name: string; val: Single; end;
  TFlatArr = array of TSymbol;
  TItemArr = array of TItemInst;

var
  GPlayer: TPlayer;
  GEnts: array of TEnt;
  GDmgNums: array of TDmgNum;
  GMapId: string = '';
  GTime: Single = 0;

{ --- stats --- }
procedure RecalcStats(var p: TPlayer);
function GetStat(const p: TPlayer; const id: string): Single;
function EvalFormula(const f: string; const syms: array of TSymbol): Single;

{ --- player --- }
procedure NewPlayer(var p: TPlayer; const name, raceId, classId: string; hardcore: Boolean);
procedure AddXP(var p: TPlayer; xp: Single);
function XPNeed(level: Integer): Integer;
function RaceFlag(const p: TPlayer; const key: string): string;

{ --- items / loot --- }
function MakeItem(const baseId: string; rarity, lvl: Integer): TItemInst;
function MakeUnique(const uid: string): TItemInst;
procedure RollLoot(const tableId: string; lvl: Integer; var items: TItemArr; out gold: Integer);
function ItemName(const it: TItemInst): string;
function InvCount(const p: TPlayer; const id: string): Integer;
procedure InvAdd(var p: TPlayer; const it: TItemInst);
function FindInv(const p: TPlayer; idx: Integer): Integer; // -1
procedure EquipFromInv(var p: TPlayer; invIdx: Integer);

{ --- store --- }
function StorePriceMul(const p: TPlayer; const mapId: string): Single;
function StorePrice(const p: TPlayer; const mapId, itemId: string): Integer;
function SellPrice(const p: TPlayer; const mapId: string; const it: TItemInst): Integer;
function StoreStockVisible(const p: TPlayer; const st: TStore; entryIdx: Integer): Boolean;

{ --- quests / rules --- }
procedure QuestRefresh(var p: TPlayer);
procedure QuestAccept(var p: TPlayer; const qid: string);
procedure QuestEvent(var p: TPlayer; const ev, arg: string);
procedure QuestTick(var p: TPlayer);
procedure FireRules(var p: TPlayer; const trigger: string);
function QuestState(const p: TPlayer; const qid: string): string;
procedure SetAct(var p: TPlayer; act: Integer);

{ --- combat --- }
function ElemAdv(const atkElem, defElem: string): Single;
function CalcHitDamage(weapDmg: Single; elem: string; critChance, critDmg: Single;
  targetRes: Single; targetArmor: Single; backstabMul: Single; isCrit: Boolean): Single;
procedure DamagePlayer(var p: TPlayer; dmg: Single; elem: string; fromX, fromY: Single);
procedure PlayerAttack(var p: TPlayer; const aimX, aimY: Single);
procedure CastQuickbar(var p: TPlayer; slot: Integer; aimX, aimY: Single);
procedure SpawnMonster(const mid: string; x, y: Single);
procedure UpdateCombat(var p: TPlayer; dt: Single);
procedure KillPlayer(var p: TPlayer);
procedure InteractAt(var p: TPlayer; x, y: Single);

{ --- save / load (versioned, CRC tamper detection; err string, caller goes loud) --- }
function SaveGame(const p: TPlayer; const slotName: string; out err: string): Boolean;
function LoadGame(var p: TPlayer; const slotName: string; out err: string): Boolean;
function SaveSlots: TStrArray;

implementation

uses SysUtils, Math;

function AngDiff(a, b: Single): Single;
var
  d: Single;
begin
  d := Abs(a - b);
  while d > 3.14159265 do d := Abs(d - 2 * 3.14159265);
  Result := d;
end;

function IIfS(cond: Boolean; a, b: Single): Single;
begin
  if cond then Result := a else Result := b;
end;

function ArrI2S(const a: array of Integer): TStrArray;
var
  i: Integer;
begin
  Result := nil;
  SetLength(Result, Length(a));
  for i := 0 to High(a) do Result[i] := I2S(a[i]);
end;

{ ================= stats ================= }

function EvalFormula(const f: string; const syms: array of TSymbol): Single;
var
  s: string;
  pos: Integer;

  function Peek: Char;
  begin
    while (pos <= Length(s)) and (s[pos] = ' ') do Inc(pos);
    if pos > Length(s) then Result := #0 else Result := s[pos];
  end;
  procedure SkipWs;
  begin
    while (pos <= Length(s)) and (s[pos] = ' ') do Inc(pos);
  end;
  function ParseExpr: Single; forward;
  function ParseTerm: Single; forward;
  function ParseFactor: Single; forward;
  function ParseTerm: Single;
  var
    v: Single;
    op: Char;
  begin
    v := ParseFactor;
    while True do
    begin
      SkipWs;
      if (pos <= Length(s)) and ((s[pos] = '*') or (s[pos] = '/')) then
      begin
        op := s[pos]; Inc(pos);
        if op = '*' then v := v * ParseFactor else v := v / ParseFactor;
      end
      else Break;
    end;
    Result := v;
  end;
  function ParseFactor: Single;
  var
    id: string;
    i: Integer;
    neg: Boolean;
    found: Boolean;
  begin
    SkipWs;
    neg := False;
    if Peek = '-' then begin neg := True; Inc(pos); end;
    if Peek = '(' then
    begin
      Inc(pos);
      Result := ParseExpr;
      SkipWs;
      if Peek <> ')' then FatalF('formula: expected ) in "%s"', [f]);
      Inc(pos);
    end
    else if (Peek >= '0') and (Peek <= '9') then
    begin
      i := pos;
      while (pos <= Length(s)) and (((s[pos] >= '0') and (s[pos] <= '9')) or (s[pos] = '.')) do Inc(pos);
      if not ParseFloatStrict(Copy(s, i, pos - i), Result) then FatalF('formula: bad number in "%s"', [f]);
    end
    else if ((Peek >= 'a') and (Peek <= 'z')) or ((Peek >= 'A') and (Peek <= 'Z')) or (Peek = '_') then
    begin
      i := pos;
      while (pos <= Length(s)) and (s[pos] in ['a'..'z', 'A'..'Z', '0'..'9', '_']) do Inc(pos);
      id := Copy(s, i, pos - i);
      found := False;
      Result := 0;
      for i := 0 to High(syms) do
        if syms[i].name = id then begin Result := syms[i].val; found := True; Break; end;
      if not found then
      begin
        if FindStat(id) >= 0 then
          FatalF('formula "%s": identifier "%s" is not a flat/attr/level — derived referencing derived or unknown', [f, id])
        else
          FatalF('formula "%s": unknown identifier "%s"', [f, id]);
      end;
    end
    else
      FatalF('formula "%s": unexpected char "%s" at %d', [f, Peek, pos]);
    if neg then Result := -Result;
  end;
  function ParseExpr: Single;
  var
    v: Single;
    op: Char;
  begin
    v := ParseTerm;
    while True do
    begin
      SkipWs;
      if (pos <= Length(s)) and ((s[pos] = '+') or (s[pos] = '-')) then
      begin
        op := s[pos]; Inc(pos);
        if op = '+' then v := v + ParseTerm else v := v - ParseTerm;
      end
      else Break;
    end;
    Result := v;
  end;
begin
  s := f;
  pos := 1;
  Result := ParseExpr;
  SkipWs;
  if pos <= Length(s) then FatalF('formula "%s": trailing garbage at %d', [f, pos]);
end;

procedure CollectFlats(const p: TPlayer; var flats: TFlatArr);
var
  e: TSkillEffect;
  i, j: Integer;
  sp: TStrArray;
  kv: TStrArray;
  v: Single;
  ri: Integer;
  procedure AddFlat(const id: string; v: Single);
  begin
    SetLength(flats, Length(flats) + 1);
    flats[High(flats)].name := id;
    flats[High(flats)].val := v;
  end;
begin
  SetLength(flats, 0);
  // race resists
  ri := FindRace(p.raceId);
  if ri >= 0 then
    for i := 0 to High(GRaces[ri].resists) do
    begin
      kv := SplitStr(GRaces[ri].resists[i], '=');
      if (Length(kv) = 2) and ParseFloatStrict(kv[1], v) then AddFlat(kv[0] + '_res', v);
    end;
  // gear
  for i := 0 to SLOT_COUNT - 1 do
    if p.gear[i].base <> '' then
    begin
      sp := Split(p.gear[i].stats, '|');
      for j := 0 to High(sp) do
      begin
        kv := SplitStr(sp[j], '=');
        if (Length(kv) = 2) and ParseFloatStrict(kv[1], v) then AddFlat(kv[0], v);
      end;
    end;
  // skill effects
  for i := 0 to High(p.skills) do
  begin
    j := FindSkill(p.skills[i]);
    if j < 0 then continue;
    for e in GSkills[j].effects do
      if e.kind = 'stat' then
        AddFlat(e.a1, e.num);
  end;
end;

function FlatSum(const flats: array of TSymbol; const id: string): Single;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(flats) do
    if flats[i].name = id then Result := Result + flats[i].val;
end;

procedure RecalcStats(var p: TPlayer);
var
  flats: array of TSymbol;
  syms: array of TSymbol;
  i, si, ci: Integer;
  base: Single;
begin
  CollectFlats(p, flats);
  SetLength(syms, 0);
  for i := 0 to 4 do
  begin
    SetLength(syms, Length(syms) + 1);
    syms[High(syms)].name := ATTR_NAMES[i];
    syms[High(syms)].val := p.attrs[i] + FlatSum(flats, ATTR_NAMES[i]);
  end;
  SetLength(syms, Length(syms) + 1);
  syms[High(syms)].name := 'level';
  syms[High(syms)].val := p.level;
  // flat stats as symbols too
  for i := 0 to High(flats) do
  begin
    // only add if not already an attr/level
    si := -1;
    for si := 0 to High(syms) do
      if syms[si].name = flats[i].name then Break;
    if (si > High(syms)) or (syms[si].name <> flats[i].name) then
    begin
      SetLength(syms, Length(syms) + 1);
      syms[High(syms)].name := flats[i].name;
      syms[High(syms)].val := flats[i].val;
    end;
  end;
  SetLength(p.statCache, 0);
  for i := 0 to High(GStats) do
  begin
    if GStats[i].kind = 'derived' then
      base := EvalFormula(GStats[i].formula, syms)
    else
      base := 0;
    // flat base from stats.dat 'base=' key
    if GStats[i].kind = 'flat' then
      base := StrToFloatDef(DataGetDef(GDB, 'data/stats.dat', 'stat:' + GStats[i].id, 'base', '0'), 0);
    SetLength(p.statCache, Length(p.statCache) + 1);
    p.statCache[High(p.statCache)].id := GStats[i].id;
    p.statCache[High(p.statCache)].val := base + FlatSum(flats, GStats[i].id);
  end;
  // class stat multipliers from data/classes.dat (hp_mul/mana_mul/stam_mul) — wired in fix pass
  ci := FindClass(p.classId);
  if ci >= 0 then
    for i := 0 to High(p.statCache) do
      if p.statCache[i].id = 'max_hp' then
        p.statCache[i].val := p.statCache[i].val * GClasses[ci].hpMul
      else if p.statCache[i].id = 'max_mana' then
        p.statCache[i].val := p.statCache[i].val * GClasses[ci].manaMul
      else if p.statCache[i].id = 'max_stamina' then
        p.statCache[i].val := p.statCache[i].val * GClasses[ci].stamMul;
end;

function GetStat(const p: TPlayer; const id: string): Single;
var
  i: Integer;
begin
  for i := 0 to High(p.statCache) do
    if p.statCache[i].id = id then Exit(p.statCache[i].val);
  // attribute?
  for i := 0 to 4 do
    if ATTR_NAMES[i] = id then Exit(p.attrs[i]);
  Result := 0;
end;

{ ================= player ================= }

function RaceFlag(const p: TPlayer; const key: string): string;
var
  ri, i: Integer;
  kv: TStrArray;
begin
  Result := '';
  ri := FindRace(p.raceId);
  if ri < 0 then Exit;
  for i := 0 to High(GRaces[ri].flags) do
  begin
    kv := SplitStr(GRaces[ri].flags[i], '=');
    if (Length(kv) = 2) and (kv[0] = key) then Exit(kv[1]);
  end;
end;

procedure NewPlayer(var p: TPlayer; const name, raceId, classId: string; hardcore: Boolean);
var
  slotIdx: Integer;
  s2: Integer;
  i: Integer;
  ci: Integer;
  kit: TStrArray;
  kv: TStrArray;
  baseId: string;
begin
  p := Default(TPlayer);
  p.name := name;
  p.raceId := raceId;
  p.classId := classId;
  p.hardcore := hardcore;
  for i := 0 to 4 do p.attrs[i] := 8;
  if RaceFlag(p, 'stat_pool_bonus') = '1' then p.attrs[RndRange(0, 4)] += 1;
  p.level := 1;
  p.xp := 0;
  p.attrPoints := 3;
  p.skillPoints := 2;
  if RaceFlag(p, 'skill_point_bonus') = '1' then p.skillPoints += 1;
  p.gold := 25;
  p.mapId := 'cinderhold';
  p.x := 24; p.y := 20;
  p.facing := 0;
  p.dead := False;
  p.flags.n := 0;
  FlagSet(p.flags, 'act', '1');
  // class kit + seeds
  ci := FindClass(classId);
  if ci < 0 then FatalF('unknown class %s', [classId]);
  kit := GClasses[ci].startKit;
  for i := 0 to High(kit) do
  begin
    kv := Split(kit[i], ':');
    if Length(kv) <> 2 then FatalF('bad start_kit token %s', [kit[i]]);
    baseId := kv[1];
    if FindItem(baseId) < 0 then FatalF('class %s start_kit: unknown item %s', [classId, baseId]);
    InvAdd(p, MakeItem(baseId, 0, 1));
  end;
  // equip kit
  for i := 0 to SLOT_COUNT - 1 do p.gear[i].base := '';
  for i := 0 to High(p.inv) do
  begin
    slotIdx := -1;
    if p.inv[i].slot = 'ring' then slotIdx := 7;
    if p.inv[i].slot = 'amulet' then slotIdx := 9;
    if slotIdx < 0 then
      for s2 := 0 to 6 do
        if SLOTS[s2] = p.inv[i].slot then slotIdx := s2;
    if (slotIdx >= 0) and (p.gear[slotIdx].base = '') then
    begin
      p.gear[slotIdx] := p.inv[i];
      p.inv[i].base := '';
    end;
  end;
  // compact empty inv entries
  for i := High(p.inv) downto 0 do
    if p.inv[i].base = '' then
    begin
      Delete(p.inv, i, 1);
    end;
  for i := 0 to High(GClasses[ci].seedSkills) do
  begin
    if FindSkill(GClasses[ci].seedSkills[i]) < 0 then
      FatalF('class %s: seed skill "%s" not in skills.dat (load-time validation should have caught this)', [classId, GClasses[ci].seedSkills[i]]);
    SetLength(p.skills, Length(p.skills) + 1);
    p.skills[High(p.skills)] := GClasses[ci].seedSkills[i];
  end;
  // starter spells: class school spells lvl<=2
  for i := 0 to High(GSpells) do
    if (GSpells[i].lvl <= 2) then
    begin
      SetLength(p.spells, Length(p.spells) + 1);
      p.spells[High(p.spells)] := GSpells[i].id;
    end;
  // quickbar: attack + first spells
  for i := 0 to QUICK_SLOTS - 1 do p.quickbar[i] := '';
  p.quickbar[0] := 'attack';
  for i := 0 to Min(High(p.spells), QUICK_SLOTS - 2) do
    p.quickbar[i + 1] := p.spells[i];
  p.rngSeed := RndUInt64;
  SeedRNG(p.rngSeed);
  RecalcStats(p);
  p.hp := GetStat(p, 'max_hp');
  p.mana := GetStat(p, 'max_mana');
  p.stamina := GetStat(p, 'max_stamina');
  QuestRefresh(p);
end;

function XPNeed(level: Integer): Integer;
begin
  Result := 100 + level * 80 + level * level * 6;
end;

procedure AddXP(var p: TPlayer; xp: Single);
var
  g: Single;
begin
  if p.level >= LEVEL_CAP then Exit;
  g := xp * (GetStat(p, 'xp_gain') / 100);
  p.xp := p.xp + Round(g);
  while (p.level < LEVEL_CAP) and (p.xp >= XPNeed(p.level)) do
  begin
    p.xp := p.xp - XPNeed(p.level);
    Inc(p.level);
    Inc(p.attrPoints);
    p.skillPoints := p.skillPoints + 2;
    if RaceFlag(p, 'skill_point_bonus') = '1' then Inc(p.skillPoints);
    Log(Format('LEVEL UP: %s reached level %d', [p.name, p.level]));
  end;
end;

{ ================= items / loot ================= }

function ResolveStats(const baseStats, extra: string): string;
var
  k: Integer;
  m: array of record id: string; v: Single; end;
  sp, kv: TStrArray;
  i, j: Integer;
  v: Single;
  procedure Add(const id: string; v: Single);
  var
    ki: Integer;
  begin
    for ki := 0 to High(m) do
      if m[ki].id = id then begin m[ki].v := m[ki].v + v; Exit; end;
    SetLength(m, Length(m) + 1);
    m[High(m)].id := id; m[High(m)].v := v;
  end;
begin
  m := nil;
  for i := 0 to 1 do
  begin
    if i = 0 then sp := Split(baseStats, '|') else sp := Split(extra, '|');
    for j := 0 to High(sp) do
    begin
      kv := SplitStr(sp[j], '=');
      if (Length(kv) = 2) and ParseFloatStrict(kv[1], v) then Add(kv[0], v);
    end;
  end;
  Result := '';
  for i := 0 to High(m) do
  begin
    if Result <> '' then Result := Result + '|';
    Result := Result + m[i].id + '=' + F2S(m[i].v, 2);
  end;
end;

function MakeItem(const baseId: string; rarity, lvl: Integer): TItemInst;
var
  bi, pi, ai: Integer;
  pool: TAffixPool;
  nAff, k: Integer;
  totalW, roll, acc: Integer;
  aff: TAffix;
  scale: Single;
begin
  bi := FindItem(baseId);
  if bi < 0 then FatalF('MakeItem: unknown item %s', [baseId]);
  if rarity < 0 then rarity := 0;
  if rarity > 5 then rarity := 5;
  Result.base := baseId;
  Result.uid := '';
  Result.slot := GItems[bi].slot;
  Result.rarity := rarity;
  Result.price := GItems[bi].price;
  Result.lvl := lvl;
  Result.seed := RndUInt64;
  Result.aff1 := ''; Result.aff2 := ''; Result.val1 := 0; Result.val2 := 0;
  Result.stats := GItems[bi].stats;
  Result.name := GItems[bi].name;
  if rarity > 0 then
  begin
    // find pool
    pool.refs := nil; pool.rarity := -1;
    for pi := 0 to High(GPools) do
      if GPools[pi].rarity = rarity then pool := GPools[pi];
    if Length(pool.refs) = 0 then FatalF('no affix pool for rarity %d', [rarity]);
    nAff := RARITY_AFFIX_COUNT[rarity];
    scale := 1 + lvl * 0.06;
    for k := 1 to nAff do
    begin
      totalW := 0;
      for pi := 0 to High(pool.refs) do Inc(totalW, pool.refs[pi].weight);
      roll := RndRange(1, totalW);
      acc := 0;
      ai := -1;
      for pi := 0 to High(pool.refs) do
      begin
        Inc(acc, pool.refs[pi].weight);
        if roll <= acc then begin ai := FindAffix(pool.refs[pi].id); Break; end;
      end;
      if ai < 0 then Fatal('affix roll failed');
      aff := GAffixes[ai];
      if k = 1 then
      begin
        Result.aff1 := aff.id;
        Result.val1 := (aff.minv + (aff.maxv - aff.minv) * (RndUInt64 mod 1000) / 1000) * scale;
        Result.stats := ResolveStats(Result.stats, aff.stat + '=' + F2S(Result.val1, 2));
        Result.name := GItems[bi].name + ' ' + aff.name;
      end
      else
      begin
        Result.aff2 := aff.id;
        Result.val2 := (aff.minv + (aff.maxv - aff.minv) * (RndUInt64 mod 1000) / 1000) * scale;
        Result.stats := ResolveStats(Result.stats, aff.stat + '=' + F2S(Result.val2, 2));
        Result.name := Result.name + ' ' + aff.name;
      end;
    end;
    Result.name := RARITY_NAMES[rarity] + ' ' + Result.name;
    Result.price := Round(GItems[bi].price * (1 + rarity * 0.8) * (1 + lvl * 0.05));
  end;
end;

function MakeUnique(const uid: string): TItemInst;
var
  ui: Integer;
begin
  ui := FindUnique(uid);
  if ui < 0 then FatalF('MakeUnique: unknown unique %s', [uid]);
  Result.base := '';
  Result.uid := uid;
  Result.slot := GUniques[ui].slot;
  Result.rarity := GUniques[ui].rarity;
  Result.price := GUniques[ui].price;
  Result.lvl := GUniques[ui].lvl;
  Result.aff1 := ''; Result.aff2 := ''; Result.val1 := 0; Result.val2 := 0;
  Result.stats := GUniques[ui].stats;
  Result.name := GUniques[ui].name;
  Result.seed := RndUInt64;
end;

function ItemName(const it: TItemInst): string;
begin
  if it.uid <> '' then Result := it.name
  else if it.rarity > 0 then Result := it.name
  else Result := it.name;
end;

procedure RollLoot(const tableId: string; lvl: Integer; var items: TItemArr; out gold: Integer);
var
  ti, i: Integer;
  e: TDropEntry;
begin
  SetLength(items, 0);
  gold := 0;
  ti := FindDropTable(tableId);
  if ti < 0 then FatalF('RollLoot: unknown table %s', [tableId]);
  for i := 0 to High(GDropTables[ti].entries) do
  begin
    e := GDropTables[ti].entries[i];
    if (lvl >= e.minLvl) and (lvl <= e.maxLvl) and RndChance(e.chance) then
    begin
      if e.itemId = 'gold' then
        gold := gold + RndRange(5, 30) * lvl
      else if e.isUnique then
      begin
        SetLength(items, Length(items) + 1);
        items[High(items)] := MakeUnique(e.itemId);
      end
      else
      begin
        SetLength(items, Length(items) + 1);
        items[High(items)] := MakeItem(e.itemId, RndRange(0, 3), lvl);
      end;
    end;
  end;
end;

function InvCount(const p: TPlayer; const id: string): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(p.inv) do
    if (p.inv[i].base = id) or (p.inv[i].uid = id) then Inc(Result);
  for i := 0 to SLOT_COUNT - 1 do
    if (p.gear[i].base = id) or (p.gear[i].uid = id) then Inc(Result);
end;

procedure InvAdd(var p: TPlayer; const it: TItemInst);
begin
  if Length(p.inv) >= MAX_INV then
  begin
    Log('inventory full — item lost to the ash');
    Exit;
  end;
  SetLength(p.inv, Length(p.inv) + 1);
  p.inv[High(p.inv)] := it;
end;

function FindInv(const p: TPlayer; idx: Integer): Integer;
begin
  if (idx >= 0) and (idx <= High(p.inv)) then Result := idx else Result := -1;
end;

procedure EquipFromInv(var p: TPlayer; invIdx: Integer);
var
  it: TItemInst;
  slotIdx, i: Integer;
begin
  if (invIdx < 0) or (invIdx > High(p.inv)) then Exit;
  it := p.inv[invIdx];
  slotIdx := -1;
  if it.slot = 'ring' then slotIdx := 7;
  if it.slot = 'amulet' then slotIdx := 9;
  if slotIdx < 0 then
    for i := 0 to 6 do
      if SLOTS[i] = it.slot then slotIdx := i;
  if slotIdx < 0 then Exit;
  // two-hand occupies offhand
  if (it.slot = 'weapon') and (FindItem(it.base) >= 0) and GItems[FindItem(it.base)].twoHand then
    if p.gear[1].base <> '' then InvAdd(p, p.gear[1]);
  if p.gear[slotIdx].base <> '' then InvAdd(p, p.gear[slotIdx]);
  if (it.slot = 'ring') and (p.gear[8].base <> '') then
  begin
    p.gear[8] := p.gear[7];
  end;
  p.gear[slotIdx] := it;
  Delete(p.inv, invIdx, 1);
  RecalcStats(p);
end;

{ ================= store ================= }

function StorePriceMul(const p: TPlayer; const mapId: string): Single;
var
  i: Integer;
  trust: Integer;
  regId: string;
  pm: Single;
begin
  Result := 1.0;
  trust := 0;
  if ParseIntStrict(FlagGet(p.flags, 'compact.trust'), trust) then ;
  Result := Result * (1 - Min(trust, 5) * 0.04);
  // region flags
  regId := '';
  for i := 0 to High(GRegions) do
    if GRegions[i].hubMap = mapId then regId := GRegions[i].id;
  if (regId = 'glass') and FlagEq(p.flags, 'compact.supply_glass', '1') then Result := Result * 0.85;
  if (regId = 'maren') and FlagEq(p.flags, 'compact.block_maren', '1') then Result := Result * 1.5;
  if ParseFloatStrict(FlagGet(p.flags, 'store.price_mul'), pm) then Result := Result * pm;
  if ParseFloatStrict(RaceFlag(p, 'store_mul'), pm) then Result := Result * pm;
end;

function StorePrice(const p: TPlayer; const mapId, itemId: string): Integer;
var
  ii, ui: Integer;
  base: Integer;
begin
  ii := FindItem(itemId);
  ui := FindUnique(itemId);
  if ii >= 0 then base := GItems[ii].price
  else if ui >= 0 then base := GUniques[ui].price
  else FatalF('StorePrice: unknown item %s', [itemId]);
  Result := Max(1, Round(base * StorePriceMul(p, mapId)));
end;

function SellPrice(const p: TPlayer; const mapId: string; const it: TItemInst): Integer;
begin
  Result := Max(1, Round(it.price * 0.4 * StorePriceMul(p, mapId)));
end;

function StoreStockVisible(const p: TPlayer; const st: TStore; entryIdx: Integer): Boolean;
var
  trust: Integer;
begin
  trust := 0;
  if ParseIntStrict(FlagGet(p.flags, 'compact.trust'), trust) then ;
  // blockade hides maren stock above minTrust 0
  if (st.map = 'maren_hub') and FlagEq(p.flags, 'compact.block_maren', '1') then
    Result := st.stock[entryIdx].minTrust <= 0
  else
    Result := trust >= st.stock[entryIdx].minTrust;
end;

{ ================= quests / rules ================= }

function CondHolds(const p: TPlayer; const cond: string): Boolean;
var
  kv: TStrArray;
begin
  kv := SplitStr(cond, '==');
  if Length(kv) <> 2 then FatalF('bad condition "%s"', [cond]);
  if kv[0] = 'act' then Result := FlagGet(p.flags, 'act') = kv[1]
  else Result := FlagGet(p.flags, kv[0]) = kv[1];
end;

function QuestState(const p: TPlayer; const qid: string): string;
var
  i: Integer;
begin
  for i := 0 to High(p.quests) do
    if p.quests[i].id = qid then Exit(p.quests[i].state);
  Result := '';
end;

procedure QuestRefresh(var p: TPlayer);
var
  i, j: Integer;
  qi: Integer;
  ok: Boolean;
begin
  for i := 0 to High(GQuests) do
  begin
    qi := -1;
    for j := 0 to High(p.quests) do
      if p.quests[j].id = GQuests[i].id then qi := j;
    if (qi >= 0) and (p.quests[qi].state <> 'locked') and (p.quests[qi].state <> '') then Continue;
    // not tracked yet, or locked: evaluate requires
    ok := True;
    for j := 0 to High(GQuests[i].reqFlags) do
      if not CondHolds(p, GQuests[i].reqFlags[j]) then begin ok := False; Break; end;
    if qi < 0 then
    begin
      SetLength(p.quests, Length(p.quests) + 1);
      p.quests[High(p.quests)].id := GQuests[i].id;
      SetLength(p.quests[High(p.quests)].obj, Length(GQuests[i].objectives));
      qi := High(p.quests);
    end;
    if ok then p.quests[qi].state := 'available' else p.quests[qi].state := 'locked';
  end;
end;

procedure QuestAccept(var p: TPlayer; const qid: string);
var
  i: Integer;
begin
  for i := 0 to High(p.quests) do
    if (p.quests[i].id = qid) and (p.quests[i].state = 'available') then
      p.quests[i].state := 'active';
end;

procedure CompleteQuest(var p: TPlayer; const qid: string);
var
  actBefore: string;
  rid: string;
  rest: string;
  kv2: TStrArray;
  qi, oi, j: Integer;
  tok: string;
begin
  qi := FindQuest(qid);
  if qi < 0 then Exit;
  actBefore := FlagGet(p.flags, 'act');
  for j := 0 to High(p.quests) do
    if p.quests[j].id = qid then
    begin
      p.quests[j].state := 'complete';
      Break;
    end;
  AddXP(p, GQuests[qi].rewardXP);
  p.gold := p.gold + GQuests[qi].rewardGold;
  FlagSet(p.flags, 'quest.' + qid + '.completed', '1');
  for j := 0 to High(GQuests[qi].rewardItems) do
  begin
    rid := GQuests[qi].rewardItems[j];
    if StartsWith(rid, 'u:') then
    begin
      rid := Copy(rid, 3, Length(rid));
      if FindUnique(rid) < 0 then FatalF('quest %s reward: unknown unique %s', [qid, rid]);
      InvAdd(p, MakeUnique(rid));
    end
    else if FindItem(rid) >= 0 then InvAdd(p, MakeItem(rid, 0, p.level))
    else FatalF('quest %s reward: unknown item %s', [qid, rid]);
  end;
  for j := 0 to High(GQuests[qi].onComplete) do
  begin
    tok := GQuests[qi].onComplete[j];
    // format set:key=val — split at first ':' then '='
    rest := Copy(GQuests[qi].onComplete[j], 5, Length(GQuests[qi].onComplete[j])); // strip 'set:'
    kv2 := SplitStr(rest, '=');
    if Length(kv2) = 2 then FlagSet(p.flags, kv2[0], kv2[1]);
  end;
  for j := 0 to High(GQuests[qi].unlocks) do
    FlagSet(p.flags, 'quest.' + GQuests[qi].unlocks[j] + '.unlocked', '1');
  if FlagGet(p.flags, 'act') <> actBefore then
    FireRules(p, 'act:' + FlagGet(p.flags, 'act'));
  Log('QUEST COMPLETE: ' + GQuests[qi].title);
  FireRules(p, 'quest:' + qid);
  QuestRefresh(p);
end;

procedure QuestEvent(var p: TPlayer; const ev, arg: string);
var
  found: Boolean;
  k: Integer;
  i, j, qi: Integer;
  allDone: Boolean;
begin
  if ev = 'kill' then
  begin
    found := False;
    for i := 0 to High(p.kills) do
      if p.kills[i].mid = arg then begin Inc(p.kills[i].n); found := True; Break; end;
    if not found then
    begin
      SetLength(p.kills, Length(p.kills) + 1);
      p.kills[High(p.kills)].mid := arg;
      p.kills[High(p.kills)].n := 1;
    end;
  end;
  if ev = 'reach' then
    FlagSet(p.flags, 'map.visited.' + arg, '1');
  for i := 0 to High(p.quests) do
  begin
    if p.quests[i].state <> 'active' then Continue;
    qi := FindQuest(p.quests[i].id);
    if qi < 0 then Continue;
    allDone := True;
    for j := 0 to High(GQuests[qi].objectives) do
    begin
      with GQuests[qi].objectives[j] do
      begin
        if (kind = ev) and (target = arg) then
          if p.quests[i].obj[j] < count then Inc(p.quests[i].obj[j]);
        // derived progress
        if kind = 'kill' then
        begin
          for k := 0 to High(p.kills) do
            if p.kills[k].mid = target then p.quests[i].obj[j] := p.kills[k].n;
        end;
        if kind = 'collect' then
          p.quests[i].obj[j] := Min(count, InvCount(p, target));
        if p.quests[i].obj[j] < count then allDone := False;
      end;
    end;
    if allDone then CompleteQuest(p, p.quests[i].id);
  end;
  QuestRefresh(p);
end;

procedure QuestTick(var p: TPlayer);
var
  i, qi: Integer;
begin
  for i := 0 to High(p.quests) do
  begin
    if p.quests[i].state <> 'active' then Continue;
    qi := FindQuest(p.quests[i].id);
    if qi < 0 then Continue;
    if (GQuests[qi].failIf <> '') and CondHolds(p, GQuests[qi].failIf) then
    begin
      p.quests[i].state := 'failed';
      Log('QUEST FAILED: ' + GQuests[qi].title);
      FireRules(p, 'quest_fail:' + p.quests[i].id);
    end;
  end;
end;

procedure FireRules(var p: TPlayer; const trigger: string);
var
  i, j: Integer;
  tok: string;
  kv: TStrArray;
begin
  for i := 0 to High(GRules) do
  begin
    if GRules[i].on <> trigger then Continue;
    if (GRules[i].ifKey <> '') and (not FlagEq(p.flags, GRules[i].ifKey, GRules[i].ifVal)) then Continue;
    for j := 0 to High(GRules[i].thenList) do
    begin
      tok := GRules[i].thenList[j];
      if StartsWith(tok, 'set:') then
      begin
        kv := SplitStr(Copy(tok, 5, Length(tok)), '=');
        if Length(kv) = 2 then
        begin
          FlagSet(p.flags, kv[0], kv[1]);
          FireRules(p, 'flag:' + kv[0]);
        end;
      end;
    end;
  end;
end;

procedure SetAct(var p: TPlayer; act: Integer);
begin
  FlagSet(p.flags, 'act', I2S(act));
  FireRules(p, 'act:' + I2S(act));
  QuestRefresh(p);
end;

{ ================= combat ================= }

function ElemAdv(const atkElem, defElem: string): Single;
var
  ei: Integer;
begin
  Result := 0;
  if (atkElem = '') or (atkElem = 'raw') or (defElem = '') or (defElem = 'raw') then Exit;
  ei := FindElement(atkElem);
  if (ei >= 0) and (GElements[ei].beats = defElem) then Result := 0.25;
  ei := FindElement(defElem);
  if (ei >= 0) and (GElements[ei].beats = atkElem) then Result := -0.25;
end;

function CalcHitDamage(weapDmg: Single; elem: string; critChance, critDmg: Single;
  targetRes: Single; targetArmor: Single; backstabMul: Single; isCrit: Boolean): Single;
var
  d: Single;
begin
  d := weapDmg;
  if isCrit then d := d * (critDmg / 100);
  d := d * (1 + ElemAdv(elem, 'raw')); // elem vs physical handled by caller via resists; keep neutral here
  d := d * Max(0.2, 1 - targetArmor * 0.03);
  d := d * Max(0, 1 - targetRes / 100);
  if isCrit then ; // backstab applied by caller
  Result := d;
end;

procedure AddDmgNum(x, y: Single; dmg: Single; crit: Boolean; const txt: string);
begin
  SetLength(GDmgNums, Length(GDmgNums) + 1);
  GDmgNums[High(GDmgNums)].x := x;
  GDmgNums[High(GDmgNums)].y := y;
  GDmgNums[High(GDmgNums)].val := dmg;
  GDmgNums[High(GDmgNums)].crit := crit;
  GDmgNums[High(GDmgNums)].t := 0;
  GDmgNums[High(GDmgNums)].txt := txt;
end;

procedure DamagePlayer(var p: TPlayer; dmg: Single; elem: string; fromX, fromY: Single);
var
  res, armor, block, parryC: Single;
  isCrit: Boolean;
  ang: Single;
begin
  if p.dead then Exit;
  if p.dodgeT > 0 then
  begin
    AddDmgNum(p.x, p.y - 0.5, 0, False, 'DODGE');
    Exit;
  end;
  res := GetStat(p, elem + '_res') + GetStat(p, 'all_res');
  armor := GetStat(p, 'armor');
  block := GetStat(p, 'block');
  parryC := GetStat(p, 'parry');
  isCrit := RndChance(5 / 100);
  // block: facing attacker?
  ang := ArcTan2(fromY - p.y, fromX - p.x);
  if p.blockHeld and (Abs(ang - p.facing) < 1.2) then
    dmg := dmg * Max(0.2, 1 - block / 100);
  if RndChance(parryC / 100) then
  begin
    AddDmgNum(p.x, p.y - 0.5, 0, False, 'PARRY');
    Exit;
  end;
  dmg := dmg * Max(0, 1 - res / 100) * Max(0.3, 1 - armor * 0.03);
  if isCrit then dmg := dmg * 1.5;
  p.hp := p.hp - dmg;
  AddDmgNum(p.x, p.y - 0.6, dmg, isCrit, '-' + F2S(dmg, 0));
  if p.hp <= 0 then KillPlayer(p);
end;

procedure KillPlayer(var p: TPlayer);
begin
  if p.dead then Exit;
  p.dead := True;
  Inc(p.deaths);
  p.corpseMap := p.mapId;
  p.corpseX := p.x;
  p.corpseY := p.y;
  p.lostXP := Round(p.xp * 0.25);
  p.xp := p.xp - p.lostXP;
  p.corpseLooted := RndChance(0.35);
  if p.corpseLooted then FireRules(p, 'death:corpse_looted');
  Log(Format('PLAYER DIED at %s (%.1f,%.1f) — lost %d XP, corpse %s', [p.mapId, p.x, p.y, p.lostXP, BoolToStr(p.corpseLooted, True)]));
end;

procedure PlayerAttack(var p: TPlayer; const aimX, aimY: Single);
var
  dd: Single;
  items: array of TItemInst;
  gold: Integer;
  ii: Integer;
  i: Integer;
  dmg, critC, critD, range, arc: Single;
  isCrit, backstab: Boolean;
  dx, dy, dist, ang, dAng: Single;
begin
  if p.dead then Exit;
  if p.atkCd > 0 then Exit;
  p.atkCd := 0.45 / Max(0.5, GetStat(p, 'attack_speed'));
  p.combo := (p.combo + 1) mod 3;
  p.facing := ArcTan2(aimY - p.y, aimX - p.x);
  range := 1.7;
  arc := 1.9;
  dmg := GetStat(p, 'melee_dmg') * (1 + p.combo * 0.25) + GetStat(p, 'melee_dmg_pct') / 100 * GetStat(p, 'melee_dmg');
  critC := GetStat(p, 'crit_chance');
  critD := GetStat(p, 'crit_dmg');
  for i := 0 to High(GEnts) do
    if (GEnts[i].kind = ekMonster) and GEnts[i].alive then
    begin
      dx := GEnts[i].x - p.x; dy := GEnts[i].y - p.y;
      dist := PointDist(p.x, p.y, GEnts[i].x, GEnts[i].y);
      if dist > range + GEnts[i].size then Continue;
      ang := ArcTan2(dy, dx);
      dAng := Abs(ang - p.facing);
      if dAng > 3.14159 then dAng := 2 * 3.14159 - dAng;
      if dAng > arc then Continue;
      isCrit := RndChance(critC / 100);
      backstab := AngDiff(GEnts[i].facing, ArcTan2(p.y - GEnts[i].y, p.x - GEnts[i].x)) > 2.0;
      dd := CalcHitDamage(dmg, 'raw', critC, critD, 0, GEnts[i].armor, 1, isCrit);
      if backstab then dd := dd * GetStat(p, 'backstab_mul');
      dd := dd * (1 + GetStat(p, 'element_dmg') / 100);
      GEnts[i].hp := GEnts[i].hp - dd;
      AddDmgNum(GEnts[i].x, GEnts[i].y - GEnts[i].size, dd, isCrit, F2S(dd, 0));
      if GEnts[i].hp <= 0 then
      begin
        GEnts[i].alive := False;
        AddXP(p, GEnts[i].xp);
        p.gold := p.gold + Round(GEnts[i].goldMin + (GEnts[i].goldMax - GEnts[i].goldMin) * (RndUInt64 mod 100) / 100);
        QuestEvent(p, 'kill', GEnts[i].id);
        if GEnts[i].dropTable <> '' then
        begin
          RollLoot(GEnts[i].dropTable, p.level, items, gold);
          p.gold := p.gold + gold;
          for ii := 0 to High(items) do
          begin
            InvAdd(p, items[ii]);
            Log('LOOT: ' + items[ii].name);
          end;
        end;
        Log('KILL: ' + GEnts[i].name);
      end;
    end;
end;

procedure CastQuickbar(var p: TPlayer; slot: Integer; aimX, aimY: Single);
var
  tx: Single;
  ty: Single;
  i: Integer;
  dd: Single;
  sid: string;
  si: Integer;
  dist: Single;
  sp: TSpell;
  e: TEnt;
begin
  if p.dead then Exit;
  if (slot < 0) or (slot >= QUICK_SLOTS) then Exit;
  sid := p.quickbar[slot];
  if sid = '' then Exit;
  if sid = 'attack' then
  begin
    PlayerAttack(p, aimX, aimY);
    Exit;
  end;
  si := FindSpell(sid);
  if si < 0 then Exit;
  sp := GSpells[si];
  if p.mana < sp.mana then Exit;
  p.mana := p.mana - sp.mana;
  p.facing := ArcTan2(aimY - p.y, aimX - p.x);
  dist := PointDist(p.x, p.y, aimX, aimY);
  if sp.range > 0 then
    dist := Min(dist, sp.range);
  case sp.kind of
    'bolt', 'dot':
    begin
      SetLength(GEnts, Length(GEnts) + 1);
      e := Default(TEnt);
      e.kind := ekProjectile;
      e.alive := True;
      e.x := p.x; e.y := p.y;
      e.vx := (aimX - p.x) / Max(0.01, PointDist(p.x, p.y, aimX, aimY)) * sp.projSpeed;
      e.vy := (aimY - p.y) / Max(0.01, PointDist(p.x, p.y, aimX, aimY)) * sp.projSpeed;
      e.pdmg := sp.dmg * (GetStat(p, 'spell_dmg') / 3 + 1);
      e.pelement := sp.element;
      e.plife := sp.range / sp.projSpeed + 0.2;
      e.fromPlayer := True;
      e.name := sp.name;
      GEnts[High(GEnts)] := e;
    end;
    'aoe', 'nova':
    begin
      tx := aimX; ty := aimY;
      if sp.kind = 'nova' then begin tx := p.x; ty := p.y; end;
      for i := 0 to High(GEnts) do
        if (GEnts[i].kind = ekMonster) and GEnts[i].alive and (PointDist(tx, ty, GEnts[i].x, GEnts[i].y) <= sp.radius + GEnts[i].size) then
        begin
          dd := sp.dmg * (GetStat(p, 'spell_dmg') / 3 + 1) * (1 + ElemAdv(sp.element, GEnts[i].element)) * (1 + GetStat(p, 'element_dmg') / 100);
          dd := dd * Max(0, 1 - 0 / 100);
          GEnts[i].hp := GEnts[i].hp - dd;
          AddDmgNum(GEnts[i].x, GEnts[i].y - GEnts[i].size, dd, False, F2S(dd, 0));
          if GEnts[i].hp <= 0 then
          begin
            GEnts[i].alive := False;
            AddXP(p, GEnts[i].xp);
            QuestEvent(p, 'kill', GEnts[i].id);
          end;
        end;
    end;
    'dash':
    begin
      p.x := p.x + (aimX - p.x) / Max(0.01, PointDist(p.x, p.y, aimX, aimY)) * Min(dist, sp.range);
      p.y := p.y + (aimY - p.y) / Max(0.01, PointDist(p.x, p.y, aimX, aimY)) * Min(dist, sp.range);
      p.dodgeT := 0.3;
    end;
    'buff', 'heal':
    begin
      if sp.kind = 'heal' then
        p.hp := Min(GetStat(p, 'max_hp'), p.hp + 20 + GetStat(p, 'spell_dmg'));
      AddDmgNum(p.x, p.y - 0.6, 0, False, sp.name);
    end;
  end;
end;

procedure SpawnMonster(const mid: string; x, y: Single);
var
  mi: Integer;
  e: TEnt;
begin
  mi := FindMonster(mid);
  if mi < 0 then FatalF('SpawnMonster: unknown monster %s', [mid]);
  if Length(GEnts) >= MAX_ENTS then Exit;
  e := Default(TEnt);
  e.kind := ekMonster;
  e.id := mid;
  e.name := GMonsters[mi].name;
  e.x := x; e.y := y;
  e.hp := GMonsters[mi].hp;
  e.maxhp := GMonsters[mi].hp;
  e.alive := True;
  e.behavior := GMonsters[mi].behavior;
  e.element := GMonsters[mi].element;
  e.dmg := GMonsters[mi].dmg;
  e.speed := GMonsters[mi].speed;
  e.aggro := GMonsters[mi].aggroRange;
  e.attackRange := GMonsters[mi].attackRange;
  e.windup := GMonsters[mi].windup;
  e.armor := GMonsters[mi].armor;
  e.size := GMonsters[mi].size;
  e.scale := GMonsters[mi].scale;
  e.xp := GMonsters[mi].xp;
  e.goldMin := GMonsters[mi].goldMin;
  e.goldMax := GMonsters[mi].goldMax;
  e.dropTable := GMonsters[mi].dropTable;
  e.boss := GMonsters[mi].boss;
  e.abilities := GMonsters[mi].abilities;
  e.state := 0;
  e.stateT := 0;
  e.atkCd := 0;
  e.facing := 0;
  SetLength(GEnts, Length(GEnts) + 1);
  GEnts[High(GEnts)] := e;
end;

procedure UpdateCombat(var p: TPlayer; dt: Single);
var
  dd: Single;
  items: array of TItemInst;
  gold: Integer;
  ii: Integer;
  pr: TEnt;
  dd2: Single;
  i, j: Integer;
  e: TEnt;
  dist: Single;
  dx, dy: Single;
begin
  GTime := GTime + dt;
  p.playTime := p.playTime + dt;
  if p.atkCd > 0 then p.atkCd := p.atkCd - dt;
  if p.dodgeT > 0 then p.dodgeT := p.dodgeT - dt;
  // regen
  if not p.dead then
  begin
    p.hp := Min(GetStat(p, 'max_hp'), p.hp + GetStat(p, 'hp_regen') * dt);
    p.mana := Min(GetStat(p, 'max_mana'), p.mana + GetStat(p, 'mana_regen') * dt);
    p.stamina := Min(GetStat(p, 'max_stamina'), p.stamina + GetStat(p, 'stamina_regen') * dt);
  end;
  for i := High(GEnts) downto 0 do
  begin
    e := GEnts[i];
    if not e.alive then
    begin
      if e.kind = ekProjectile then Delete(GEnts, i, 1);
      Continue;
    end;
    if e.kind = ekProjectile then
    begin
      e.x := e.x + e.vx * dt;
      e.y := e.y + e.vy * dt;
      e.plife := e.plife - dt;
      if e.plife <= 0 then begin GEnts[i].alive := False; Continue; end;
      if e.fromPlayer then
      begin
        for j := 0 to High(GEnts) do
          if (GEnts[j].kind = ekMonster) and GEnts[j].alive and (PointDist(e.x, e.y, GEnts[j].x, GEnts[j].y) < GEnts[j].size + 0.25) then
          begin
            dd := e.pdmg * (1 + ElemAdv(e.pelement, GEnts[j].element)) * Max(0.3, 1 - GEnts[j].armor * 0.03);
            GEnts[j].hp := GEnts[j].hp - dd;
            AddDmgNum(GEnts[j].x, GEnts[j].y - GEnts[j].size, dd, False, F2S(dd, 0));
            if GEnts[j].hp <= 0 then
            begin
              GEnts[j].alive := False;
              AddXP(p, GEnts[j].xp);
              p.gold := p.gold + Round(GEnts[j].goldMin + (GEnts[j].goldMax - GEnts[j].goldMin) * (RndUInt64 mod 100) / 100);
              QuestEvent(p, 'kill', GEnts[j].id);
              if GEnts[j].dropTable <> '' then
              begin
                RollLoot(GEnts[j].dropTable, p.level, items, gold);
                p.gold := p.gold + gold;
                for ii := 0 to High(items) do InvAdd(p, items[ii]);
              end;
            end;
            GEnts[i].alive := False;
            Break;
          end;
      end
      else
      begin
        if PointDist(e.x, e.y, p.x, p.y) < 0.4 then
        begin
          DamagePlayer(p, e.pdmg, e.pelement, e.x - e.vx, e.y - e.vy);
          GEnts[i].alive := False;
        end;
      end;
      GEnts[i] := e;
      Continue;
    end;
    if e.kind <> ekMonster then Continue;
    // monster AI
    dist := PointDist(e.x, e.y, p.x, p.y);
    if p.dead then dist := 1e9;
    e.atkCd := e.atkCd - dt;
    case e.state of
      0: begin // idle
        if dist < e.aggro then e.state := 1;
      end;
      1: begin // chase
        if dist <= e.attackRange then
        begin
          e.state := 2;
          e.stateT := e.windup * IIfS(e.enraged, 0.7, 1.0);
        end
        else if dist < e.aggro then
        begin
          dx := (p.x - e.x) / dist; dy := (p.y - e.y) / dist;
          e.x := e.x + dx * e.speed * dt;
          e.y := e.y + dy * e.speed * dt;
          e.facing := ArcTan2(dy, dx);
        end
        else e.state := 0;
      end;
      2: begin // windup — telegraph visible to renderer
        e.stateT := e.stateT - dt;
        e.facing := ArcTan2(p.y - e.y, p.x - e.x);
        if e.stateT <= 0 then
        begin
          e.state := 3;
          e.stateT := 0.15;
        end;
      end;
      3: begin // strike
        if e.behavior = 'ranged' then
        begin
          SetLength(GEnts, Length(GEnts) + 1);
          pr := Default(TEnt);
          pr.kind := ekProjectile;
          pr.alive := True;
          pr.x := e.x; pr.y := e.y;
          dd2 := Max(0.01, dist);
          pr.vx := (p.x - e.x) / dd2 * 11;
          pr.vy := (p.y - e.y) / dd2 * 11;
          pr.pdmg := e.dmg * IIfS(e.enraged, 1.3, 1.0);
          pr.pelement := e.element;
          pr.plife := 3;
          pr.fromPlayer := False;
          pr.name := e.name + ' bolt';
          GEnts[High(GEnts)] := pr;
        end
        else
        begin
          if dist < e.attackRange + 0.6 then
            DamagePlayer(p, e.dmg * IIfS(e.enraged, 1.3, 1.0), e.element, e.x, e.y);
        end;
        e.state := 4;
        e.stateT := 1.2;
        e.atkCd := 1.2;
      end;
      4: begin
        e.stateT := e.stateT - dt;
        if e.stateT <= 0 then e.state := 1;
      end;
    end;
    // boss enrage
    if e.boss and (not e.enraged) and (e.hp < e.maxhp * 0.3) then
    begin
      e.enraged := True;
      Log('BOSS ENRAGED: ' + e.name);
    end;
    // summoner ability
    if (e.behavior = 'summoner') and (e.state = 1) and (e.atkCd <= 0) then
    begin
      for j := 0 to High(e.abilities) do
        if StartsWith(e.abilities[j], 'summon:') then
        begin
          SpawnMonster(Copy(e.abilities[j], 8, 99), e.x + RndRange(-2, 2) / 2, e.y + RndRange(-2, 2) / 2);
          e.atkCd := 6;
        end;
    end;
    GEnts[i] := e;
  end;
  // damage numbers
  for i := High(GDmgNums) downto 0 do
  begin
    GDmgNums[i].t := GDmgNums[i].t + dt;
    if GDmgNums[i].t > 1.2 then Delete(GDmgNums, i, 1);
  end;
  QuestTick(p);
end;

procedure InteractAt(var p: TPlayer; x, y: Single);
var
  items: array of TItemInst;
  gold: Integer;
  ii: Integer;
  i: Integer;
  best, bd: Integer;
begin
  best := -1; bd := 2;
  for i := 0 to High(GEnts) do
    if GEnts[i].alive and (GEnts[i].kind in [ekMarker, ekChest, ekLore, ekStore, ekNpc]) then
      if PointDist(x, y, GEnts[i].x, GEnts[i].y) < bd then begin bd := Round(PointDist(x, y, GEnts[i].x, GEnts[i].y) * 10); best := i; end;
  if best < 0 then Exit;
  case GEnts[best].kind of
    ekMarker: if not GEnts[best].used then begin GEnts[best].used := True; QuestEvent(p, 'interact', GEnts[best].id); end;
    ekChest: if not GEnts[best].used then
      begin
        GEnts[best].used := True;
        RollLoot(GEnts[best].id, p.level, items, gold);
        p.gold := p.gold + gold;
        for ii := 0 to High(items) do InvAdd(p, items[ii]);
        Log(Format('CHEST opened: +%d gold, %d items', [gold, Length(items)]));
      end;
    ekLore: if not GEnts[best].used then
      begin
        GEnts[best].used := True;
        SetLength(p.lore, Length(p.lore) + 1);
        p.lore[High(p.lore)] := GEnts[best].id;
        if StartsWith(GEnts[best].id, 'lore_') then QuestEvent(p, 'collect', GEnts[best].id);
        Log('LORE read: ' + GEnts[best].id);
      end;
  end;
end;

{ ================= save / load ================= }

function SaveGame(const p: TPlayer; const slotName: string; out err: string): Boolean;
var
  payload: string;
  i, j: Integer;
  f: TextFile;
  path: string;
  crc: LongWord;
  procedure L(const s: string);
  begin
    payload := payload + s + #10;
  end;
begin
  Result := False;
  err := '';
  payload := '';
  L('name=' + p.name);
  L('race=' + p.raceId);
  L('class=' + p.classId);
  L('hardcore=' + BoolToStr(p.hardcore, True));
  L('attrs=' + I2S(p.attrs[0]) + ',' + I2S(p.attrs[1]) + ',' + I2S(p.attrs[2]) + ',' + I2S(p.attrs[3]) + ',' + I2S(p.attrs[4]));
  L('level=' + I2S(p.level));
  L('xp=' + I2S(p.xp));
  L('attrPoints=' + I2S(p.attrPoints));
  L('skillPoints=' + I2S(p.skillPoints));
  L('gold=' + I2S(p.gold));
  L('hp=' + F2S(p.hp, 2));
  L('mana=' + F2S(p.mana, 2));
  L('stamina=' + F2S(p.stamina, 2));
  L('x=' + F2S(p.x, 3));
  L('y=' + F2S(p.y, 3));
  L('map=' + p.mapId);
  L('deaths=' + I2S(p.deaths));
  L('day=' + I2S(p.day));
  L('rng=' + IntToStr(Int64(p.rngSeed)));
  L('flags=' + I2S(p.flags.n));
  for i := 0 to p.flags.n - 1 do
    L('flag=' + p.flags.items[i].key + '=' + p.flags.items[i].value);
  L('gearN=' + I2S(SLOT_COUNT));
  for i := 0 to SLOT_COUNT - 1 do
    with p.gear[i] do
      L('gear=' + base + ';' + uid + ';' + name + ';' + slot + ';' + I2S(rarity) + ';' + aff1 + ';' + aff2 + ';' + F2S(val1, 3) + ';' + F2S(val2, 3) + ';' + stats + ';' + I2S(price) + ';' + I2S(lvl) + ';' + IntToStr(Int64(seed)));
  L('invN=' + I2S(Length(p.inv)));
  for i := 0 to High(p.inv) do
    with p.inv[i] do
      L('inv=' + base + ';' + uid + ';' + name + ';' + slot + ';' + I2S(rarity) + ';' + aff1 + ';' + aff2 + ';' + F2S(val1, 3) + ';' + F2S(val2, 3) + ';' + stats + ';' + I2S(price) + ';' + I2S(lvl) + ';' + IntToStr(Int64(seed)));
  L('qb=' + Join(p.quickbar, '|'));
  L('spells=' + Join(p.spells, '|'));
  L('skills=' + Join(p.skills, '|'));
  L('questN=' + I2S(Length(p.quests)));
  for i := 0 to High(p.quests) do
    L('quest=' + p.quests[i].id + '|' + p.quests[i].state + '|' + Join(ArrI2S(p.quests[i].obj), ','));
  L('lore=' + Join(p.lore, '|'));
  L('killsN=' + I2S(Length(p.kills)));
  for i := 0 to High(p.kills) do
    L('kill=' + p.kills[i].mid + '|' + I2S(p.kills[i].n));
  L('corpse=' + p.corpseMap + '|' + F2S(p.corpseX, 2) + '|' + F2S(p.corpseY, 2) + '|' + I2S(p.lostXP) + '|' + BoolToStr(p.corpseLooted, True));
  crc := CRC32OfStr(payload);
  path := 'saves/' + slotName + '.sav';
  try
    ForceDirectories('saves');
    Assign(f, path);
    Rewrite(f);
    Writeln(f, SAVE_MAGIC);
    Writeln(f, I2S(SAVE_VERSION));
    Writeln(f, IntToHex(crc, 8));
    Write(f, payload);
    Close(f);
    Result := True;
  except
    on E: Exception do err := E.Message;
  end;
end;

function LoadGame(var p: TPlayer; const slotName: string; out err: string): Boolean;
var
  ap: TStrArray;
  rest: string;
  k2: string;
  v2: string;
  eq: Integer;
  parts: TStrArray;
  gi: Integer;
  s: Integer;
  op: TStrArray;
  k: Integer;
  cp: TStrArray;
  qp: TStrArray;
  f: TextFile;
  path, magic: string;
  ver: Integer;
  crcStr, payload, line: string;
  crc: LongWord;
  lines: TStrArray;
  i: Integer;
  v: string;
  procedure Bad(const why: string);
  begin
    err := 'corrupt/tampered save ' + path + ': ' + why;
    Result := False;
  end;
  function NeedKey(const key: string; out val: string): Boolean;
  var
    k: Integer;
  begin
    Result := False;
    val := '';
    for k := 0 to High(lines) do
      if StartsWith(lines[k], key + '=') then begin val := Copy(lines[k], Length(key) + 2, Length(lines[k])); Result := True; Exit; end;
    if not Result then Bad('missing key ' + key);
  end;
begin
  Result := False;
  err := '';
  path := 'saves/' + slotName + '.sav';
  if not FileExistsOS(path) then begin err := 'no such save: ' + path; Exit; end;
  Assign(f, path);
  try
    Reset(f);
    Readln(f, magic);
    if magic <> SAVE_MAGIC then begin Bad('bad magic'); Close(f); Exit; end;
    Readln(f, line);
    if not ParseIntStrict(line, ver) then begin Bad('bad version'); Close(f); Exit; end;
    if ver > SAVE_VERSION then begin Bad('newer save version ' + I2S(ver)); Close(f); Exit; end;
    // v1 only; migration path: none needed yet
    Readln(f, crcStr);
    payload := '';
    while not Eof(f) do
    begin
      Readln(f, line);
      payload := payload + line + #10;
    end;
    Close(f);
  except
    on E: Exception do begin err := 'read error: ' + E.Message; Exit; end;
  end;
  crc := CRC32OfStr(payload);
  if Lower(IntToHex(crc, 8)) <> Lower(crcStr) then begin Bad('CRC mismatch (tampered or corrupt)'); Exit; end;
  lines := Split(payload, #10);
  // parse
  p := Default(TPlayer);
  if not NeedKey('name', v) then Exit; p.name := v;
  if not NeedKey('race', v) then Exit; p.raceId := v;
  if not NeedKey('class', v) then Exit; p.classId := v;
  v := ''; NeedKey('hardcore', v); p.hardcore := v = 'True';
  if not NeedKey('attrs', v) then Exit;
  ap := Split(v, ',');
  if Length(ap) <> 5 then begin Bad('attrs count'); Exit; end;
  for i := 0 to 4 do ParseIntStrict(ap[i], p.attrs[i]);
  v := ''; NeedKey('level', v); ParseIntStrict(v, p.level);
  v := ''; NeedKey('xp', v); ParseIntStrict(v, p.xp);
  v := ''; NeedKey('attrPoints', v); ParseIntStrict(v, p.attrPoints);
  v := ''; NeedKey('skillPoints', v); ParseIntStrict(v, p.skillPoints);
  v := ''; NeedKey('gold', v); ParseIntStrict(v, p.gold);
  v := ''; NeedKey('hp', v); ParseFloatStrict(v, p.hp);
  v := ''; NeedKey('mana', v); ParseFloatStrict(v, p.mana);
  v := ''; NeedKey('stamina', v); ParseFloatStrict(v, p.stamina);
  v := ''; NeedKey('x', v); ParseFloatStrict(v, p.x);
  v := ''; NeedKey('y', v); ParseFloatStrict(v, p.y);
  v := ''; NeedKey('map', v); p.mapId := v;
  v := ''; NeedKey('deaths', v); ParseIntStrict(v, p.deaths);
  v := ''; NeedKey('day', v); ParseIntStrict(v, p.day);
  v := ''; NeedKey('rng', v); p.rngSeed := StrToInt64Def(v, 1);
  p.flags.n := 0;
  for i := 0 to High(lines) do
    if StartsWith(lines[i], 'flag=') then
    begin
      rest := Copy(lines[i], 6, Length(lines[i]));
      eq := Pos('=', rest);
      k2 := Copy(rest, 1, eq - 1); v2 := Copy(rest, eq + 1, Length(rest));
      FlagSet(p.flags, k2, v2);
    end;
  for i := 0 to SLOT_COUNT - 1 do
  begin
    p.gear[i].base := '';
    p.gear[i].slot := SLOTS[i];
  end;
  for i := 0 to High(lines) do
    if StartsWith(lines[i], 'gear=') then
    begin
      parts := Split(Copy(lines[i], 6, Length(lines[i])), ';');
      if Length(parts) <> 13 then begin Bad('gear fields'); Exit; end;
      // find slot index
      gi := -1;
      for s := 0 to SLOT_COUNT - 1 do
        if SLOTS[s] = parts[3] then gi := s;
      if gi < 0 then gi := 0;
      with p.gear[gi] do
      begin
        base := parts[0]; uid := parts[1]; name := parts[2]; slot := parts[3];
        ParseIntStrict(parts[4], rarity);
        aff1 := parts[5]; aff2 := parts[6];
        ParseFloatStrict(parts[7], val1); ParseFloatStrict(parts[8], val2);
        stats := parts[9];
        ParseIntStrict(parts[10], price); ParseIntStrict(parts[11], lvl);
        seed := StrToInt64Def(parts[12], 1);
      end;
    end;
  p.inv := nil;
  for i := 0 to High(lines) do
    if StartsWith(lines[i], 'inv=') then
    begin
      parts := Split(Copy(lines[i], 5, Length(lines[i])), ';');
      if Length(parts) <> 13 then begin Bad('inv fields'); Exit; end;
      SetLength(p.inv, Length(p.inv) + 1);
      with p.inv[High(p.inv)] do
      begin
        base := parts[0]; uid := parts[1]; name := parts[2]; slot := parts[3];
        ParseIntStrict(parts[4], rarity);
        aff1 := parts[5]; aff2 := parts[6];
        ParseFloatStrict(parts[7], val1); ParseFloatStrict(parts[8], val2);
        stats := parts[9];
        ParseIntStrict(parts[10], price); ParseIntStrict(parts[11], lvl);
        seed := StrToInt64Def(parts[12], 1);
      end;
    end;
  v := ''; NeedKey('qb', v); qp := Split(v, '|');
  for i := 0 to QUICK_SLOTS - 1 do
    if i <= High(qp) then p.quickbar[i] := qp[i] else p.quickbar[i] := '';
  v := ''; NeedKey('spells', v); p.spells := Split(v, '|');
  v := ''; NeedKey('skills', v); p.skills := Split(v, '|');
  p.quests := nil;
  for i := 0 to High(lines) do
    if StartsWith(lines[i], 'quest=') then
    begin
      parts := Split(Copy(lines[i], 7, Length(lines[i])), '|');
      if Length(parts) <> 3 then begin Bad('quest fields'); Exit; end;
      SetLength(p.quests, Length(p.quests) + 1);
      p.quests[High(p.quests)].id := parts[0];
      p.quests[High(p.quests)].state := parts[1];
      op := Split(parts[2], ',');
      SetLength(p.quests[High(p.quests)].obj, Length(op));
      for k := 0 to High(op) do
        ParseIntStrict(op[k], p.quests[High(p.quests)].obj[k]);
    end;
  v := ''; NeedKey('lore', v); p.lore := Split(v, '|');
  p.kills := nil;
  for i := 0 to High(lines) do
    if StartsWith(lines[i], 'kill=') then
    begin
      parts := Split(Copy(lines[i], 6, Length(lines[i])), '|');
      SetLength(p.kills, Length(p.kills) + 1);
      p.kills[High(p.kills)].mid := parts[0];
      ParseIntStrict(parts[1], p.kills[High(p.kills)].n);
    end;
  v := ''; NeedKey('corpse', v);
  cp := Split(v, '|');
  if Length(cp) = 5 then
  begin
    p.corpseMap := cp[0];
    ParseFloatStrict(cp[1], p.corpseX);
    ParseFloatStrict(cp[2], p.corpseY);
    ParseIntStrict(cp[3], p.lostXP);
    p.corpseLooted := cp[4] = 'True';
  end;
  SeedRNG(p.rngSeed);
  RecalcStats(p);
  Result := True;
end;

function SaveSlots: TStrArray;
var
  sr: TSearchRec;
begin
  Result := nil;
  if FindFirst('saves/*.sav', faAnyFile, sr) = 0 then
  begin
    repeat
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Copy(sr.Name, 1, Pos('.', sr.Name) - 1);
    until FindNext(sr) <> 0;
    FindClose(sr);
  end;
end;

end.
