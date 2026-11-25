unit selftest;
{$mode objfpc}{$H+}
{ Headless selftest suite (brief 5.4). Run: plamen selftest -> RC 0 = all pass.
  Covers: data registries, stat formulas, loot tables, quest consequence chains
  (act1 choice -> act4 outcome), store price/trust rules, save/load round-trip +
  corruption detection, build-path simulation, data-only monster/spell add. }
interface

function RunSelftest: Integer;

implementation

uses SysUtils, core, data, reg, sim;

var
  gPass, gFail: Integer;
  gLog: string;

procedure TLog(const s: string);
begin
  gLog := gLog + s + #10;
  Writeln(s);
end;

procedure Check(cond: Boolean; const name: string);
begin
  if cond then
  begin
    Inc(gPass);
    TLog('PASS  ' + name);
  end
  else
  begin
    Inc(gFail);
    TLog('FAIL  ' + name);
  end;
end;

function RunSelftest: Integer;
var
  it1: TItemInst;
  basePrice: Integer;
  loaded: TPlayer;
  txt: string;
  mid: Integer;
  taken: TStrArray;
  cost: Integer;
  ok: Boolean;
  si: Integer;
  has: Boolean;
  k: Integer;
  p, p2: TPlayer;
  i, j: Integer;
  err: string;
  items: TItemArr;
  gold: Integer;
  syms: array of TSymbol;
  savedSeeds: TStrArray;
  ci: Integer;
  savedMul, savedManaMul, savedStamMul: Single;
  baseHp, baseMana, baseStam: Single;
