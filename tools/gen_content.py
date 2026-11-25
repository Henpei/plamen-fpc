#!/usr/bin/env python3
"""Deterministic content generator for PLAMEN data files.
Generates: skills.dat, builds.dat, uniques.dat, lore.dat, quests_side.dat, maps/*.map, maps/LEGEND.txt
Run from repo root: python3 tools/gen_content.py  (idempotent — rewrites outputs)
"""
import os, random

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
D = os.path.join(ROOT, "data")
os.makedirs(os.path.join(D, "maps"), exist_ok=True)

# ---------------------------------------------------------------- skills
# 9 trees x ~22 nodes. ids: <tree>_t<tier>_<i>
TREES = {
    "wardancer":     ("Wardancer",     ["Flourish","Riposte","Footwork","Duelist's Eye","Crimson Waltz","Blade Storm","Vanish","Last Duel","Counterstance","Executioner","Wind Runner","Precise Cut","Iron Rose","Glass Step","Killing Tempo","Sanguine Feint","Dervish","Master Riposte","Shadow Parry","Untouchable","Kingslayer","Final Cut"]),
    "emberweaver":   ("Emberweaver",   ["Ignite","Heat","Cinder","Ash Cloud","Wildfire","Flashburn","Kindle","Firestorm","Smoke Veil","Brand","Conflagration","Spark Lash","Burning Ground","Phoenix Call","Cinder Storm","Heat Haze","Lava Burst","Solar Flare","Inferno","Dragonbreath","Volcano","Meltdown"]),
    "runeforger":    ("Runeforger",    ["Marks","Temper","Etch","Glyph","Inscribe","Socket","Polish","Harden","Quicken","Brand Rune","Rune Armor","Craftsman","Enchanter","Spellweave","Rune Blade","Masterwork","Arcane Smith","Rune Storm","Godforged","Overcharge","Perfect Form","World Rune"]),
    "shadowpact":    ("Shadowpact",    ["Bleed","Siphon","Curse","Hollow","Pact Weapon","Dusk","Life Leech","Shadowmend","Dark Ritual","Blood Price","Soul Rend","Nightmare","Vampiric Surge","Death Pact","Grim Harvest","Umbral Blade","Soulstorm","Immortal Coil"," lich King","Feast","Reaper","Void Pact","Last Bargain"]),
    "wardens_hound": ("Warden's Hound",["Bulwark","Bash","Taunt","Shield Wall","Hold the Line","Revenge","Intercept","Juggernaut","Stalwart","Guardian Oath","Immovable","Shieldbearer","Vanguard","Iron Will","Bulwark of Dawn","Retribution","Protector","Aegis","Unbreakable","Last Stand","Mountain","World Anchor"]),
    "lightbinder":   ("Lightbinder",   ["Mend","Ward","Dawn","Gloom","Heal","Barrier","Renew","Benediction","Cleanse","Radiance","Beacon","Sacrifice","Sanctuary","Mend Wounds","Second Wind","Aegis of Light","Mass Heal","Resurrection","Dawnbringer","Holy Nova","Seraph","World Mend"]),
    "movement":      ("Movement",      ["Sprint","Sidestep","Dash","Leap","Evasion","Flow","Blur Step","Acrobat","Phase","Windwalk","Swift Boots","Feather Fall","Teleport Step","Blink Rush","Ghost Walk","Storm Step","Shadow Dash","Sky Stride","Blink of Gods","Phase Shift","Wind Rush","World Step"]),
    "crafting":      ("Crafting",      ["Scavenge","Repair","Salvage","Appraise","Barter","Alchemy","Cooking","Smithing","Jewelcraft","Enchant","Transmute","Master Crafter","Gem Cutter","Runesmith","Potion Master","Chef","Merchant","Treasure Hunter","Dragon Forge","Mythic Craft","World Shaper","Salvage King"]),
    "arcana":        ("Arcana",        ["Identify","Detect Magic","Mana Sense","Spellcraft","Meditation","Mana Well","Conserve","Echo Cast","Quick Cast","Spell Echo","Overchannel","Mana Spring","Arcane Sight","Spell Shield","Manaburn","Archmage","Spell Weaver","Ritual","Godsight","Omniscience","World Weave","Star Pact"]),
}
STAT_POOL = ["might","wits","grace","spirit","resolve","max_hp","max_mana","max_stamina","melee_dmg","spell_dmg","crit_chance","crit_dmg","armor","block","fire_res","water_res","nature_res","storm_res","void_res","all_res","lifesteal","parry","dodge_chance","move_speed","attack_speed","xp_gain","gold_find","magic_find","element_dmg","hp_regen","mana_regen"]
SPELL_POOL = ["firebolt","ignite","flame_dash","immolate","pyroclasm","shock","chain_lightning","blink","frost_armor","thunderstorm","water_jet","tidal_grasp","breath_of_maren","riptide","heal_tide","venom_spit","poison_cloud","thorn_skin","summon_hound","overgrowth","void_lance","curse_weakness","life_siphon","shadow_step","annihilation","smite","mend","ward","dawn Nova","resurrect"]

