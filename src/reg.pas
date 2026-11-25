unit reg;
{$mode objfpc}{$H+}
{ Typed registries loaded from data/*.dat. Adding a monster/spell/item/quest
  = adding a section in a data file; no code changes. }
interface

uses core, data;

const
  RARITY_NAMES: array[0..5] of string = ('Grå', 'Fine', 'Superior', 'Enchanted', 'Relic', 'Mythforged');
  RARITY_AFFIX_COUNT: array[0..5] of Integer = (0, 1, 1, 2, 2, 2);
  SLOTS: array[0..9] of string = ('weapon', 'offhand', 'head', 'body', 'hands', 'legs', 'feet', 'ring1', 'ring2', 'amulet');
  SLOT_COUNT = 10;
  ATTR_NAMES: array[0..4] of string = ('might', 'wits', 'grace', 'spirit', 'resolve');
  ATTR_LABEL: array[0..4] of string = ('Might', 'Wits', 'Grace', 'Spirit', 'Resolve');

type
  TStatDef = record id, name, kind, formula: string; end;
  TElement = record id, name, beats: string; hex: LongWord; end;
  TRace = record id, name, desc: string; resists: TStrArray; flags: TStrArray; end;
  TClassDef = record id, name, desc: string; startKit: TStrArray; seedSkills: TStrArray; manaMul, hpMul, stamMul: Single; end;
  TSkillEffect = record kind, a1, a2: string; num: Single; end;
  TSkill = record id, tree, name, desc: string; tier, cost: Integer; requires: string; effects: array of TSkillEffect; end;
  TSpell = record id, school, name, desc, kind, element: string; mana, cd, dmg, range, radius, projSpeed: Single; lvl: Integer; end;
  TMonster = record
    id, name, behavior, element, dropTable: string;
    hp, dmg, speed, xp, goldMin, goldMax, aggroRange, attackRange, windup, size, scale, armor: Single;
    abilities: TStrArray;
    boss: Boolean;
  end;
  TAffix = record id, name, stat: string; minv, maxv: Single; end;
  TAffixRef = record id: string; weight: Integer; end;
  TAffixPool = record rarity: Integer; refs: array of TAffixRef; end;
  TItemBase = record id, name, slot, stats, icon: string; price, lvl: Integer; twoHand: Boolean; end;
  TUnique = record id, name, slot, lore, source, stats: string; price, lvl, rarity: Integer; end;
  TDropEntry = record itemId: string; chance: Single; minLvl, maxLvl, count: Integer; isUnique: Boolean; end;
  TDropTable = record id: string; entries: array of TDropEntry; end;
  TNpc = record id, name, title, faction, map: string; x, y: Single; essential: Boolean; end;
  TDialogLine = record cond, text, gotoSec: string; choices: TStrArray; end;
  TObjective = record kind, target: string; count: Integer; end;
  TQuest = record
    id, title, act, giver, region, desc: string;
    objectives: array of TObjective;
    reqFlags: TStrArray;
    failIf: string;
    rewardXP, rewardGold: Integer;
    rewardItems: TStrArray;
    onComplete: TStrArray;
    unlocks: TStrArray;
    repeatable: Boolean;
  end;
  TRule = record id, on, ifKey, ifVal: string; thenList: TStrArray; end;
  TLore = record id, title, text, map, contradicts: string; hidden: Boolean; end;
  TStoreStock = record itemId: string; qty, minTrust: Integer; end;
  TStore = record id, name, npc, map: string; stock: array of TStoreStock; end;
  TRegion = record id, name, biome, desc, hubMap: string; maps: TStrArray; act: Integer; end;
  TBuild = record id, name, classId: string; nodes: TStrArray; end;

var
  GDB: TDataDB;
  GStats: array of TStatDef;
  GElements: array of TElement;
  GRaces: array of TRace;
  GClasses: array of TClassDef;
  GSkills: array of TSkill;
  GSpells: array of TSpell;
  GMonsters: array of TMonster;
  GAffixes: array of TAffix;
  GPools: array of TAffixPool;
  GItems: array of TItemBase;
  GUniques: array of TUnique;
  GDropTables: array of TDropTable;
  GNpcs: array of TNpc;
  GQuests: array of TQuest;
  GRules: array of TRule;
  GLore: array of TLore;
  GStores: array of TStore;
  GRegions: array of TRegion;
  GBuilds: array of TBuild;

procedure LoadAllData;   // loads data/*.dat into GDB + registries; FATAL on any problem
procedure LoadMonstersFrom(const path: string);  // public so selftest can prove data-only adds
procedure LoadSpellsFrom(const path: string);

{ finders — return index or -1 }
function FindStat(const id: string): Integer;
function FindElement(const id: string): Integer;
function FindRace(const id: string): Integer;
function FindClass(const id: string): Integer;
function FindSkill(const id: string): Integer;
function FindSpell(const id: string): Integer;
function FindMonster(const id: string): Integer;
function FindAffix(const id: string): Integer;
function FindItem(const id: string): Integer;
function FindUnique(const id: string): Integer;
function FindDropTable(const id: string): Integer;
function FindNpc(const id: string): Integer;
function FindQuest(const id: string): Integer;
function FindStore(const id: string): Integer;
function FindRegion(const id: string): Integer;
function FindBuild(const id: string): Integer;

implementation

uses SysUtils;

const
  F_STATS = 'data/stats.dat';
  F_ELEMENTS = 'data/elements.dat';
  F_RACES = 'data/races.dat';
  F_CLASSES = 'data/classes.dat';
  F_SKILLS = 'data/skills.dat';
  F_SPELLS = 'data/spells.dat';
  F_MONSTERS = 'data/monsters.dat';
  F_AFFIXES = 'data/affixes.dat';
  F_ITEMS = 'data/items.dat';
  F_UNIQUES = 'data/uniques.dat';
  F_DROPS = 'data/drops.dat';
  F_NPCS = 'data/npcs.dat';
  F_DIALOG = 'data/dialog.dat';
  F_QUESTS = 'data/quests.dat';
  F_QUESTS2 = 'data/quests_side.dat';
  F_RULES = 'data/rules.dat';
  F_LORE = 'data/lore.dat';
  F_STORES = 'data/stores.dat';
  F_REGIONS = 'data/regions.dat';
  F_BUILDS = 'data/builds.dat';

procedure LoadMonstersFrom(const path: string);
var
  ids: TStrArray;
  i: Integer;
  sec: string;
begin
  ids := DataList(GDB, path, 'monster');
  for i := 0 to High(ids) do
  begin
    sec := 'monster:' + ids[i];
    SetLength(GMonsters, Length(GMonsters) + 1);
    with GMonsters[High(GMonsters)] do
    begin
      id := ids[i];
      name := DataGet(GDB, path, sec, 'name');
      behavior := DataGetDef(GDB, path, sec, 'behavior', 'melee');
      element := DataGetDef(GDB, path, sec, 'element', 'raw');
      hp := DataGetF(GDB, path, sec, 'hp');
      dmg := DataGetF(GDB, path, sec, 'dmg');
      speed := DataGetFDef(GDB, path, sec, 'speed', 2.2);
      xp := DataGetFDef(GDB, path, sec, 'xp', 10);
      goldMin := DataGetFDef(GDB, path, sec, 'gold_min', 0);
      goldMax := DataGetFDef(GDB, path, sec, 'gold_max', 0);
      aggroRange := DataGetFDef(GDB, path, sec, 'aggro', 7);
      attackRange := DataGetFDef(GDB, path, sec, 'attack_range', 1.4);
      windup := DataGetFDef(GDB, path, sec, 'windup', 0.7);
      size := DataGetFDef(GDB, path, sec, 'size', 0.5);
      scale := DataGetFDef(GDB, path, sec, 'scale', 1.0);
      armor := DataGetFDef(GDB, path, sec, 'armor', 0);
      abilities := DataGetListDef(GDB, path, sec, 'abilities', '');
      dropTable := DataGetDef(GDB, path, sec, 'drops', '');
      boss := DataGetBDef(GDB, path, sec, 'boss', False);
    end;
  end;
end;

procedure LoadSpellsFrom(const path: string);
var
  ids: TStrArray;
  i: Integer;
  sec: string;
begin
  ids := DataList(GDB, path, 'spell');
  for i := 0 to High(ids) do
  begin
    sec := 'spell:' + ids[i];
    SetLength(GSpells, Length(GSpells) + 1);
    with GSpells[High(GSpells)] do
    begin
      id := ids[i];
      school := DataGet(GDB, path, sec, 'school');
      name := DataGet(GDB, path, sec, 'name');
      desc := DataGetDef(GDB, path, sec, 'desc', '');
      kind := DataGetDef(GDB, path, sec, 'kind', 'bolt');
      element := DataGetDef(GDB, path, sec, 'element', 'raw');
      mana := DataGetF(GDB, path, sec, 'mana');
      cd := DataGetFDef(GDB, path, sec, 'cd', 0);
      dmg := DataGetFDef(GDB, path, sec, 'dmg', 0);
      range := DataGetFDef(GDB, path, sec, 'range', 6);
      radius := DataGetFDef(GDB, path, sec, 'radius', 0);
      projSpeed := DataGetFDef(GDB, path, sec, 'proj_speed', 12);
      lvl := DataGetIDef(GDB, path, sec, 'lvl', 1);
    end;
  end;
end;

procedure LoadQuestsFrom(const path: string);
var
  sp: TStrArray;
  ids: TStrArray;
  i, j: Integer;
  sec: string;
  parts: TStrArray;
begin
  ids := DataList(GDB, path, 'quest');
  for i := 0 to High(ids) do
  begin
    sec := 'quest:' + ids[i];
    SetLength(GQuests, Length(GQuests) + 1);
    with GQuests[High(GQuests)] do
    begin
      id := ids[i];
      title := DataGet(GDB, path, sec, 'title');
      act := DataGetDef(GDB, path, sec, 'act', '1');
      giver := DataGetDef(GDB, path, sec, 'giver', '');
      region := DataGetDef(GDB, path, sec, 'region', '');
      desc := DataGetDef(GDB, path, sec, 'desc', '');
      objectives := nil;
      parts := DataGetListDef(GDB, path, sec, 'objectives', '');
      for j := 0 to High(parts) do
      begin
        SetLength(objectives, Length(objectives) + 1);
        with objectives[High(objectives)] do
        begin
          sp := Split(parts[j], ':');
          if Length(sp) < 2 then FatalF('%s [%s] bad objective: %s', [path, sec, parts[j]]);
          kind := sp[0];
          target := sp[1];
          count := 1;
          if Length(sp) > 2 then
            if not ParseIntStrict(sp[2], count) then FatalF('%s [%s] bad count: %s', [path, sec, parts[j]]);
        end;
      end;
      reqFlags := DataGetListDef(GDB, path, sec, 'requires', '');
      failIf := DataGetDef(GDB, path, sec, 'fail_if', '');
      rewardXP := DataGetIDef(GDB, path, sec, 'reward_xp', 0);
      rewardGold := DataGetIDef(GDB, path, sec, 'reward_gold', 0);
      rewardItems := DataGetListDef(GDB, path, sec, 'reward_items', '');
      onComplete := DataGetListDef(GDB, path, sec, 'on_complete', '');
      unlocks := DataGetListDef(GDB, path, sec, 'unlocks', '');
      repeatable := DataGetBDef(GDB, path, sec, 'repeatable', False);
    end;
  end;
end;

procedure LoadAllData;
var
  raw: string;
  sp: TStrArray;
  ids: TStrArray;
  i, j: Integer;
  sec: string;
  parts: TStrArray;
begin
  GDB.files := nil;
  DataLoad(GDB, F_STATS);
  DataLoad(GDB, F_ELEMENTS);
  DataLoad(GDB, F_RACES);
  DataLoad(GDB, F_CLASSES);
  DataLoad(GDB, F_SKILLS);
  DataLoad(GDB, F_SPELLS);
  DataLoad(GDB, F_MONSTERS);
  DataLoad(GDB, F_AFFIXES);
  DataLoad(GDB, F_ITEMS);
  DataLoad(GDB, F_UNIQUES);
  DataLoad(GDB, F_DROPS);
  DataLoad(GDB, F_NPCS);
  DataLoad(GDB, F_DIALOG);
  DataLoad(GDB, F_QUESTS);
  DataLoad(GDB, F_QUESTS2);
  DataLoad(GDB, F_RULES);
  DataLoad(GDB, F_LORE);
  DataLoad(GDB, F_STORES);
  DataLoad(GDB, F_REGIONS);
  DataLoad(GDB, F_BUILDS);

  // stats
  ids := DataList(GDB, F_STATS, 'stat');
  for i := 0 to High(ids) do
  begin
    sec := 'stat:' + ids[i];
    SetLength(GStats, Length(GStats) + 1);
    with GStats[High(GStats)] do
    begin
      id := ids[i];
      name := DataGet(GDB, F_STATS, sec, 'name');
      kind := DataGet(GDB, F_STATS, sec, 'kind');       // 'derived' | 'flat'
      formula := DataGetDef(GDB, F_STATS, sec, 'formula', '');
      if (kind <> 'derived') and (kind <> 'flat') then
        FatalF('stats.dat [%s]: kind must be derived|flat', [sec]);
      if (kind = 'derived') and (formula = '') then
        FatalF('stats.dat [%s]: derived stat needs formula', [sec]);
    end;
  end;

  // elements
  ids := DataList(GDB, F_ELEMENTS, 'element');
  for i := 0 to High(ids) do
  begin
    sec := 'element:' + ids[i];
    SetLength(GElements, Length(GElements) + 1);
    with GElements[High(GElements)] do
    begin
      id := ids[i];
      name := DataGet(GDB, F_ELEMENTS, sec, 'name');
      beats := DataGetDef(GDB, F_ELEMENTS, sec, 'beats', '');
      hex := StrToIntDef(DataGet(GDB, F_ELEMENTS, sec, 'hex'), 0);
    end;
  end;

  // races
  ids := DataList(GDB, F_RACES, 'race');
  for i := 0 to High(ids) do
  begin
    sec := 'race:' + ids[i];
    SetLength(GRaces, Length(GRaces) + 1);
    with GRaces[High(GRaces)] do
    begin
      id := ids[i];
      name := DataGet(GDB, F_RACES, sec, 'name');
      desc := DataGet(GDB, F_RACES, sec, 'desc');
      resists := DataGetListDef(GDB, F_RACES, sec, 'resists', '');
      flags := DataGetListDef(GDB, F_RACES, sec, 'flags', '');
    end;
  end;

  // classes
  ids := DataList(GDB, F_CLASSES, 'class');
  for i := 0 to High(ids) do
  begin
    sec := 'class:' + ids[i];
    SetLength(GClasses, Length(GClasses) + 1);
    with GClasses[High(GClasses)] do
    begin
      id := ids[i];
      name := DataGet(GDB, F_CLASSES, sec, 'name');
      desc := DataGet(GDB, F_CLASSES, sec, 'desc');
      startKit := DataGetListDef(GDB, F_CLASSES, sec, 'start_kit', '');
      seedSkills := DataGetListDef(GDB, F_CLASSES, sec, 'seed_skills', '');
      manaMul := DataGetFDef(GDB, F_CLASSES, sec, 'mana_mul', 1.0);
      hpMul := DataGetFDef(GDB, F_CLASSES, sec, 'hp_mul', 1.0);
      stamMul := DataGetFDef(GDB, F_CLASSES, sec, 'stam_mul', 1.0);
    end;
  end;

  // skills
  ids := DataList(GDB, F_SKILLS, 'skill');
  for i := 0 to High(ids) do
  begin
    sec := 'skill:' + ids[i];
    SetLength(GSkills, Length(GSkills) + 1);
    with GSkills[High(GSkills)] do
    begin
      id := ids[i];
      tree := DataGet(GDB, F_SKILLS, sec, 'tree');
      name := DataGet(GDB, F_SKILLS, sec, 'name');
      desc := DataGetDef(GDB, F_SKILLS, sec, 'desc', '');
      tier := DataGetI(GDB, F_SKILLS, sec, 'tier');
      cost := DataGetIDef(GDB, F_SKILLS, sec, 'cost', 1);
      requires := DataGetDef(GDB, F_SKILLS, sec, 'requires', '');
      effects := nil;
      parts := DataGetListDef(GDB, F_SKILLS, sec, 'effects', '');
      for j := 0 to High(parts) do
      begin
        // effect token: kind:arg1:arg2[:num]
        sp := Split(parts[j], ':');
        if Length(sp) < 1 then FatalF('skills.dat [%s] bad effect: %s', [sec, parts[j]]);
        if Length(sp) > 4 then FatalF('skills.dat [%s] too many effect fields: %s', [sec, parts[j]]);
        SetLength(effects, Length(effects) + 1);
        with effects[High(effects)] do
        begin
          kind := sp[0];
          a1 := ''; a2 := ''; num := 0;
          if Length(sp) > 1 then a1 := sp[1];
          if Length(sp) > 2 then a2 := sp[2];
          if Length(sp) > 3 then
            if not ParseFloatStrict(sp[3], num) then FatalF('skills.dat [%s] bad effect num: %s', [sec, parts[j]]);
        end;
      end;
    end;
  end;

  // spells + monsters (via reusable loaders so selftest can prove data-only adds)
  LoadSpellsFrom(F_SPELLS);
  LoadMonstersFrom(F_MONSTERS);

  // affixes: [affix:id] defs + [pool:rarity] refs
  ids := DataList(GDB, F_AFFIXES, 'affix');
  for i := 0 to High(ids) do
  begin
    sec := 'affix:' + ids[i];
    SetLength(GAffixes, Length(GAffixes) + 1);
    with GAffixes[High(GAffixes)] do
    begin
      id := ids[i];
      name := DataGet(GDB, F_AFFIXES, sec, 'name');
      stat := DataGet(GDB, F_AFFIXES, sec, 'stat');
      minv := DataGetF(GDB, F_AFFIXES, sec, 'min');
      maxv := DataGetF(GDB, F_AFFIXES, sec, 'max');
      if (FindStat(stat) < 0) and not ((stat = 'might') or (stat = 'wits') or (stat = 'grace') or (stat = 'spirit') or (stat = 'resolve')) then
        FatalF('affixes.dat [%s]: unknown stat %s', [sec, stat]);
    end;
  end;
  ids := DataList(GDB, F_AFFIXES, 'pool');
  for i := 0 to High(ids) do
  begin
    sec := 'pool:' + ids[i];
    SetLength(GPools, Length(GPools) + 1);
    with GPools[High(GPools)] do
    begin
      if not ParseIntStrict(ids[i], rarity) then FatalF('affixes.dat [%s]: bad rarity', [sec]);
      refs := nil;
      parts := DataGetListDef(GDB, F_AFFIXES, sec, 'affixes', '');
      for j := 0 to High(parts) do
      begin
        // token: affixId:weight
        SetLength(refs, Length(refs) + 1);
        with refs[High(refs)] do
        begin
          sp := Split(parts[j], ':');
          if Length(sp) <> 2 then FatalF('affixes.dat [%s] bad ref: %s', [sec, parts[j]]);
          id := sp[0];
          if not ParseIntStrict(sp[1], weight) then FatalF('affixes.dat [%s] bad weight: %s', [sec, parts[j]]);
          if FindAffix(id) < 0 then FatalF('affixes.dat [%s]: unknown affix %s', [sec, id]);
        end;
      end;
    end;
  end;

  // items
  ids := DataList(GDB, F_ITEMS, 'item');
  for i := 0 to High(ids) do
  begin
    sec := 'item:' + ids[i];
    SetLength(GItems, Length(GItems) + 1);
    with GItems[High(GItems)] do
    begin
      id := ids[i];
      name := DataGet(GDB, F_ITEMS, sec, 'name');
      slot := DataGet(GDB, F_ITEMS, sec, 'slot');
      stats := DataGetDef(GDB, F_ITEMS, sec, 'stats', '');
      icon := DataGetDef(GDB, F_ITEMS, sec, 'icon', slot);
      price := DataGetI(GDB, F_ITEMS, sec, 'price');
      lvl := DataGetIDef(GDB, F_ITEMS, sec, 'lvl', 1);
      twoHand := DataGetBDef(GDB, F_ITEMS, sec, 'twohand', False);
    end;
  end;

  // uniques
  ids := DataList(GDB, F_UNIQUES, 'unique');
  for i := 0 to High(ids) do
  begin
    sec := 'unique:' + ids[i];
    SetLength(GUniques, Length(GUniques) + 1);
    with GUniques[High(GUniques)] do
    begin
      id := ids[i];
      name := DataGet(GDB, F_UNIQUES, sec, 'name');
      slot := DataGet(GDB, F_UNIQUES, sec, 'slot');
      lore := DataGetDef(GDB, F_UNIQUES, sec, 'lore', '');
      source := DataGetDef(GDB, F_UNIQUES, sec, 'source', '');
      stats := DataGetDef(GDB, F_UNIQUES, sec, 'stats', '');
      price := DataGetIDef(GDB, F_UNIQUES, sec, 'price', 100);
      lvl := DataGetIDef(GDB, F_UNIQUES, sec, 'lvl', 1);
      rarity := DataGetIDef(GDB, F_UNIQUES, sec, 'rarity', 4);
    end;
  end;

  // drop tables
  ids := DataList(GDB, F_DROPS, 'table');
  for i := 0 to High(ids) do
  begin
    sec := 'table:' + ids[i];
    SetLength(GDropTables, Length(GDropTables) + 1);
    with GDropTables[High(GDropTables)] do
    begin
      id := ids[i];
      entries := nil;
      parts := DataGetListDef(GDB, F_DROPS, sec, 'entries', '');
      for j := 0 to High(parts) do
      begin
        // token: itemId:chance:minLvl:maxLvl:count   (prefix u: for unique)
        SetLength(entries, Length(entries) + 1);
        with entries[High(entries)] do
        begin
          isUnique := StartsWith(parts[j], 'u:');
          if isUnique then raw := Copy(parts[j], 3, Length(parts[j])) else raw := parts[j];
          sp := Split(raw, ':');
          if Length(sp) <> 5 then FatalF('drops.dat [%s] bad entry: %s', [sec, parts[j]]);
          itemId := sp[0];
          if not ParseFloatStrict(sp[1], chance) then FatalF('drops.dat [%s] bad chance: %s', [sec, parts[j]]);
          if not ParseIntStrict(sp[2], minLvl) then FatalF('drops.dat [%s] bad minLvl: %s', [sec, parts[j]]);
          if not ParseIntStrict(sp[3], maxLvl) then FatalF('drops.dat [%s] bad maxLvl: %s', [sec, parts[j]]);
          if not ParseIntStrict(sp[4], count) then FatalF('drops.dat [%s] bad count: %s', [sec, parts[j]]);
          if itemId <> 'gold' then
          begin
            if isUnique and (FindUnique(itemId) < 0) then FatalF('drops.dat [%s]: unknown unique %s', [sec, itemId]);
            if (not isUnique) and (FindItem(itemId) < 0) then FatalF('drops.dat [%s]: unknown item %s', [sec, itemId]);
          end;
        end;
      end;
    end;
  end;

  // npcs
  ids := DataList(GDB, F_NPCS, 'npc');
  for i := 0 to High(ids) do
  begin
    sec := 'npc:' + ids[i];
    SetLength(GNpcs, Length(GNpcs) + 1);
    with GNpcs[High(GNpcs)] do
    begin
      id := ids[i];
      name := DataGet(GDB, F_NPCS, sec, 'name');
      title := DataGetDef(GDB, F_NPCS, sec, 'title', '');
      faction := DataGetDef(GDB, F_NPCS, sec, 'faction', '');
      map := DataGetDef(GDB, F_NPCS, sec, 'map', '');
      x := DataGetFDef(GDB, F_NPCS, sec, 'x', -1);
      y := DataGetFDef(GDB, F_NPCS, sec, 'y', -1);
      essential := DataGetBDef(GDB, F_NPCS, sec, 'essential', True);
    end;
  end;

  // quests (main + side files)
  LoadQuestsFrom(F_QUESTS);
  LoadQuestsFrom(F_QUESTS2);

  // rules: consequence engine. [rule:id] on=quest:qid|act:n|flag:key  if=key==val (optional)  then=set:key=val|...
  ids := DataList(GDB, F_RULES, 'rule');
  for i := 0 to High(ids) do
  begin
    sec := 'rule:' + ids[i];
    SetLength(GRules, Length(GRules) + 1);
    with GRules[High(GRules)] do
    begin
      id := ids[i];
      on := DataGet(GDB, F_RULES, sec, 'on');
      ifKey := ''; ifVal := '';
      if DataHas(GDB, F_RULES, sec, 'if') then
      begin
        parts := SplitStr(DataGet(GDB, F_RULES, sec, 'if'), '==');
        if Length(parts) <> 2 then FatalF('rules.dat [%s]: if must be key==val', [sec]);
        ifKey := parts[0]; ifVal := parts[1];
      end;
      thenList := DataGetListDef(GDB, F_RULES, sec, 'then', '');
    end;
  end;

  // lore
  ids := DataList(GDB, F_LORE, 'doc');
  for i := 0 to High(ids) do
  begin
    sec := 'doc:' + ids[i];
    SetLength(GLore, Length(GLore) + 1);
    with GLore[High(GLore)] do
    begin
      id := ids[i];
      title := DataGet(GDB, F_LORE, sec, 'title');
      text := DataGet(GDB, F_LORE, sec, 'text');
      map := DataGetDef(GDB, F_LORE, sec, 'map', '');
      contradicts := DataGetDef(GDB, F_LORE, sec, 'contradicts', '');
      hidden := DataGetBDef(GDB, F_LORE, sec, 'hidden', False);
    end;
  end;

  // stores
  ids := DataList(GDB, F_STORES, 'store');
  for i := 0 to High(ids) do
  begin
    sec := 'store:' + ids[i];
    SetLength(GStores, Length(GStores) + 1);
    with GStores[High(GStores)] do
    begin
      id := ids[i];
      name := DataGet(GDB, F_STORES, sec, 'name');
      npc := DataGetDef(GDB, F_STORES, sec, 'npc', '');
      map := DataGetDef(GDB, F_STORES, sec, 'map', '');
      stock := nil;
      parts := DataGetListDef(GDB, F_STORES, sec, 'stock', '');
      for j := 0 to High(parts) do
      begin
        // token: itemId:qty:minTrust
        SetLength(stock, Length(stock) + 1);
        with stock[High(stock)] do
        begin
          sp := Split(parts[j], ':');
          if Length(sp) < 2 then FatalF('stores.dat [%s] bad stock: %s', [sec, parts[j]]);
          itemId := sp[0];
          if not ParseIntStrict(sp[1], qty) then FatalF('stores.dat [%s] bad qty: %s', [sec, parts[j]]);
          if Length(sp) > 2 then
          begin
            if not ParseIntStrict(sp[2], minTrust) then FatalF('stores.dat [%s] bad minTrust: %s', [sec, parts[j]]);
          end
          else minTrust := 0;
        end;
      end;
    end;
  end;

  // regions
  ids := DataList(GDB, F_REGIONS, 'region');
  for i := 0 to High(ids) do
  begin
    sec := 'region:' + ids[i];
    SetLength(GRegions, Length(GRegions) + 1);
    with GRegions[High(GRegions)] do
    begin
      id := ids[i];
      name := DataGet(GDB, F_REGIONS, sec, 'name');
      biome := DataGet(GDB, F_REGIONS, sec, 'biome');
      desc := DataGetDef(GDB, F_REGIONS, sec, 'desc', '');
      hubMap := DataGetDef(GDB, F_REGIONS, sec, 'hub_map', '');
      maps := DataGetListDef(GDB, F_REGIONS, sec, 'maps', '');
      if not ParseIntStrict(DataGetDef(GDB, F_REGIONS, sec, 'act', '1'), act) then
        FatalF('regions.dat [%s]: bad act', [sec]);
    end;
  end;

  // builds (selftest build-path simulation)
  ids := DataList(GDB, F_BUILDS, 'build');
  for i := 0 to High(ids) do
  begin
    sec := 'build:' + ids[i];
    SetLength(GBuilds, Length(GBuilds) + 1);
    with GBuilds[High(GBuilds)] do
    begin
      id := ids[i];
      name := DataGet(GDB, F_BUILDS, sec, 'name');
      classId := DataGet(GDB, F_BUILDS, sec, 'class');
      nodes := DataGetList(GDB, F_BUILDS, sec, 'nodes');
    end;
  end;

  Log(Format('data loaded: %d stats, %d elements, %d races, %d classes, %d skills, %d spells, %d monsters, %d affixes, %d pools, %d items, %d uniques, %d tables, %d npcs, %d quests, %d rules, %d lore, %d stores, %d regions, %d builds',
    [Length(GStats), Length(GElements), Length(GRaces), Length(GClasses), Length(GSkills),
     Length(GSpells), Length(GMonsters), Length(GAffixes), Length(GPools), Length(GItems),
     Length(GUniques), Length(GDropTables), Length(GNpcs), Length(GQuests), Length(GRules),
     Length(GLore), Length(GStores), Length(GRegions), Length(GBuilds)]));
end;

{ generic finders }
function FindStat(const id: string): Integer;
var i: Integer; begin for i := 0 to High(GStats) do if GStats[i].id = id then Exit(i); Result := -1; end;
function FindElement(const id: string): Integer;
var i: Integer; begin for i := 0 to High(GElements) do if GElements[i].id = id then Exit(i); Result := -1; end;
function FindRace(const id: string): Integer;
var i: Integer; begin for i := 0 to High(GRaces) do if GRaces[i].id = id then Exit(i); Result := -1; end;
function FindClass(const id: string): Integer;
var i: Integer; begin for i := 0 to High(GClasses) do if GClasses[i].id = id then Exit(i); Result := -1; end;
function FindSkill(const id: string): Integer;
var i: Integer; begin for i := 0 to High(GSkills) do if GSkills[i].id = id then Exit(i); Result := -1; end;
function FindSpell(const id: string): Integer;
var i: Integer; begin for i := 0 to High(GSpells) do if GSpells[i].id = id then Exit(i); Result := -1; end;
function FindMonster(const id: string): Integer;
var i: Integer; begin for i := 0 to High(GMonsters) do if GMonsters[i].id = id then Exit(i); Result := -1; end;
function FindAffix(const id: string): Integer;
var i: Integer; begin for i := 0 to High(GAffixes) do if GAffixes[i].id = id then Exit(i); Result := -1; end;
function FindItem(const id: string): Integer;
var i: Integer; begin for i := 0 to High(GItems) do if GItems[i].id = id then Exit(i); Result := -1; end;
function FindUnique(const id: string): Integer;
var i: Integer; begin for i := 0 to High(GUniques) do if GUniques[i].id = id then Exit(i); Result := -1; end;
function FindDropTable(const id: string): Integer;
var i: Integer; begin for i := 0 to High(GDropTables) do if GDropTables[i].id = id then Exit(i); Result := -1; end;
function FindNpc(const id: string): Integer;
var i: Integer; begin for i := 0 to High(GNpcs) do if GNpcs[i].id = id then Exit(i); Result := -1; end;
function FindQuest(const id: string): Integer;
var i: Integer; begin for i := 0 to High(GQuests) do if GQuests[i].id = id then Exit(i); Result := -1; end;
function FindStore(const id: string): Integer;
var i: Integer; begin for i := 0 to High(GStores) do if GStores[i].id = id then Exit(i); Result := -1; end;
function FindRegion(const id: string): Integer;
var i: Integer; begin for i := 0 to High(GRegions) do if GRegions[i].id = id then Exit(i); Result := -1; end;
function FindBuild(const id: string): Integer;
var i: Integer; begin for i := 0 to High(GBuilds) do if GBuilds[i].id = id then Exit(i); Result := -1; end;

end.