begin
  gPass := 0; gFail := 0; gLog := '';
  TLog('=== PLAMEN selftest commit=' + VERSION_STAMP + ' ===');
  SeedRNG(12345);
  LoadAllData;

  { ---- 1. registry volumes (brief content minimums) ---- }
  Check(Length(GMonsters) >= 15, Format('monsters >= 15 (%d)', [Length(GMonsters)]));
  Check(Length(GSpells) >= 30, Format('spells >= 30 (%d)', [Length(GSpells)]));
  Check(Length(GUniques) >= 50, Format('uniques >= 50 (%d)', [Length(GUniques)]));
  Check(Length(GLore) >= 25, Format('lore docs >= 25 (%d)', [Length(GLore)]));
  Check(Length(GQuests) >= 40, Format('quests >= 40 (%d)', [Length(GQuests)]));
  Check(Length(GSkills) >= 150, Format('skill nodes >= 150 (%d)', [Length(GSkills)]));
  Check(Length(GStores) = 5, 'stores == 5');
  Check(Length(GRegions) = 5, 'regions == 5');
  Check(Length(GRaces) = 5, 'races == 5');
  Check(Length(GClasses) = 6, 'classes == 6');
  Check(Length(GElements) = 6, 'elements == 6');
  Check(Length(GBuilds) >= 12, Format('builds >= 12 (%d)', [Length(GBuilds)]));
  j := 0;
  for i := 0 to High(GLore) do
    if GLore[i].contradicts <> '' then Inc(j);
  Check(j >= 3, Format('contradicting lore pairs >= 3 (%d)', [j]));
  j := 0;
  for i := 0 to High(GLore) do
    if GLore[i].hidden then Inc(j);
  Check(j >= 1, 'hidden endgame book exists');

  { ---- 2. stat registry formulas (incl. class muls, wired in fix pass) ---- }
  NewPlayer(p, 'Selftest', 'ashborn', 'wardancer', False);
  ci := FindClass('wardancer');
  Check(Abs(GetStat(p, 'max_hp') - (30 + 8 * 8 + 1 * 4) * GClasses[ci].hpMul) < 0.001, 'formula max_hp = (30+might*8+level*4) * class hp_mul');
  Check(Abs(GetStat(p, 'max_mana') - (10 + 8 * 7 + 8 * 2) * GClasses[ci].manaMul) < 0.001, 'formula max_mana = (10+spirit*7+wits*2) * class mana_mul');
  p.gear[4] := MakeItem('miner_gloves', 0, 1);  // hands: might=2
  RecalcStats(p);
  Check(Abs(GetStat(p, 'max_hp') - (30 + 10 * 8 + 1 * 4) * GClasses[ci].hpMul) < 0.001, 'gear flat might=2 raises max_hp (x class hp_mul)');
  syms := nil;
  Check(Abs(EvalFormula('2+3*4', syms) - 14) < 0.001, 'eval 2+3*4=14');
  Check(Abs(EvalFormula('(1+2)*3/2', syms) - 4.5) < 0.001, 'eval (1+2)*3/2=4.5');

  { ---- 3. elements wheel ---- }
  Check(Abs(ElemAdv('fire', 'nature') - 0.25) < 0.001, 'fire beats nature +25%');
  Check(Abs(ElemAdv('nature', 'fire') + 0.25) < 0.001, 'nature loses to fire -25%');
  Check(Abs(ElemAdv('raw', 'fire')) < 0.001, 'raw neutral');

  { ---- 4. combat math ---- }
  Check(Abs(CalcHitDamage(10, 'raw', 0, 150, 0, 0, 1, False) - 10) < 0.001, 'plain hit 10');
  Check(Abs(CalcHitDamage(10, 'raw', 0, 150, 0, 10, 1, False) - 7) < 0.001, 'armor 10 -> 7');
  Check(Abs(CalcHitDamage(10, 'raw', 0, 150, 50, 0, 1, False) - 5) < 0.001, 'resist 50 -> 5');
  Check(Abs(CalcHitDamage(10, 'raw', 0, 150, 0, 0, 1, True) - 15) < 0.001, 'crit x1.5 -> 15');

  { ---- 5. XP / leveling ---- }
  NewPlayer(p, 'XPTest', 'untethered', 'lightbinder', False);
  AddXP(p, 2000);
  Check(p.level > 3, Format('xp 2000 -> level %d (>3)', [p.level]));
  Check(p.skillPoints >= 2 + 2 * (p.level - 1) + (p.level - 1), 'untethered +1 skill/lvl');
  Check(p.level <= LEVEL_CAP, 'level cap 30 respected');

  { ---- 6. loot tables ---- }
  SeedRNG(999);
  RollLoot('t_boss_charred_maw', 10, items, gold);
  j := 0;
  for i := 0 to High(items) do
    if (items[i].uid = 'mawfang_blade') or (items[i].uid = 'cinderheart') then Inc(j);
  Check(j = 2, Format('boss table drops both uniques (got %d)', [j]));
  Check(gold >= 0, 'gold roll ok');
  SeedRNG(7);
  j := 0;
  for i := 0 to 49 do
  begin
    RollLoot('t_hound', 5, items, gold);
    Inc(j, Length(items));
  end;
  Check(j > 0, Format('hound table drops something in 50 rolls (%d)', [j]));
  // affix rolling: make a rarity-3 item, expect 2 affixes
  SeedRNG(42);
  it1 := MakeItem('rapier', 3, 10);
  Check((it1.aff1 <> '') and (it1.aff2 <> ''), 'rarity 3 item rolls 2 affixes');
  Check(it1.stats <> '', 'affixes resolved into stats string');

  { ---- 7. quest consequence chains (act1 -> act4) ---- }
  NewPlayer(p, 'QuestTest', 'ashborn', 'wardancer', False);
  Check(QuestState(p, 'q_act1_1') = 'available', 'q_act1_1 available at start');
  QuestAccept(p, 'q_act1_1');
  QuestEvent(p, 'talk', 'sela_vosch');
  Check(FlagEq(p.flags, 'act1.started', '1'), 'q_act1_1 complete sets act1.started');
  QuestRefresh(p);
  Check(QuestState(p, 'q_act1_2') = 'available', 'q_act1_2 available after q_act1_1 completed');
  // branch A: looter freed
  QuestAccept(p, 'q_act1_looter');
  FlagSet(p.flags, 'act1.looter', 'freed');   // dialog choice
  QuestEvent(p, 'interact', 'vey_tann');
  Check(QuestState(p, 'q_act1_looter') = 'complete', 'looter quest completes');
  Check(FlagEq(p.flags, 'compact.supply_glass', '1'), 'freed looter -> Glass Wastes supply line open (act4)');
  Check(FlagEq(p.flags, 'quest.q_act4_supply.available', '1'), 'act4 supply quest flagged available');
  Check(FlagEq(p.flags, 'ashkar.trust', '-1'), 'freed looter -> Ashkar trust -1');
  // act2 cell saved -> remnant library -> act5 third path
  SetAct(p, 2);
  QuestRefresh(p);
  QuestAccept(p, 'q_act2_cell');
  QuestEvent(p, 'reach', 'maren_area1');
  QuestEvent(p, 'kill', 'drowned_knight');
  QuestEvent(p, 'kill', 'drowned_knight');
  QuestEvent(p, 'kill', 'drowned_knight');
  QuestEvent(p, 'talk', 'vessel_quill');
  Check(FlagEq(p.flags, 'act2.cell_saved', '1'), 'act2 cell saved flag');
  Check(FlagEq(p.flags, 'remnant.library', '1'), 'cell saved -> Remnant library exists in act4');
  SetAct(p, 3);
  Check(FlagEq(p.flags, 'npc.vessel_quill', 'dead'), 'act3: Sela executes Quill (consequence)');
  SetAct(p, 5);
  Check(FlagEq(p.flags, 'endgame.third_path', '1'), 'act5: third path available when library survived');
  // branch B: looter handed over + cinderhold falls
  NewPlayer(p, 'QuestTestB', 'stormcrowned', 'emberweaver', False);
  QuestAccept(p, 'q_act1_1');
  QuestEvent(p, 'talk', 'sela_vosch');
  QuestRefresh(p);
  QuestAccept(p, 'q_act1_looter');
  FlagSet(p.flags, 'act1.looter', 'handed');
  QuestEvent(p, 'interact', 'vey_tann');
  Check(FlagEq(p.flags, 'compact.block_maren', '1'), 'handed looter -> Compact blockades Maren gear');
  Check(FlagEq(p.flags, 'ashkar.trust', '2'), 'handed looter -> Ashkar trust +2');
  FlagSet(p.flags, 'quest.q_act1_2.completed', '1');
  QuestRefresh(p);
  QuestAccept(p, 'q_act1_defense');
  FlagSet(p.flags, 'region.emberfall.overrun', '1');
  QuestTick(p);
  Check(QuestState(p, 'q_act1_defense') = 'failed', 'defense quest fails when overrun');
  Check(FlagEq(p.flags, 'region.emberfall.hub', 'cinderhold_ruins'), 'overrun -> different hub for whole game');
  Check(FlagEq(p.flags, 'store.price_mul', '1.30'), 'overrun -> stores pricier');

  { ---- 8. store price / trust rules ---- }
  NewPlayer(p, 'StoreTest', 'ashborn', 'wardancer', False);
  basePrice := StorePrice(p, 'cinderhold', 'health_vial');
  Check(basePrice = 15, Format('base price health_vial = 15 (got %d)', [basePrice]));
  FlagSet(p.flags, 'compact.trust', '3');
  Check(StorePrice(p, 'cinderhold', 'health_vial') = Round(15 * 0.88), 'trust 3 -> -12%');
  FlagSet(p.flags, 'compact.supply_glass', '1');
  Check(StorePrice(p, 'glass_hub', 'health_vial') = Round(15 * 0.88 * 0.85), 'supply line -> glass -15% extra');
  FlagSet(p.flags, 'compact.block_maren', '1');
  Check(StorePrice(p, 'maren_hub', 'health_vial') = Round(15 * 0.88 * 1.5), 'blockade -> maren +50%');
  NewPlayer(p, 'StormStore', 'stormcrowned', 'wardancer', False);
  Check(StorePrice(p, 'cinderhold', 'health_vial') = Round(15 * 1.10), 'stormcrowned pays +10% everywhere');

  { ---- 9. save/load round-trip + tamper detection ---- }
  NewPlayer(p, 'SaveTest', 'veilkin', 'shadowpact', True);
  AddXP(p, 500);
  p.gold := 777;
  FlagSet(p.flags, 'act1.looter', 'freed');
  QuestAccept(p, 'q_act1_1');
  QuestEvent(p, 'talk', 'sela_vosch');
  p.gear[4] := MakeItem('swift_gloves', 2, 5);
  RecalcStats(p);
  Check(SaveGame(p, 'selftest_slot', err), 'save ok: ' + err);
  Check(LoadGame(loaded, 'selftest_slot', err), 'load ok: ' + err);
  Check(loaded.name = 'SaveTest', 'round-trip name');
  Check(loaded.gold = p.gold, Format('round-trip gold (%d)', [p.gold]));
  Check(loaded.level = p.level, 'round-trip level');
  Check(loaded.gear[4].base = 'swift_gloves', 'round-trip gear');
  Check(loaded.gear[4].rarity = 2, 'round-trip rarity');
  Check(FlagEq(loaded.flags, 'act1.looter', 'freed'), 'round-trip flags');
  Check(QuestState(loaded, 'q_act1_1') = 'complete', 'round-trip quest state');
  Check(Abs(GetStat(loaded, 'max_hp') - GetStat(p, 'max_hp')) < 0.01, 'round-trip derived stats');
  // tamper: flip one payload byte
  txt := ReadTextFile('saves/selftest_slot.sav');
  mid := Length(txt) div 2 + 10;
  if txt[mid] = 'a' then txt[mid] := 'b' else txt[mid] := 'a';
  WriteTextFile('saves/selftest_slot.sav', txt);
  Check(not LoadGame(loaded, 'selftest_slot', err), 'tampered save rejected');
  Check(Pos('CRC', err) > 0, 'tamper error names CRC: ' + err);
  Check(not LoadGame(loaded, 'no_such_slot', err), 'missing save rejected loudly');

  { ---- 10. build-path simulation (12 endgame builds) ---- }
  for i := 0 to High(GBuilds) do
  begin
    taken := nil; cost := 0; ok := True;
    for j := 0 to High(GBuilds[i].nodes) do
    begin
      si := FindSkill(GBuilds[i].nodes[j]);
      if si < 0 then begin ok := False; Break; end;
      if (GSkills[si].requires <> '') then
      begin
        has := False;
        for k := 0 to High(taken) do
          if taken[k] = GSkills[si].requires then has := True;
        if not has then begin ok := False; Break; end;
      end;
      cost := cost + GSkills[si].cost;
      SetLength(taken, Length(taken) + 1);
      taken[High(taken)] := GBuilds[i].nodes[j];
    end;
    Check(ok and (cost <= 2 * LEVEL_CAP), Format('build %s valid, cost %d <= 60', [GBuilds[i].id, cost]));
  end;

  { ---- 11. data-only monster/spell add (brief 5.5) ---- }
  WriteTextFile('data/_selftest_extra.dat',
    '[monster:selftest_drake]' + #10 + 'name=Selftest Drake' + #10 + 'hp=10' + #10 + 'dmg=1' + #10 +
    '[spell:selftest_zap]' + #10 + 'school=storm' + #10 + 'name=Zap' + #10 + 'mana=1' + #10);
  DataLoad(GDB, 'data/_selftest_extra.dat');
  LoadMonstersFrom('data/_selftest_extra.dat');
  LoadSpellsFrom('data/_selftest_extra.dat');
  Check(FindMonster('selftest_drake') >= 0, 'new monster added via data file alone');
  Check(FindSpell('selftest_zap') >= 0, 'new spell added via data file alone');
  DeleteFile('data/_selftest_extra.dat');

  { ---- 12. class seed skills: load-time validation + granted at chargen (fix pass) ---- }
  Check(ValidateClassSeedIds = '', 'ValidateClassSeedIds: all class seed ids exist in skills.dat');
  savedSeeds := GClasses[0].seedSkills;
  SetLength(GClasses[0].seedSkills, 1);
  GClasses[0].seedSkills[0] := 'no_such_skill_xyz';
  Check(ValidateClassSeedIds <> '', 'ValidateClassSeedIds catches unknown seed id (loud-fail contract)');
  GClasses[0].seedSkills := savedSeeds;
  Check(ValidateClassSeedIds = '', 'ValidateClassSeedIds clean again after restore');
  for i := 0 to High(GClasses) do
  begin
    NewPlayer(p, 'SeedT', GRaces[0].id, GClasses[i].id, False);
    ok := Length(GClasses[i].seedSkills) > 0;
    for j := 0 to High(GClasses[i].seedSkills) do
    begin
      has := False;
      for k := 0 to High(p.skills) do
        if p.skills[k] = GClasses[i].seedSkills[j] then has := True;
      if not has then ok := False;
    end;
    Check(ok and (Length(p.skills) >= Length(GClasses[i].seedSkills)),
      Format('class %s grants its %d seed skills at chargen', [GClasses[i].id, Length(GClasses[i].seedSkills)]));
  end;

  { ---- 13. class stat multipliers wired (hp_mul/mana_mul/stam_mul, fix pass) ---- }
  NewPlayer(p, 'MulA', GRaces[0].id, 'wardancer', False);       // hp 0.95 mana 0.7 stam 1.2
  NewPlayer(p2, 'MulB', GRaces[0].id, 'wardens_hound', False);  // hp 1.35 mana 0.6 stam 1.1
  // strip kit gear so only the class mul differs (attrs are fixed at 8, same race)
  for i := 0 to SLOT_COUNT - 1 do
  begin
    p.gear[i].base := '';
    p2.gear[i].base := '';
  end;
  RecalcStats(p);
  RecalcStats(p2);
  Check(Abs(GetStat(p2, 'max_hp') / GetStat(p, 'max_hp') - 1.35 / 0.95) < 0.001,
    'class hp_mul applies: hound/wardancer max_hp ratio ' + F2S(GetStat(p2, 'max_hp') / GetStat(p, 'max_hp'), 4) + ' ~= ' + F2S(1.35 / 0.95, 4));
  Check(Abs(GetStat(p2, 'max_mana') / GetStat(p, 'max_mana') - 0.6 / 0.7) < 0.001,
    'class mana_mul applies: hound/wardancer max_mana ratio ' + F2S(GetStat(p2, 'max_mana') / GetStat(p, 'max_mana'), 4) + ' ~= ' + F2S(0.6 / 0.7, 4));
  Check(Abs(GetStat(p2, 'max_stamina') / GetStat(p, 'max_stamina') - 1.1 / 1.2) < 0.001,
    'class stam_mul applies: hound/wardancer max_stamina ratio ' + F2S(GetStat(p2, 'max_stamina') / GetStat(p, 'max_stamina'), 4) + ' ~= ' + F2S(1.1 / 1.2, 4));
  // direct: doubling the muls scales the un-multiplied base by 2.0
  ci := FindClass('wardancer');
  savedMul := GClasses[ci].hpMul;
  savedManaMul := GClasses[ci].manaMul;
  savedStamMul := GClasses[ci].stamMul;
  baseHp := GetStat(p, 'max_hp');
  baseMana := GetStat(p, 'max_mana');
  baseStam := GetStat(p, 'max_stamina');
  GClasses[ci].hpMul := 2.0;
  GClasses[ci].manaMul := 2.0;
  GClasses[ci].stamMul := 2.0;
  RecalcStats(p);
  Check((Abs(GetStat(p, 'max_hp') - baseHp / savedMul * 2.0) < 0.01) and
        (Abs(GetStat(p, 'max_mana') - baseMana / savedManaMul * 2.0) < 0.01) and
        (Abs(GetStat(p, 'max_stamina') - baseStam / savedStamMul * 2.0) < 0.01),
    'changing class muls changes max_hp/mana/stamina (2x mul -> 2x unmul base)');
  GClasses[ci].hpMul := savedMul;
  GClasses[ci].manaMul := savedManaMul;
  GClasses[ci].stamMul := savedStamMul;
  RecalcStats(p);
  Check(Abs(GetStat(p, 'max_hp') - baseHp) < 0.01, 'class muls restored, max_hp back to base');

  { ---- done ---- }
  TLog(Format('=== selftest done: %d passed, %d failed ===', [gPass, gFail]));
  WriteTextFile('selftest.log', gLog);
  if gFail = 0 then Result := 0 else Result := 1;
end;

end.