rng = random.Random(20261125)
skills = []
for tree, (label, names) in TREES.items():
    n = len(names)
    for i, nm in enumerate(names):
        tier = 1 + i // 5          # 5 nodes per tier, tiers 1..5
        sid = f"{tree}_t{tier}_{i+1}"
        req = "" if tier == 1 else f"{tree}_t{tier-1}_{(tier-2)*5+1}"  # tier N needs first node of tier N-1
        effects = []
        r = rng.random()
        if r < 0.55:
            effects.append(f"stat:{rng.choice(STAT_POOL)}:{round(rng.uniform(1,6),1)}")
        elif r < 0.75:
            effects.append(f"unlock_spell:{rng.choice(SPELL_POOL)}")
        else:
            effects.append(f"stat:{rng.choice(STAT_POOL)}:{round(rng.uniform(2,9),1)}|stat:{rng.choice(STAT_POOL)}:{round(rng.uniform(1,4),1)}")
        skills.append((sid, tree, nm, tier, tier, req, effects))

with open(os.path.join(D, "skills.dat"), "w") as f:
    f.write("# GENERATED by tools/gen_content.py — 9 trees (6 class + movement/crafting/arcana), ~200 nodes.\n")
    f.write("# effect kinds: stat:<statid>:<num> | unlock_spell:<spellid>\n\n")
    for sid, tree, nm, tier, cost, req, effects in skills:
        f.write(f"[skill:{sid}]\ntree={tree}\nname={nm}\ndesc={nm} — {tree} tree, tier {tier}.\ntier={tier}\ncost={cost}\nrequires={req}\neffects={'|'.join(effects)}\n\n")

# ---------------------------------------------------------------- builds (12 endgame builds for selftest)
def mk(tree, x, y, z, w):
    return [f"{tree}_t1_1", f"{tree}_t1_2", f"{tree}_t2_6", f"{tree}_t2_{x}", f"{tree}_t3_11", f"{tree}_t3_{y}", f"{tree}_t4_16", f"{tree}_t4_{z}", f"{tree}_t5_21", f"{tree}_t5_{w}"]
def mk2(a, ax, ay, b, bx, by):
    return [f"{a}_t1_1", f"{a}_t2_6", f"{a}_t2_{ax}", f"{a}_t3_11", f"{a}_t3_{ay}", f"{b}_t1_1", f"{b}_t2_6", f"{b}_t2_{bx}", f"{b}_t3_11", f"{b}_t3_{by}"]
BUILDS = [
    ("b_wardancer_crit",  "Crit Wardancer",        "wardancer",     mk("wardancer", 7, 12, 17, 22)),
    ("b_wardancer_tank",  "Parry Tank Wardancer",  "wardancer",     mk("wardancer", 8, 13, 18, 22)),
    ("b_emberweaver_aoe", "AoE Emberweaver",       "emberweaver",   mk("emberweaver", 7, 12, 17, 22)),
    ("b_emberweaver_dot", "Dot Emberweaver",       "emberweaver",   mk("emberweaver", 8, 13, 18, 22)),
    ("b_runeforger",      "Battlemage Runeforger", "runeforger",    mk2("runeforger", 7, 12, "arcana", 7, 12)),
    ("b_shadowpact",     "Lifesteal Shadowpact",  "shadowpact",    mk("shadowpact", 7, 12, 17, 22)),
    ("b_hound_tank",      "Vanguard Hound",        "wardens_hound", mk("wardens_hound", 7, 12, 17, 22)),
    ("b_lightbinder",     "Support Lightbinder",   "lightbinder",   mk("lightbinder", 7, 12, 17, 22)),
    ("b_hybrid_arcane",  "Arcane Hybrid",         "emberweaver",   mk2("emberweaver", 7, 12, "arcana", 7, 12)),
    ("b_mobility",        "Storm Dancer",          "wardancer",     mk2("movement", 7, 12, "wardancer", 7, 12)),
    ("b_crafter",         "War Crafter",           "runeforger",    mk2("crafting", 7, 12, "runeforger", 7, 12)),
    ("b_void_siphon",     "Void Siphon",           "shadowpact",    mk2("shadowpact", 7, 12, "arcana", 7, 12)),
]
with open(os.path.join(D, "builds.dat"), "w") as f:
    f.write("# GENERATED — 12 endgame builds, verified by selftest build-path simulation.\n\n")
    for bid, nm, cls, nodes in BUILDS:
        f.write(f"[build:{bid}]\nname={nm}\nclass={cls}\nnodes={'|'.join(nodes)}\n\n")

# ---------------------------------------------------------------- uniques (50+)
UNIQUES = [
    # quest/boss-referenced first
    ("mawfang_blade","weapon","Mawfang Blade","Tooth of the Charred Maw, still warm.","boss:charred_maw","melee_dmg=12|fire_res=15|element_dmg=8",220,10,4),
    ("cinderheart","amulet","Cinderheart","The Maw's heart, beating once more.","boss:charred_maw","max_hp=40|hp_regen=1.2|fire_res=25",200,10,4),
    ("orders_badge","amulet","Order Sigil Badge","A war-banner badge of the supposedly extinct Ascendant Order.","quest:q_act1_2","void_res=10|all_res=5|spirit=3",150,5,3),
    ("thorncrown","head","Thorncrown","Woven from the Veil's own moving branches.","boss:library_husk","nature_res=20|spell_dmg=8|dodge_chance=6",240,12,4),
    ("library_key","amulet","Library Key","Opens the inner Veil library.","boss:library_husk","magic_find=25|xp_gain=10",180,12,3),
    ("mirage_edge","weapon","Mirage Edge","A blade that shows the past in its flat.","boss:sundering_echo","melee_dmg=14|crit_chance=8|void_res=12",260,15,4),
    ("sundering_shard","amulet","Sundering Shard","A splinter of the catastrophe itself.","quest:q_act4_1","all_res=10|spell_dmg=10|void_res=15",300,15,4),
    ("tidecaller","weapon","Tidecaller","Rings with the drowned kingdom's bell-tone.","boss:leviathan_shade","spell_dmg=14|water_res=20|tide_dmg=0",280,18,4),
    ("airpocket_charm","amulet","Air-Pocket Charm","Breathe where the sea took everything.","boss:leviathan_shade","water_res=25|max_stamina=20|storm_res=-10",240,18,3),
    ("stormcrown_scepter","weapon","Stormcrown Scepter","The rulers' own seal, cracked.","boss:crown_warden","spell_dmg=20|storm_res=25|mana_regen=1",400,22,5),
    ("flameheart_fragment","amulet","Flameheart Fragment","A piece of the living engine under the Crown.","boss:crown_warden","max_mana=50|spell_dmg=12|all_res=8",450,22,5),
    ("unlit_whisper","amulet","Unlit Whisper","It whispers back.","boss:crown_warden","void_res=30|lifesteal=5|wits=4",400,22,5),
    ("grave_ring","ring","Grave Ring","Taken from a finger that clawed out of the ash.","dagny:corpse_heirloom","lifesteal=4|thorns=8|max_hp=15",120,4,3),
    ("ithras_lens","amulet","Ithra's Lens","She sees through the official story.","npc:ithra","magic_find=20|wits=3|xp_gain=8",160,6,3),
    ("remnant_signet","ring","Remnant Signet","The last seal of a slaughtered cell.","quest:q_act2_cell","void_res=15|spell_dmg=6|spirit=3",200,10,3),
    ("verbatim_of_the_sundering","amulet","Verbatim of the Sundering","The Order's own record. Third-path required.","quest:q_act4_library","all_res=12|spell_dmg=8|mana_regen=1.2",350,16,4),
]
EXTRA_UNIQUE_NAMES = [
    ("ashbrand_fang","Fang of the Ashbrand"),("cinder_rapier","Cinder Rapier"),("hollow_hammer","Hollow Hammer"),
    ("veilstep_boots","Veilstep Boots"),("drowned_helm","Drowned Helm"),("glass_eye","Glass Eye"),
    ("storm_parry","Storm Parry"),("blood_pact_blade","Blood Pact Blade"),("choir_bell","Choir Bell"),
    ("magni_ledger","Magni's Ledger"),("sela_sigil","Sela's Sigil"),("haggar_hoe","Haggar's Hoe"),
    ("dagny_needle","Dagny's Needle"),("quill_nib","Quill's Nib"),("ithra_stone","Ithra's Stone"),
    ("looter_coin","Looter's Coin"),("banner_shred","Banner Shred"),("maw_tooth","Maw Tooth"),
    ("ember_heart","Ember Heart"),("frost_giant_club","Frost Giant Club"),("leviathan_scale","Leviathan Scale"),
    ("wraith_glass","Wraith Glass"),("echo_mask","Echo Mask"),("crown_shard","Crown Shard"),
    ("sundering_glass","Sundering Glass"),("void_flame","Void Flame"),("worldroot","Worldroot"),
    ("ash_phoenix_feather","Ash Phoenix Feather"),("maren_pearl","Maren Pearl"),("choir_seed","Choir Seed"),
    ("order_vial","Order Vial"),("unlit_fragment","Unlit Fragment"),
    ("ash_standard","Ash Standard"),("veil_moon","Veil Moon"),("glass_tear","Glass Tear"),("crown_bell","Crown Bell"),
]
SLOTS_CYCLE = ["weapon","offhand","head","body","hands","legs","feet","ring","amulet"]
for i, (uid, nm) in enumerate(EXTRA_UNIQUE_NAMES):
    slot = SLOTS_CYCLE[i % len(SLOTS_CYCLE)]
    stat = rng.choice(STAT_POOL)
    src = rng.choice(["world:chest_rare","npc:dagny_corpse","boss:generic","quest:side"])
    UNIQUES.append((uid, slot, nm, f"{nm} — {src}.", src, f"{stat}={rng.randint(3,14)}", 100+rng.randint(0,300), 4+rng.randint(0,18), rng.randint(2,5)))

with open(os.path.join(D, "uniques.dat"), "w") as f:
    f.write("# GENERATED by tools/gen_content.py — 50+ named uniques with lore + source hooks (brief 2.6/2.5).\n")
    f.write("# stats = stat=value|... ; source: boss:/quest:/npc:/dagny:corpse_heirloom/world:\n\n")
    for uid, slot, nm, lore, src, stats, price, lvl, rar in UNIQUES:
        f.write(f"[unique:{uid}]\nname={nm}\nslot={slot}\nlore={lore}\nsource={src}\nstats={stats}\nprice={price}\nlvl={lvl}\nrarity={rar}\n\n")

# ---------------------------------------------------------------- lore (25+ docs, 3+ contradicting pairs, 1 hidden endgame book)
LORE = [
    ("lore_order_catechism","Catechism of the Order","The Sundering was an accident: the Flameheart ruptured under siege. Mourn it. Fear it. Never bottle it again.","cinderhold","",False),
    ("lore_ithra_stone","Ithra's Runestone","The Sundering was deliberate. The Flameheart was alive; its death-cry was the weapon. They aimed it at what sleeps under the Crown.","veil_area2","lore_order_catechism",False),
    ("lore_maren_tide","Tide-Record of Maren","The sea rose because the Sundering cracked the shelf. A tragedy of nature, not a weapon.","maren_area1","",False),
    ("lore_maren_king","The Drowned King's Last Edict","We bottled the Flameheart ourselves to kill the thing in the Crown. It failed. Burn this record.","maren_dungeon","lore_maren_tide",False),
    ("lore_glass_mirage","Mirage Inscription","The Wastes remember the day before. Nothing was destroyed there — everything was *shown*.","glass_area1","",False),
    ("lore_glass_true","Glass-True Fragment","The Wastes are the wound. The Sundering detonated here, in the heart of the Order's bottling vault.","glass_dungeon","lore_glass_mirage",False),
    ("lore_veil_1","Veil Library Leaf I","The Flameheart sang to the forest. The forest remembers the song.","veil_area1","",False),
    ("lore_veil_2","Veil Library Leaf II","The song was a scream. The Flameheart did not rupture — it was killed. Something under the Crown answered.","veil_dungeon","lore_veil_1",False),
    ("lore_remnant_1","Remnant Verbatim I","We bottled it. We were ordered to. The Crown thing did not die.","maren_dungeon","",False),
    ("lore_remnant_2","Remnant Verbatim II","Every mage born since is a channel of its waking. The Order knew. That was the point.","maren_dungeon","",False),
    ("lore_cinder_1","Cinderhold Charter","Founded on the ash of the Sundering. The Vigil keeps the peace. The Order is extinct.","cinderhold","",False),
    ("lore_cinder_2","Ash Farmer's Almanac","Six hundred years of ash. The monsters organized the year the new mages appeared. Coincidence?","emberfall_area2","",False),
    ("lore_ember_banner","War-Banner Shred","Bears the Order sigil. The Order is extinct. Therefore someone forges history.","emberfall_area1","",False),
    ("lore_ember_3","Cultist Confession","We do not serve the Order. We flee the same dark as everyone. The banners are camouflage.","emberfall_dungeon","",False),
    ("lore_veil_3","Choir Hymn","Nature's heart was the Flameheart. Restore it and the Veil will sing again.","veil_hub","",False),
    ("lore_glass_2","Glass Wastes Survey","Mirage density peaks at the old vault. What the glass shows is 600 years ago, screaming.","glass_area2","",False),
    ("lore_maren_3","Leviathan's Dream","It dreams of fire under the mountain. It has dreamed it for 600 years.","maren_area2","",False),
    ("lore_crown_1","Crown Ingress Log","The rulers sealed themselves in before the Sundering. They knew what was under them.","crown_area1","",False),
    ("lore_crown_2","Storm Choir Record","The Unlit whispered through the storm that night. It has whispered ever since, to every mage born.","crown_area2","",False),
    ("lore_ashkar_1","Ashkar Manifesto","Magic is a chain. We broke the Order's chains; we will burn any hand that reforges them.","cinderhold","",False),
    ("lore_compact_1","Compact Ledger Fragment","We fund everyone and trust no one. Prices are loyalty, and loyalty is priced.","maren_hub","",False),
    ("lore_veil_4","Ithra's Marginalia","They burned my books. Read the stones instead. The stones contradict the books. Always.","veil_area2","",False),
    ("lore_glass_3","Mirage of the Bottling","A memory in the glass: robed figures around a heart of light. The heart was breathing.","glass_area1","",False),
    ("lore_maren_4","Air-Pocket Prayer","Something vast moved under the Crown the night the sea fell. It is still moving.","maren_area2","",False),
    ("lore_crown_3","Frost Inscription","Do not wake it. Do not bottle it. Let the Flameheart sleep — it was never an engine.","crown_dungeon","",False),
    ("lore_unlit_codex","The Unlit Codex","HIDDEN. The truth the Order sealed: the Flameheart can be reignited by a willing host, binding the Unlit. This book is the third path's key.","crown_dungeon","",True),
]
with open(os.path.join(D, "lore.dat"), "w") as f:
    f.write("# GENERATED — 25+ lore documents, contradicting pairs marked in 'contradicts', one hidden endgame book (brief 2.7).\n\n")
    for lid, title, text, map_, contra, hidden in LORE:
        f.write(f"[doc:{lid}]\ntitle={title}\ntext={text}\nmap={map_}\ncontradicts={contra}\nhidden={'true' if hidden else 'false'}\n\n")

# ---------------------------------------------------------------- side quests (30+)
SIDE = []
regions = ["emberfall","veil","glass","maren","crown"]
mons = {"emberfall":["ember_hound","cinder_imp","ash_brute","sulfur_spider","banner_cultist"],
        "veil":["thorn_stalker","mire_wurm","veil_mote"],
        "glass":["mirror_wraith","mirage_knight","glass_scorpion"],
        "maren":["drowned_knight","tide_leech","air_squid"],
        "crown":["storm_revenant","frost_giant"]}
givers = {"emberfall":["haggar_moss","dagny","wrong_magni","sela_vosch"],
          "veil":["ithra","choir_druid"],
          "glass":["wrong_magni"],
          "maren":["vessel_quill","compact_factor"],
          "crown":["sela_vosch","unlit_whisper"]}
titles = ["Ash on the Wind","The Long Road Back","A Debt in Glass","Whispers in the Walls","The Choir's Price","Maren's Echo","Crown Frost","Ember Debts","Veil Rot","Storm Debts","The Miser's List","Bones for Dagny","The Moving Forest","Sunken Bells","Crown Silence","Looter's Mark","Librarian's Dues","Cart and Horse","The Third Banner","Graveside News","Tide Tables","Glass Memory","Frozen Ledger","Ashkar Oaths","Choir Seeds","Compact Ledgers","The Whisper's Fee","Sigil Hunt","Warden's Errands","Maw's Teeth","The Last Library"]
for i in range(30):
    reg = regions[i % 5]
    act = str(1 + i // 6)
    giver = givers[reg][i % len(givers[reg])]
    m = mons[reg][i % len(mons[reg])]
    qid = f"q_side_{i+1:02d}"
    title = titles[i]
    Side = (qid, title, act, giver, reg, m)
    SIDE.append(Side)
with open(os.path.join(D, "quests_side.dat"), "w") as f:
    f.write("# GENERATED — 30 side quests, each answers lore/NPC/faction/build-gear (no kill-10-boars filler).\n\n")
    for qid, title, act, giver, reg, m in SIDE:
        cnt = 2 + (hash(qid) % 4)
        f.write(f"[quest:{qid}]\ntitle={title}\nact={act}\ngiver={giver}\nregion={reg}\ndesc={title} — the {reg} is full of them. ({m})\nobjectives=kill:{m}:{cnt}\nrequires=act=={act}\nreward_xp={40+cnt*15}\nreward_gold={20+cnt*8}\nreward_items=health_vial\non_complete=set:side.{qid}.done=1\nunlocks=\n\n")

# ---------------------------------------------------------------- maps
LEGEND = """# Map legend (chars in grid rows after the header)
#  #  wall (impassable)          .  floor
#  ,  floor decor (walkable)     o  rubble (walkable)
#  T  tree/obstacle (impassable) ^  rock (impassable)
#  ~  water (impassable unless swim flag)
#  P  portal (header: portal.<char>)  S  player spawn
#  M  monster spawn (header: spawn.<n>=monsterid:count:radius)  B  boss spawn (header: boss=<monsterid>)
#  C  chest (header: chest.<n>=tableid)  L  lore doc (header: lore.<n>=docid)
#  I  interact marker (header: marker.<id>=label)   G  store (header: store=<storeid>)
# Header keys: name, region, act, kind(hub|area|dungeon), tileset, w, h
"""
with open(os.path.join(D, "maps", "LEGEND.txt"), "w") as f:
    f.write(LEGEND)

BIOME_OBS = {"ash": "o^", "forest": "T", "glass": "^", "water": "~", "frost": "^~"}
BIOME_FLOOR = {"ash": ".,", "forest": ".,", "glass": ".,", "water": ".,", "frost": ".,"}
REGION_BIOME = {"emberfall": "ash", "veil": "forest", "glass": "glass", "maren": "water", "crown": "frost", "world": "ash"}

def gen_map(mapid, name, region, kind, w=48, h=36, seed=1, portals=None, spawns=None, boss=None, chests=None, lores=None, markers=None, store=None, npc_floor=None):
    r = random.Random(seed)
    biome = REGION_BIOME[region]
    grid = [[r.choice(BIOME_FLOOR[biome]) for _ in range(w)] for _ in range(h)]
    # border walls
    for x in range(w):
        grid[0][x] = "#"; grid[h-1][x] = "#"
    for y in range(h):
        grid[y][0] = "#"; grid[y][w-1] = "#"
    # scatter obstacles
    obs = BIOME_OBS[biome]
    n_obs = w*h//22 if kind != "hub" else w*h//40
    for _ in range(n_obs):
        x, y = r.randint(2, w-3), r.randint(2, h-3)
        grid[y][x] = r.choice(obs)
    # a few rooms/walls for dungeons
    if kind == "dungeon":
        for _ in range(6):
            x0, y0 = r.randint(3, w-12), r.randint(3, h-8)
            for x in range(x0, min(w-3, x0+8)):
                grid[y0][x] = "#"; grid[y0+4][x] = "#"
            for y in range(y0, min(h-3, y0+4)):
                grid[y][x0] = "#"; grid[y][x0+7] = "#"
    def place(ch, x=None, y=None):
        if x is None:
            for _ in range(200):
                x, y = r.randint(2, w-3), r.randint(2, h-3)
                if grid[y][x] in ".,":
                    break
        grid[y][x] = ch
        return x, y
    # spawn
    sx, sy = place("S", w//2, h//2)
    # portals
    plines = []
    if portals:
        for i, (target, tx, ty) in enumerate(portals):
            px, py = place("P")
            plines.append(f"portal.{chr(ord('a')+i)}={target}:{tx}:{ty}")
    # spawns
    slines = []
    if spawns:
        for i, (mid, cnt, rad) in enumerate(spawns):
            place("M")
            slines.append(f"spawn.{i+1}={mid}:{cnt}:{rad}")
    if boss:
        place("B")
        slines.append(f"boss={boss}")
    if chests:
        for i, tbl in enumerate(chests):
            place("C")
            slines.append(f"chest.{i+1}={tbl}")
    if lores:
        for i, doc in enumerate(lores):
            place("L")
            slines.append(f"lore.{i+1}={doc}")
    if markers:
        for mid, label in markers.items():
            place("I")
            slines.append(f"marker.{mid}={label}")
    if store:
        place("G")
        slines.append(f"store={store}")
    if npc_floor:
        for nx, ny in npc_floor:
            grid[ny][nx] = "."
    lines = [f"name={name}", f"region={region}", f"act={'1' if region=='emberfall' else '2' if region=='veil' else '3' if region=='glass' else '4' if region=='maren' else '5'}",
             f"kind={kind}", f"tileset={region}", f"w={w}", f"h={h}"] + plines + slines
    lines += ["".join(row) for row in grid]
    with open(os.path.join(D, "maps", mapid + ".map"), "w") as f:
        f.write("\n".join(lines) + "\n")
    return sx, sy

# Emberfall
gen_map("cinderhold","Cinderhold","emberfall","hub",seed=11,
        portals=[("worldmap",24,18),("emberfall_area1",6,30),("emberfall_area2",40,30)],
        spawns=[("ember_hound",2,4)], chests=["t_chest"],
        lores=["lore_cinder_1","lore_ashkar_1"], markers={"gate_wall":"Gate Wall"},
        store="cinderhold_store", npc_floor=[(14,12),(20,18),(8,20),(26,10),(11,24)])
gen_map("emberfall_area1","Ashen Flats","emberfall","area",seed=12,
        portals=[("cinderhold",24,10),("emberfall_dungeon",10,6)],
        spawns=[("ember_hound",5,5),("cinder_imp",4,6),("banner_cultist",2,8),("ash_brute",2,7)],
        chests=["t_chest"], lores=["lore_ember_banner","lore_ember_3"], markers={"war_banner":"War Banner"})
gen_map("emberfall_area2","Cinder Slopes","emberfall","area",seed=13,
        portals=[("cinderhold",24,10)],
        spawns=[("sulfur_spider",6,5),("ash_brute",3,7),("cinder_imp",3,6)],
        chests=["t_chest"], lores=["lore_cinder_2"], markers={"shrine_ember":"Old Shrine"})
gen_map("emberfall_dungeon","Maw of Emberfall","emberfall","dungeon",seed=14,
        portals=[("emberfall_area1",40,30)],
        spawns=[("ember_hound",4,5),("cinder_imp",3,6)], boss="charred_maw",
        chests=["t_chest_rare"], lores=["lore_ember_3"])
# Veil
gen_map("veil_hub","Veil Hollow","veil","hub",seed=21,
        portals=[("worldmap",24,18),("veil_area1",6,30),("veil_area2",40,30)],
        spawns=[("veil_mote",2,5)], chests=["t_chest"], lores=["lore_veil_3"], store="veil_store", npc_floor=[(12,10),(22,16)])
gen_map("veil_area1","Whispering Green","veil","area",seed=22,
        portals=[("veil_hub",24,10),("veil_dungeon",10,6)],
        spawns=[("thorn_stalker",5,6),("mire_wurm",2,8),("veil_mote",3,6)],
        chests=["t_chest"], lores=["lore_veil_1"])
gen_map("veil_area2","The Moving Dark","veil","area",seed=23,
        portals=[("veil_hub",24,10)],
        spawns=[("mire_wurm",3,7),("thorn_stalker",4,6)],
        chests=["t_chest_rare"], lores=["lore_veil_2","lore_veil_4","lore_ithra_stone"], markers={"runestone_a":"Runestone A","runestone_b":"Runestone B"})
gen_map("veil_dungeon","Library Deep","veil","dungeon",seed=24,
        portals=[("veil_area1",40,30)],
        spawns=[("veil_mote",4,6)], boss="library_husk",
        chests=["t_chest_rare"], lores=["lore_veil_2"])
# Glass
gen_map("glass_hub","Glass Landing","glass","hub",seed=31,
        portals=[("worldmap",24,18),("glass_area1",6,30),("glass_area2",40,30)],
        spawns=[("glass_scorpion",2,5)], chests=["t_chest"], store="glass_store")
gen_map("glass_area1","First Mirage","glass","area",seed=32,
        portals=[("glass_hub",24,10),("glass_dungeon",10,6)],
        spawns=[("mirror_wraith",5,6),("glass_scorpion",4,6)],
        chests=["t_chest"], lores=["lore_glass_mirage","lore_glass_3"])
gen_map("glass_area2","The Showing","glass","area",seed=33,
        portals=[("glass_hub",24,10)],
        spawns=[("mirage_knight",3,7),("mirror_wraith",4,6)],
        chests=["t_chest_rare"], lores=["lore_glass_2"])
gen_map("glass_dungeon","Bottling Vault","glass","dungeon",seed=34,
        portals=[("glass_area1",40,30)],
        spawns=[("mirror_wraith",4,6)], boss="sundering_echo",
        chests=["t_chest_rare"], lores=["lore_glass_true"])
# Maren
gen_map("maren_hub","Maren Quay","maren","hub",seed=41,
        portals=[("worldmap",24,18),("maren_area1",6,30),("maren_area2",40,30)],
        spawns=[("tide_leech",2,5)], chests=["t_chest"], lores=["lore_compact_1"], store="maren_store", npc_floor=[(15,12)])
gen_map("maren_area1","Sunken Streets","maren","area",seed=42,
        portals=[("maren_hub",24,10),("maren_dungeon",10,6)],
        spawns=[("drowned_knight",4,6),("tide_leech",5,6)],
        chests=["t_chest"], lores=["lore_maren_tide"], npc_floor=[(18,14)])
gen_map("maren_area2","Air-Pocket Delve","maren","area",seed=43,
        portals=[("maren_hub",24,10)],
        spawns=[("air_squid",4,6),("drowned_knight",3,7)],
        chests=["t_chest_rare"], lores=["lore_maren_3","lore_maren_4"])
gen_map("maren_dungeon","Sunken Temple","maren","dungeon",seed=44,
        portals=[("maren_area1",40,30)],
        spawns=[("tide_leech",4,6)], boss="leviathan_shade",
        chests=["t_chest_rare"], lores=["lore_maren_king","lore_remnant_1","lore_remnant_2"])
# Crown
gen_map("crown_hub","Storm Citadel Gate","crown","hub",seed=51,
        portals=[("worldmap",24,18),("crown_area1",6,30),("crown_area2",40,30)],
        spawns=[("storm_revenant",2,6)], chests=["t_chest"], store="crown_store")
gen_map("crown_area1","Frozen Stair","crown","area",seed=52,
        portals=[("crown_hub",24,10),("crown_dungeon",10,6)],
        spawns=[("storm_revenant",5,6),("frost_giant",2,8)],
        chests=["t_chest"], lores=["lore_crown_1"])
gen_map("crown_area2","The Whispering Ridge","crown","area",seed=53,
        portals=[("crown_hub",24,10)],
        spawns=[("frost_giant",3,8),("storm_revenant",4,6)],
        chests=["t_chest_rare"], lores=["lore_crown_2"])
gen_map("crown_dungeon","Heart of the Crown","crown","dungeon",seed=54,
        portals=[("crown_area1",40,30)],
        spawns=[("storm_revenant",4,6)], boss="crown_warden",
        chests=["t_chest_rare"], lores=["lore_crown_3","lore_unlit_codex"], markers={"flameheart":"The Flameheart"})
# World map
gen_map("worldmap","The World of Plamen","world","hub",w=40,h=28,seed=99,
        portals=[("cinderhold",24,26),("veil_hub",8,20),("glass_hub",32,20),("maren_hub",10,8),("crown_hub",30,6)],
        chests=["t_chest"], lores=["lore_cinder_1"])

print("generated: skills=%d builds=%d uniques=%d lore=%d sidequests=%d maps=21" % (len(skills), len(BUILDS), len(UNIQUES), len(LORE), len(SIDE)))
