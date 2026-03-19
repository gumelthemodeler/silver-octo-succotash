-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- AOT_Data  (Optimized O(1) Architecture)
-- Place in: ReplicatedStorage > AOT > AOT_Data

local D = {}

D.SCHEMA_VERSION  = 2
D.DATASTORE_KEY   = "AOT_v1_"
D.GAME_VERSION    = "1.1.0"

D.GP_VIP          = 0   
D.GP_PATHS        = 0   
D.GP_AUTOTRAIN    = 0   
D.GP_VAULT        = 0   
D.GP_ARSENAL      = 0   

D.DP_FUNDS_SM     = 0   
D.DP_FUNDS_MD     = 0   
D.DP_FUNDS_LG     = 0   
D.DP_SERUMS_1     = 0   
D.DP_SERUMS_5     = 0   
D.DP_VIALS_1      = 0   
D.DP_VIALS_5      = 0   
D.DP_SPEARS_10    = 0   
D.DP_BOOST_24H    = 0   

-- ==========================================
-- STAT DEFINITIONS
-- ==========================================
D.STATS = {
	str = { name = "Strength", desc = "Base melee damage.", startValue = 5, pointCost = 1 },
	def = { name = "Defense", desc = "Flat damage reduction each hit.", startValue = 5, pointCost = 1 },
	spd = { name = "Speed", desc = "Evasion success chance.", startValue = 5, pointCost = 1 },
	wil = { name = "Willpower", desc = "Recover heal strength. Titan heat decay bonus.", startValue = 5, pointCost = 1 },
	bladeMastery = { name = "Blade Mastery", desc = "ODM gear damage multiplier.", startValue = 0, pointCost = 2 },
	titanAffinity = { name = "Titan Affinity", desc = "Reduces heat cost. Amplifies special damage.", startValue = 0, pointCost = 2, heatCostReductionPer10 = 2, specialDmgPer10 = 0.05 },
	fortitude = { name = "Fortitude", desc = "Scales max HP. Increases resist.", startValue = 0, pointCost = 2, hpPerPoint = 8, resistPerPoint = 0.005 },
}
D.STAT_ORDER = {"str","def","spd","wil","bladeMastery","titanAffinity","fortitude"}

D.MAX_LEVEL = 100
D.STAT_POINTS_PER_LEVEL  = 3
D.TRAINING_XP_PER_POINT  = 80

function D.XpToNext(level)
	if level >= D.MAX_LEVEL then return math.huge end
	return math.floor(120 * (level ^ 1.6))
end

function D.SoftCap(val, cap)
	if val <= cap then return val end
	return math.floor(cap + math.sqrt((val - cap) * cap))
end

function D.DayNumber()
	return math.floor(os.time() / 86400)
end

-- ==========================================
-- PRESTIGE PATHS
-- ==========================================
D.PATHS = {
	eldian = { id = "eldian", name = "Eldian", desc = "Titans answer your blood.", requiresPass = false, passives = { titanSynergyMult = 0.15, titanHeatDecay = 5, coordinateUnlock = true } },
	marleyan = { id = "marleyan", name = "Marleyan", desc = "Warriors of Marley.", requiresPass = false, passives = { spearCostMult = 0.75, spearDamageMult = 1.20, antiTitanStrMult = 1.10 } },
	wandering = { id = "wandering", name = "Wandering", desc = "Between walls and nations.", requiresPass = true, passives = { odmMult = 1.25, clanBonusMult = 1.30, evasionCDReduce = 1 } },
	royal = { id = "royal", name = "Royal Blood", desc = "The Reiss line endures.", requiresPass = true, passives = { foundingMult = 1.40, pvpStrMult = 1.15, pvpDefMult = 1.10, maxHpFlatBonus = 200 } },
}

D.PRESTIGE_PER_LEVEL = {
	strFlat = 2, defFlat = 2, spdFlat = 1, wilFlat = 1, bladeMasteryFlat = 1, titanAffinityFlat = 1, fortitudeFlat = 1, xpPct = 0.05, fundsPct = 0.05,
}

function D.GetPrestigePassiveTotals(prestige)
	local p = prestige or 0
	local pl = D.PRESTIGE_PER_LEVEL
	return {
		strFlat = p * pl.strFlat, defFlat = p * pl.defFlat, spdFlat = p * pl.spdFlat, wilFlat = p * pl.wilFlat,
		bladeMasteryFlat = p * pl.bladeMasteryFlat, titanAffinityFlat = p * pl.titanAffinityFlat, fortitudeFlat = p * pl.fortitudeFlat,
		xpPct = p * pl.xpPct, fundsPct = p * pl.fundsPct,
	}
end

-- ==========================================
-- COMBAT MOVES (O(1) Dictionaries)
-- ==========================================
D.MOVES = {
	slash = { id = "slash", name = "Slash", layer = 1, type = "attack", baseDamage = 12, strMult = 1.0, bladeMult = 0.4, accuracy = 0.95, unlockLevel = 1, cooldown = 0 },
	heavy_strike = { id = "heavy_strike", name = "Heavy Strike", layer = 1, type = "attack", baseDamage = 24, strMult = 1.6, accuracy = 0.75, unlockLevel = 5, cooldown = 2 },
	recover = { id = "recover", name = "Recover", layer = 1, type = "heal", healBase = 20, healMult = 1.2, cooldown = 3, unlockLevel = 1 },
	evasive_maneuver = { id = "evasive_maneuver", name = "Evasive Maneuver", layer = 1, type = "evade", baseEvadeChance = 0.70, spdBonusPer10 = 0.03, evadeTurns = 1, cooldown = 4, unlockLevel = 1 },
	retreat = { id = "retreat", name = "Retreat", layer = 1, type = "retreat", cooldown = 0, unlockLevel = 1 },

	spear_strike = { id = "spear_strike", name = "Thunder Spear", layer = 2, type = "attack", baseDamage = 40, strMult = 2.0, accuracy = 0.92, spearCost = 1, pierceDef = true, cooldown = 0, unlockCond = "thunderSpears >= 1", unlockLevel = 10 },
	spear_volley = { id = "spear_volley", name = "Spear Volley", layer = 2, type = "attack", baseDamage = 70, strMult = 3.0, accuracy = 0.85, spearCost = 2, pierceDef = true, cooldown = 3, unlockCond = "thunderSpears >= 2", unlockLevel = 20 },
	odm_dash = { id = "odm_dash", name = "ODM Dash", layer = 2, type = "attack", baseDamage = 18, bladeMult = 1.4, spdMult = 0.3, accuracy = 0.97, partialPierce = 0.25, cooldown = 1, unlockCond = "bladeMastery >= 20", unlockLevel = 1 },
	advanced_slash = { id = "advanced_slash", name = "Advanced Slash", layer = 2, type = "attack", baseDamage = 30, bladeMult = 2.2, accuracy = 0.93, cooldown = 2, unlockCond = "bladeMastery >= 40", unlockLevel = 1 },

	titan_punch = { id = "titan_punch", name = "Titan Fist", layer = 3, type = "titan_attack", baseDamage = 35, strMult = 1.8, affinityMult = 0.3, heatCost = 25, cooldown = 0, unlockCond = "titanShifterMode == true" },
	titan_kick = { id = "titan_kick", name = "Titan Kick", layer = 3, type = "titan_attack", baseDamage = 50, strMult = 2.0, affinityMult = 0.25, heatCost = 30, special = "stun", stunChance = 0.30, cooldown = 2, unlockCond = "titanShifterMode == true" },
	titan_roar = { id = "titan_roar", name = "Titan Roar", layer = 3, type = "titan_buff", buffKey = "nextAttackMult", buffValue = 1.5, wilBonusTurns = 0.1, heatCost = 20, cooldown = 4, unlockCond = "titanShifterMode == true" },
	titan_special = { id = "titan_special", name = "Titan Special", layer = 3, type = "titan_special", heatCost = 40, cooldown = 5, unlockCond = "titanShifterMode == true" },
}

D.CLAN_MOVES = {
	yeager = { id = "yeager_coordinate", name = "Coordinating Scream", type = "clan_active", cooldown = 6, heatCost = 0, effects = {"fear_enemy_2","self_titan_boost_50"}, unlockCond = function(d) return (d.clanTier or 0) >= 2 or (d.prestige or 0) >= 5 end },
	ackerman = { id = "ackerman_surge", name = "Ackerman Awakening", type = "clan_active", bladeMult = 2.8, spdMult = 0.6, baseDamage = 20, trueDamage = true, cooldown = 5, heatCost = 0, effects = {"true_damage"}, unlockCond = function(d) return (d.clanTier or 0) >= 1 end },
	reiss = { id = "reiss_royal_vow", name = "Royal Vow", type = "clan_active", healPct = 0.30, immuneTurns = 3, cooldown = 999, heatCost = 0, effects = {"heal_pct_30","status_immune_3"}, unlockCond = function(d) return (d.clanTier or 0) >= 1 end },
	tybur = { id = "tybur_war_hammer", name = "War Hammer Construct", type = "clan_active", counterDmgMult = 0.8, shieldHits = 2, cooldown = 5, heatCost = 0, effects = {"shield_2_hits","counter_on_absorb"}, unlockCond = function(d) return (d.clanTier or 0) >= 1 end },
}

D.PATH_MOVES = {
	eldian = { id = "eldian_coordinate", name = "The Coordinate", type = "path_active", strMult = 3.5, affinityMult = 0.8, heatCost = 50, cooldown = 8, effects = {"confuse_enemy_1"}, unlockCond = function(d) return (d.prestige or 0) >= 5 end },
	marleyan = { id = "marleyan_barrage", name = "Anti-Titan Barrage", type = "path_active", strMult = 2.5, bladeMult = 1.0, spearCost = 3, pierceDef = true, heatCost = 0, cooldown = 6, effects = {}, unlockCond = function(d) return (d.prestige or 0) >= 3 end },
	wandering = { id = "wandering_ghost_step", name = "Ghost Step", type = "path_active", spdMult = 1.2, bladeMult = 1.5, evadeTurns = 2, guaranteedCrit = true, critMult = 2.0, heatCost = 0, cooldown = 7, effects = {"evade_2","guaranteed_crit"}, unlockCond = function(d) return (d.prestige or 0) >= 2 end },
	royal = { id = "royal_founding_scream", name = "Founding Scream", type = "path_active", wilMult = 1.0, healPct = 0.20, enemyAtkDebuffTurns = 3, enemyAtkDebuffPct = 0.50, heatCost = 0, cooldown = 7, effects = {"enemy_atk_half_3","heal_pct_20"}, unlockCond = function(d) return (d.prestige or 0) >= 2 end },
}

-- O(1) Move Compilation (Instant lookup)
D.ALL_MOVES_MAP = {}
for k, v in pairs(D.MOVES) do D.ALL_MOVES_MAP[k] = v end
for _, v in pairs(D.CLAN_MOVES) do D.ALL_MOVES_MAP[v.id] = v end
for _, v in pairs(D.PATH_MOVES) do D.ALL_MOVES_MAP[v.id] = v end

function D.GetMoveDef(moveId)
	return D.ALL_MOVES_MAP[moveId]
end

function D.GetAvailableMoves(d)
	local moves = {"slash", "heavy_strike", "recover", "evasive_maneuver", "retreat"}

	if (d.thunderSpears or 0) >= 1 then table.insert(moves, "spear_strike") end
	if (d.thunderSpears or 0) >= 2 then table.insert(moves, "spear_volley") end
	if (d.bladeMastery or 0) >= 20 then table.insert(moves, "odm_dash") end
	if (d.bladeMastery or 0) >= 40 then table.insert(moves, "advanced_slash") end

	if d.titanShifterMode and d.clan ~= "ackerman" then
		table.insert(moves, "titan_punch")
		table.insert(moves, "titan_kick")
		table.insert(moves, "titan_roar")
		if d.equippedTitan and d.titanSlots and d.titanSlots[d.equippedTitan] then
			table.insert(moves, "titan_special")
		end
	end

	if d.clan and D.CLAN_MOVES[d.clan] and D.CLAN_MOVES[d.clan].unlockCond(d) then
		table.insert(moves, D.CLAN_MOVES[d.clan].id)
	end

	if d.path and D.PATH_MOVES[d.path] and D.PATH_MOVES[d.path].unlockCond(d) then
		table.insert(moves, D.PATH_MOVES[d.path].id)
	end

	return moves
end

-- ==========================================
-- COMBAT FORMULAS
-- ==========================================
D.TITAN_HEAT_MAX = 100
D.TITAN_HEAT_DECAY = 10
D.TITAN_SUPPRESS_TURNS = 2
D.BASE_HP = 100

function D.GetHeatCost(moveId, titanAffinity)
	local move = D.GetMoveDef(moveId)
	if not move or not move.heatCost then return 0 end
	local reduction = math.floor((titanAffinity or 0) / 10) * 2
	return math.max(5, move.heatCost - reduction)
end

function D.GetAffinitySpecialMult(titanAffinity)
	return 1 + math.floor((titanAffinity or 0) / 10) * 0.05
end

function D.GetEvadeChance(spd)
	return math.min(0.95, D.MOVES.evasive_maneuver.baseEvadeChance + math.floor(spd / 10) * 0.03)
end

function D.GetRecoverHeal(wil, maxHp)
	return math.floor(maxHp * 0.20 + wil * 2.5)
end

function D.IsPierceMove(moveId)
	local def = D.GetMoveDef(moveId)
	return def and (def.pierceDef or def.trueDamage) or false
end

function D.IsTitanAffinityMove(moveId)
	local def = D.GetMoveDef(moveId)
	if not def then return false end
	return def.type == "titan_attack" or def.type == "titan_special" or def.type == "titan_buff" or def.type == "path_active"
end

-- ==========================================
-- TITAN POOL & ATTACKS
-- ==========================================
D.TITAN_PITY_LEGENDARY = 50
D.TITAN_PITY_MYTHICAL  = 200
D.TITAN_LEVEL_MAX = 50
D.TITAN_XP_PER_LEVEL = 500
D.TITAN_RARITY_XP_SCALE = {Rare=1.0, Legendary=1.5, Mythical=2.5}
D.TITAN_STAT_PER_LEVEL = {str=1, def=1, spd=1, wil=1}

D.TITAN_POOL = {
	{id="founding",  name="Founding Titan",   rarity="Mythical",  weight=2, bonus={str=100, wil=80, def=50}},
	{id="warhammer", name="War Hammer Titan",  rarity="Mythical",  weight=4, bonus={str=70,  wil=50}},
	{id="colossal",  name="Colossal Titan",    rarity="Mythical",  weight=4, bonus={str=80,  def=30}},
	{id="attack",    name="Attack Titan",      rarity="Legendary", weight=18, bonus={str=40,  wil=20}},
	{id="armored",   name="Armored Titan",     rarity="Legendary", weight=16, bonus={def=60,  str=20}},
	{id="female",    name="Female Titan",      rarity="Legendary", weight=16, bonus={spd=40,  wil=30}},
	{id="beast",     name="Beast Titan",       rarity="Legendary", weight=16, bonus={str=50,  wil=40}},
	{id="cart",      name="Cart Titan",        rarity="Rare",      weight=450, bonus={spd=30,  def=20}},
	{id="jaw",       name="Jaw Titan",         rarity="Rare",      weight=450, bonus={str=30,  spd=20}},
}

D.TITAN_ATTACKS = {
	founding  = {name="THE COORDINATE",       mult=4.5, special="confuse",    msg="The Coordinate awakens! Reality fractures."},
	warhammer = {name="CRYSTAL LANCE",         mult=3.8, special="pierce",     msg="A crystal lance erupts through all armour!"},
	colossal  = {name="STEAM BURST",           mult=3.5, special="burn",       msg="Boiling steam detonates across the field!"},
	attack    = {name="BATTLE HARDENING",      mult=3.0, special="none",       msg="Attack Titan crystallises and strikes!"},
	armored   = {name="ARMORED CHARGE",        mult=2.8, special="stun",       msg="The Armored Titan plows through defences!"},
	female    = {name="CRYSTAL SHATTER",       mult=2.5, special="lifesteal",  msg="Female Titan shatters into the foe!"},
	beast     = {name="BOULDER VOLLEY",        mult=3.2, special="none",       msg="Beast Titan hurls a massive boulder!"},
	cart      = {name="CANNON BARRAGE",        mult=2.2, special="none",       msg="Cart Titan deploys cannons mid-battle!"},
	jaw       = {name="TITANIUM BITE",         mult=3.4, special="pierce",     msg="Jaw Titan bites through all hardening!"},
	pure      = {name="TITAN GRAB",            mult=1.8, special="none",       msg="The titan lunges with terrifying speed!"},
}

-- ==========================================
-- CLAN POOL
-- ==========================================
D.CLAN_TIER_COSTS = {[0]=0, [1]=3, [2]=8, [3]=20}

D.CLAN_POOL = {
	{id="yeager", name="Yeager", rarity="Legendary", weight=10, tiers = {
		[0] = {bonus={str=12}, traits={"attack_synergy"}},
		[1] = {bonus={str=20, wil=8}, traits={"attack_synergy","freedom_drive"}},
		[2] = {bonus={str=28, wil=14}, traits={"attack_synergy","freedom_drive","titan_special_boost"}},
		[3] = {bonus={str=40, wil=20}, traits={"attack_synergy","freedom_drive","titan_special_boost","rumbling_echo"}},
	}},
	{id="ackerman", name="Ackerman", rarity="Legendary", weight=10, tiers = {
		[0] = {bonus={str=8,  spd=15}, traits={"no_titan","odm_mastery"}},
		[1] = {bonus={str=16, spd=22}, traits={"no_titan","odm_mastery","ackerman_peak"}},
		[2] = {bonus={str=24, spd=30}, traits={"no_titan","odm_mastery","ackerman_peak","killing_reflex"}},
		[3] = {bonus={str=36, spd=42}, traits={"no_titan","odm_mastery","ackerman_peak","killing_reflex","awakening"}},
	}},
	{id="reiss", name="Reiss", rarity="Legendary", weight=8, tiers = {
		[0] = {bonus={wil=15, def=5}, traits={"founding_synergy"}},
		[1] = {bonus={wil=22, def=10}, traits={"founding_synergy","royal_grace"}},
		[2] = {bonus={wil=30, def=16}, traits={"founding_synergy","royal_grace","coordinate_touch"}},
		[3] = {bonus={wil=44, def=24}, traits={"founding_synergy","royal_grace","coordinate_touch","true_king"}},
	}},
	{id="tybur", name="Tybur", rarity="Legendary", weight=8, tiers = {
		[0] = {bonus={str=10, def=10}, traits={"warhammer_synergy"}},
		[1] = {bonus={str=18, def=16}, traits={"warhammer_synergy","crystal_armour"}},
		[2] = {bonus={str=26, def=22}, traits={"warhammer_synergy","crystal_armour","lance_mastery"}},
		[3] = {bonus={str=38, def=32}, traits={"warhammer_synergy","crystal_armour","lance_mastery","world_nobility"}},
	}},
	{id="braun", name="Braun", rarity="Rare", weight=25, tiers = {
		[0] = {bonus={def=14, str=6}, traits={"armored_synergy"}},
		[1] = {bonus={def=22, str=12}, traits={"armored_synergy","iron_skin"}},
		[2] = {bonus={def=30, str=18}, traits={"armored_synergy","iron_skin","shield_slam"}},
		[3] = {bonus={def=44, str=28}, traits={"armored_synergy","iron_skin","shield_slam","unbreakable"}},
	}},
	{id="leonhart", name="Leonhart", rarity="Rare", weight=25, tiers = {
		[0] = {bonus={spd=14, wil=6}, traits={"female_synergy"}},
		[1] = {bonus={spd=22, wil=12}, traits={"female_synergy","crystal_reflex"}},
		[2] = {bonus={spd=30, wil=18}, traits={"female_synergy","crystal_reflex","scream"}},
		[3] = {bonus={spd=44, wil=28}, traits={"female_synhardt","crystal_reflex","scream","apex_predator"}},
	}},
	{id="zoe", name="Zoe", rarity="Rare", weight=30, tiers = {
		[0] = {bonus={wil=10, spd=8}, traits={"survey_bonus"}},
		[1] = {bonus={wil=16, spd=14}, traits={"survey_bonus","field_notes"}},
		[2] = {bonus={wil=22, spd=20}, traits={"survey_bonus","field_notes","test_subject"}},
		[3] = {bonus={wil=32, spd=28}, traits={"survey_bonus","field_notes","test_subject","beautiful"}},
	}},
	{id="springer", name="Springer", rarity="Common", weight=60, tiers = {
		[0] = {bonus={def=6,  spd=6},  traits={"garrison_heart"}},
		[1] = {bonus={def=12, spd=10}, traits={"garrison_heart","stubborn"}},
		[2] = {bonus={def=18, spd=15}, traits={"garrison_heart","stubborn","home_defender"}},
		[3] = {bonus={def=28, spd=22}, traits={"garrison_heart","stubborn","home_defender","never_give_up"}},
	}},
	{id="blouse", name="Blouse", rarity="Common", weight=60, tiers = {
		[0] = {bonus={spd=10, wil=4}, traits={"hunter_instinct"}},
		[1] = {bonus={spd=16, wil=8}, traits={"hunter_instinct","forager"}},
		[2] = {bonus={spd=22, wil=13}, traits={"hunter_instinct","forager","potato_power"}},
		[3] = {bonus={spd=32, wil=20}, traits={"hunter_instinct","forager","potato_power","survival_mode"}},
	}},
	{id="smith", name="Smith", rarity="Common", weight=55, tiers = {
		[0] = {bonus={wil=8,  str=6},  traits={"commanders_will"}},
		[1] = {bonus={wil=14, str=10}, traits={"commanders_will","calculated_risk"}},
		[2] = {bonus={wil=20, str=16}, traits={"commanders_will","calculated_risk","devote_your_hearts"}},
		[3] = {bonus={wil=30, str=24}, traits={"commanders_will","calculated_risk","devote_your_hearts","beyond_the_walls"}},
	}},
}

D.CLAN_TOTAL_WEIGHT = 0
for _, c in ipairs(D.CLAN_POOL) do D.CLAN_TOTAL_WEIGHT = D.CLAN_TOTAL_WEIGHT + c.weight end

function D.RollClan(pity)
	pity = pity or 0
	local forceLegendary = pity >= 80
	local forceRarePlus  = pity >= 30
	local pool = {}
	local totalW = 0
	for _, c in ipairs(D.CLAN_POOL) do
		if forceLegendary and c.rarity ~= "Legendary" then continue end
		if forceRarePlus  and c.rarity == "Common"    then continue end
		table.insert(pool, c)
		totalW = totalW + c.weight
	end
	local roll = math.random() * totalW
	local cum  = 0
	for _, c in ipairs(pool) do
		cum = cum + c.weight
		if roll < cum then return c end
	end
	return pool[#pool]
end

-- ==========================================
-- ITEMS, SETS & ODM GEAR
-- ==========================================
D.FORGE_BONUS_PER_LEVEL = 2
D.FORGE_MAX_LEVEL       = 10
D.FORGE_COST_BASE       = 300

function D.ForgeCost(currentLevel, hasBoost)
	local base = math.floor(D.FORGE_COST_BASE * (1.6 ^ currentLevel))
	return hasBoost and math.floor(base * 0.75) or base
end

D.ITEMS = {
	{id="odm_basic",       name="Standard ODM Gear",     type="weapon", rarity="Common",    bonus={str=4,  spd=2,  bladeMastery=1},                  setGroup="survey"},
	{id="odm_survey",      name="Survey Corps ODM",      type="weapon", rarity="Uncommon",  bonus={str=8,  spd=5,  bladeMastery=3},                  setGroup="survey"},
	{id="odm_elite",       name="Elite ODM Gear",        type="weapon", rarity="Rare",      bonus={str=14, spd=8,  bladeMastery=6},                  setGroup="elite_corps"},
	{id="thunder_blade",   name="Thunder Blade",         type="weapon", rarity="Rare",      bonus={str=16, wil=4,  bladeMastery=4},                  setGroup="thunder"},
	{id="odm_legendary",   name="Legendary ODM Rig",     type="weapon", rarity="Legendary", bonus={str=24, spd=14, bladeMastery=12},                 setGroup="elite_corps"},
	{id="warhammer_spike", name="War Hammer Spike",      type="weapon", rarity="Legendary", bonus={str=30, def=8,  titanAffinity=6},                 setGroup="marley"},
	{id="coordinate_blade",name="Coordinate Blade",      type="weapon", rarity="Mythical",  bonus={str=40, wil=20, spd=10, titanAffinity=14},        setGroup="royal"},
	{id="recruit_uniform", name="Recruit Uniform",       type="armor",  rarity="Common",    bonus={def=4,  fortitude=2},                             setGroup="survey"},
	{id="survey_cloak",    name="Survey Corps Cloak",    type="armor",  rarity="Uncommon",  bonus={def=8,  wil=3,  fortitude=3},                     setGroup="survey"},
	{id="garrison_plate",  name="Garrison Plate",        type="armor",  rarity="Rare",      bonus={def=14, fortitude=8},                             setGroup="garrison"},
	{id="thunder_vest",    name="Thunder Spear Vest",    type="armor",  rarity="Rare",      bonus={def=12, wil=6,  fortitude=5},                     setGroup="thunder"},
	{id="elite_armour",    name="Elite Corps Armour",    type="armor",  rarity="Legendary", bonus={def=22, fortitude=14},                            setGroup="elite_corps"},
	{id="marley_armour",   name="Marleyan Battle Plate", type="armor",  rarity="Legendary", bonus={def=26, str=6,  fortitude=10},                    setGroup="marley"},
	{id="founding_robe",   name="Founding Robe",         type="armor",  rarity="Mythical",  bonus={def=36, wil=18, fortitude=22},                    setGroup="royal"},
	{id="wing_pin",        name="Wings of Freedom Pin",  type="accessory", rarity="Common",    bonus={wil=4,  xpBonus=0.05}},
	{id="survey_badge",    name="Survey Corps Badge",    type="accessory", rarity="Uncommon",  bonus={wil=6,  spd=3,  bladeMastery=2},               setGroup="survey"},
	{id="thunder_harness", name="Thunder Spear Harness", type="accessory", rarity="Rare",      bonus={str=8,  wil=8}},
	{id="ackerman_ring",   name="Ackerman Ring",         type="accessory", rarity="Rare",      bonus={spd=12, str=6,  bladeMastery=8}},
	{id="titan_core",      name="Titan Core Fragment",   type="accessory", rarity="Rare",      bonus={titanAffinity=10, wil=4}},
	{id="reiss_crown",     name="Reiss Crown Fragment",  type="accessory", rarity="Legendary", bonus={wil=20, def=10, fortitude=8},                  setGroup="royal"},
	{id="marley_medal",    name="Marley War Medal",      type="accessory", rarity="Legendary", bonus={str=16, def=12}},
	{id="founders_eye",    name="Founder's Eye",         type="accessory", rarity="Mythical",  bonus={wil=30, str=15, spd=8, titanAffinity=12},      setGroup="royal"},
}

D.ITEM_MAP = {}
for _, item in ipairs(D.ITEMS) do D.ITEM_MAP[item.id] = item end

D.EQUIPMENT_SETS = {
	{name="Survey Corps",    pieces={"odm_survey","survey_cloak","survey_badge"}, twoBonus={wil=8,xpBonus=0.10}, threeBonus={str=10,spd=10,wil=12,xpBonus=0.15}},
	{name="Elite Corps",     pieces={"odm_elite","elite_armour"}, twoBonus={str=14,def=10}},
	{name="Thunder Arsenal", pieces={"thunder_blade","thunder_vest","thunder_harness"}, twoBonus={str=10,wil=8}, threeBonus={str=18,wil=14,spearDamageMult=0.15}},
	{name="Royal Legacy",    pieces={"coordinate_blade","founding_robe","founders_eye"}, twoBonus={wil=20,def=14}, threeBonus={wil=36,def=24,str=16,maxHpBonus=200}},
	{name="Marleyan Warrior",pieces={"warhammer_spike","marley_armour","marley_medal"}, twoBonus={str=16,def=12}, threeBonus={str=28,def=22,spearDamageMult=0.20}},
}

function D.GetSetBonus(weapon, armor, accessory)
	local bonus = {str=0,def=0,spd=0,wil=0,hp=0,xpBonus=0,spearDamageMult=0,maxHpBonus=0}
	local equipped = {weapon, armor, accessory}
	for _, set in ipairs(D.EQUIPMENT_SETS) do
		local matches = 0
		for _, piece in ipairs(set.pieces) do
			for _, e in ipairs(equipped) do if e == piece then matches = matches + 1 break end end
		end
		local b = nil
		if matches >= 3 and set.threeBonus then b = set.threeBonus
		elseif matches >= 2 and set.twoBonus then b = set.twoBonus end
		if b then for k, v in pairs(b) do bonus[k] = (bonus[k] or 0) + v end end
	end
	return bonus
end

D.ODM_UPGRADES = {
	{tier=1, name="Better Blades",         cost=1500,  bonus={str=4}},
	{tier=2, name="Refined Gas Canisters", cost=3500,  bonus={spd=5}},
	{tier=3, name="Reinforced Wires",      cost=7000,  bonus={def=4, spd=3}},
	{tier=4, name="Survey Corps Rig",      cost=15000, bonus={str=8, spd=8}},
	{tier=5, name="Custom Vertical Gear",  cost=30000, bonus={str=14,spd=14,wil=6}},
	{tier=6, name="Legendary ODM Frame",   cost=70000, bonus={str=20,spd=20,def=10,wil=10}},
}

D.SPEAR_RECIPES = {
	{id="spear_basic",  name="Thunder Spear (×5)", yields=5, cost=800, materials={{id="titan_flesh",qty=3},{id="gas_canister",qty=2}}},
	{id="spear_pack",   name="Thunder Spear Pack (×15)", yields=15, cost=2000, materials={{id="titan_flesh",qty=8},{id="gas_canister",qty=5},{id="refined_ore",qty=2}}},
	{id="spear_bundle", name="Thunder Spear Bundle (×30)", yields=30, cost=4500, materials={{id="titan_flesh",qty=15},{id="gas_canister",qty=10},{id="colossal_shard",qty=1}}},
}

-- ==========================================
-- ECONOMY & SHOP
-- ==========================================
D.SHOP_PRICES   = {Common=600, Uncommon=1500, Rare=3500, Legendary=9000, Mythical=28000}
D.SHOP_WEIGHTS  = {Common=40,  Uncommon=28,   Rare=18,   Legendary=8,    Mythical=1}
D.SHOP_SLOTS    = 6
D.SHOP_REROLL_COST = 500

D.PROMO_CODES = {
	ATTACKONTITAN  = {funds=1000, serums=1,  xp=500,  vials=0, active=true},
	SURVEYKORPS    = {funds=2000, serums=2,  xp=1000, vials=0, active=true},
	WALLMARIA      = {funds=500,  serums=0,  xp=0,    vials=2, active=true},
	RUMBLING       = {funds=3000, serums=3,  xp=2000, vials=0, active=true},
	COLOSSAL       = {funds=1500, serums=0,  xp=0,    vials=3, active=true},
	PATHS          = {funds=500,  serums=1,  xp=250,  vials=1, active=true},
}

D.LOGIN_STREAK_REWARDS = {
	[1] = {funds=500,  serums=0, xp=200,  vials=0, label="Day 1 — Welcome back!"},
	[2] = {funds=800,  serums=0, xp=400,  vials=0, label="Day 2 — Keep going!"},
	[3] = {funds=1200, serums=1, xp=600,  vials=0, label="Day 3 — Titan Serum!"},
	[4] = {funds=1500, serums=0, xp=800,  vials=1, label="Day 4 — Blood Vial!"},
	[5] = {funds=2000, serums=1, xp=1000, vials=0, label="Day 5 — Serum + Funds!"},
	[6] = {funds=2500, serums=0, xp=1500, vials=1, label="Day 6 — Almost there!"},
	[7] = {funds=6000, serums=2, xp=3000, vials=2, label="Day 7 — FULL STREAK BONUS!"},
}
D.LOGIN_STREAK_VIP_BONUS = {funds=500, serums=1, xp=500, vials=0}

-- ==========================================
-- BOSS MECHANICS
-- ==========================================
D.BOSS_MECHANICS = {
	crystal_hardening = { id = "crystal_hardening", name = "Crystal Hardening", activatesAtPhase = 2, activeByDefault = false, announcement = "Annie hardens her crystal armour!", shatterMsg = "A pierce strike shatters the hardening!", damageReductionPct = 0.60, pierceBreakChance = 0.30 },
	nape_armor = { id = "nape_armor", name = "Armored Nape", activatesAtPhase = 1, activeByDefault = true, announcement = "Reiner's armour is impenetrable. Break through!", shatterMsg = "The armour CRACKS!", damageReductionPct = 0.70, armorHp = 500, heavyStreakBonus = 2.0 },
	boulder_barrage = { id = "boulder_barrage", name = "Boulder Barrage", activatesAtPhase = 1, activeByDefault = true, announcement = "The Beast Titan readies a boulder. BRACE FOR IMPACT!", barrageInterval = 3, barrageDamageMult = 2.0, inflictsSlowTurns = 2, evadeChanceBonus = 0.15, fortitudeSlowReduce = 0.1 },
	steam_release = { id = "steam_release", name = "Steam Release", activatesAtPhase = 2, activeByDefault = false, announcement = "The Colossal Titan vents scalding steam!", steamDmgReductionPct = 0.80, steamBurnPct = 0.08, wilBurnReductePer10 = 0.01 },
	crystal_construct = { id = "crystal_construct", name = "Crystal Construct", activatesAtPhase = 2, activeByDefault = false, announcement = "Lara Tybur raises a crystal construct!", shatterMsg = "The crystal SHATTERS!", barrierHp = 2000, titanAffinityDamageMult = 2.0, coordinateDamageMult = 3.0 },
	coordinate_authority = { id = "coordinate_authority", name = "Coordinate Authority", activatesAtPhase = 3, activeByDefault = false, announcement = "The Founding Titan's authority warps reality!", statusCycle = {"bleed", "slow", "fear"}, statusDuration = 2, reflectChance = 0.20, reflectPct = 0.50, fortitudeStatusReduce = 0.05 },
}

-- ==========================================
-- CAMPAIGN, RAIDS & ENEMIES
-- ==========================================
D.CAMPAIGN = {
	{id="ch1", name="The Fall of Wall Maria", desc="Wall Maria is breached.", unlockPrestige=0, enemies={
		{name="5M Pure Titan", hp=120, atk=14, xp=28, funds=14, tier="weak"},
		{name="8M Rogue Titan", hp=200, atk=22, xp=50, funds=25, tier="weak"},
		{name="10M Titan", hp=300, atk=30, xp=75, funds=38, tier="medium"},
		{name="Titan Pair", hp=420, atk=38, xp=100, funds=55, tier="medium"},
		{name="12M Aberrant", hp=580, atk=46, xp=140, funds=80, tier="medium", behavior="aberrant"},
		{name="Titan Vanguard", hp=750, atk=55, xp=180, funds=110, tier="strong"},
		{name="COLOSSAL TITAN", hp=1200, atk=90, xp=600, funds=400, tier="boss", isBoss=true, regen=60, bossBonus=200, behavior="telegraph", titanId="colossal", drops={"titan_flesh","colossal_shard"}, phases={[2]={hpThreshold=0.60, atkMult=1.25, regenMult=1.20, msg="The Colossal Titan bellows!"}, [3]={hpThreshold=0.30, atkMult=1.20, msg="The Colossal Titan rears back!"}}},
	}},
	{id="ch2", name="Wall Rose Breach", desc="Titans appear inside Wall Rose.", unlockPrestige=0, enemies={
		{name="10M Aberrant", hp=500, atk=44, xp=130, funds=75, tier="medium", behavior="aberrant"},
		{name="10M Crawler", hp=500, atk=44, xp=130, funds=75, tier="medium", behavior="crawler"},
		{name="12M Titan", hp=800, atk=58, xp=200, funds=120, tier="strong"},
		{name="14M Titan", hp=1000, atk=68, xp=250, funds=150, tier="strong"},
		{name="Garrison Captain", hp=900, atk=62, xp=220, funds=140, tier="strong"},
		{name="FEMALE TITAN", hp=3200, atk=105, xp=900, funds=600, tier="boss", isBoss=true, regen=90, bossBonus=300, behavior="telegraph", titanId="female", drops={"titan_flesh","gas_canister","odm_elite"}, mechanic="crystal_hardening", phases={[2]={hpThreshold=0.60, atkMult=1.20, regenMult=1.15, msg="Annie crystallises!", activateMechanic=true}, [3]={hpThreshold=0.30, atkMult=1.25, msg="She roars and reinforces the hardening!"}}},
	}},
	{id="ch3", name="Forest of Giant Trees", desc="Survey Corps territory.", unlockPrestige=0, enemies={
		{name="15M Titan", hp=1100, atk=72, xp=280, funds=170, tier="strong"},
		{name="Titan Patrol", hp=1400, atk=82, xp=360, funds=210, tier="strong"},
		{name="Armoured Scout", hp=1800, atk=92, xp=420, funds=260, tier="strong", behavior="armored"},
		{name="Titan Commander", hp=2800, atk=115, xp=600, funds=370, tier="boss", regen=100},
		{name="BEAST TITAN", hp=5500, atk=145, xp=1600, funds=1000, tier="boss", isBoss=true, regen=140, bossBonus=500, behavior="telegraph", titanId="beast", drops={"titan_flesh","refined_ore","beast_core"}, mechanic="boulder_barrage", phases={[2]={hpThreshold=0.60, atkMult=1.20, regenMult=1.15, msg="Zeke roars!"}, [3]={hpThreshold=0.30, atkMult=1.25, msg="Zeke screams in fury!"}}},
	}},
	{id="ch4", name="Assault on Stohess", desc="Chaos inside Wall Sina.", unlockPrestige=0, enemies={
		{name="Military Police", hp=1800, atk=95, xp=460, funds=290, tier="strong"},
		{name="MP Elite", hp=2200, atk=105, xp=520, funds=320, tier="strong"},
		{name="Crystal Titan", hp=3500, atk=120, xp=800, funds=500, tier="boss", regen=120, behavior="armored"},
		{name="ARMORED TITAN", hp=9000, atk=190, xp=2800, funds=1800, tier="boss", isBoss=true, regen=200, bossBonus=800, behavior="telegraph", titanId="armored", drops={"titan_flesh","refined_ore","armored_plate","garrison_plate"}, mechanic="nape_armor", phases={[2]={hpThreshold=0.60, atkMult=1.20, msg="Reiner's armour glows red-hot!"}, [3]={hpThreshold=0.30, atkMult=1.30, regenMult=1.20, msg="Reiner charges!"}}},
	}},
	{id="ch5", name="Retaking Wall Maria", desc="The final march to Shiganshina.", unlockPrestige=0, enemies={
		{name="Titan Horde", hp=4000, atk=130, xp=900, funds=600, tier="strong"},
		{name="Gate Titan", hp=5500, atk=150, xp=1100, funds=700, tier="boss", regen=160, behavior="armored"},
		{name="Wall Sentinel", hp=6500, atk=165, xp=1300, funds=820, tier="boss", regen=180},
		{name="COLOSSAL TITAN II", hp=16000, atk=260, xp=5000, funds=3000, tier="boss", isBoss=true, regen=320, bossBonus=1500, behavior="telegraph", titanId="colossal", drops={"colossal_shard","refined_ore","odm_legendary"}, mechanic="steam_release", phases={[2]={hpThreshold=0.50, atkMult=1.20, regenMult=1.15, msg="The Colossal Titan vents steam!", activateMechanic=true}, [3]={hpThreshold=0.25, atkMult=1.25, msg="Steam fills the entire arena!"}}},
	}},
	{id="ch6", name="The War for Paradis", desc="Marleyan forces land.", unlockPrestige=1, enemies={
		{name="Marleyan Soldier", hp=8000, atk=180, xp=1800, funds=1100, tier="strong"},
		{name="Thunder Squad", hp=11000, atk=210, xp=2400, funds=1500, tier="strong"},
		{name="Titan Knight", hp=15000, atk=230, xp=2800, funds=1700, tier="boss", regen=250},
		{name="WARHAMMER TITAN", hp=35000, atk=340, xp=8000, funds=5000, tier="boss", isBoss=true, regen=600, bossBonus=3000, behavior="telegraph", titanId="warhammer", drops={"warhammer_frag","war_hammer_spike","refined_ore"}, mechanic="crystal_construct", phases={[2]={hpThreshold=0.65, atkMult=1.20, msg="Lara retreats into a crystal construct!", activateMechanic=true}, [3]={hpThreshold=0.30, atkMult=1.30, regenMult=1.25, msg="The War Hammer Titan fights back!"}}},
	}},
	{id="ch7", name="The Rumbling Begins", desc="Wall Titans march on the world.", unlockPrestige=2, enemies={
		{name="Wall Titan", hp=18000, atk=240, xp=3200, funds=2000, tier="strong"},
		{name="Titan Battalion", hp=25000, atk=270, xp=4500, funds=2800, tier="strong"},
		{name="Elder Wall Titan", hp=35000, atk=310, xp=6000, funds=3800, tier="boss", regen=500, behavior="armored"},
		{name="FOUNDING TITAN", hp=80000, atk=480, xp=18000, funds=12000, tier="boss", isBoss=true, regen=1200, bossBonus=8000, behavior="telegraph", titanId="founding", drops={"founding_relic","coordinate_blade","founders_eye"}, mechanic="coordinate_authority", phases={[2]={hpThreshold=0.60, atkMult=1.25, regenMult=1.20, msg="The Founding Titan's power surges!"}, [3]={hpThreshold=0.30, atkMult=1.30, msg="The Coordinate activates!", activateMechanic=true}}},
	}},
	{id="ch8", name="The Battle of Heaven and Earth", desc="The Alliance makes its final stand.", unlockPrestige=3, enemies={
		{name="Yeagerist Vanguard", hp=28000, atk=300, xp=5000, funds=3200, tier="strong"},
		{name="Pure Titan Wave", hp=32000, atk=320, xp=5800, funds=3600, tier="strong", behavior="aberrant"},
		{name="Armored Wall Titan", hp=45000, atk=370, xp=8000, funds=5000, tier="boss", regen=700, behavior="armored"},
		{name="EREN — FOUNDING", hp=150000, atk=600, xp=30000, funds=20000, tier="boss", isBoss=true, regen=2000, bossBonus=15000, behavior="telegraph", titanId="founding", drops={"founders_eye","founding_relic","coordinate_blade","founding_robe"}, mechanic="coordinate_authority", mechanicPhase2="crystal_hardening", phases={[2]={hpThreshold=0.65, atkMult=1.20, regenMult=1.15, msg="Eren hardens!", activateMechanic=true, activateMechanic2=true}, [3]={hpThreshold=0.30, atkMult=1.30, regenMult=1.20, msg="FINAL FORM!"}}},
	}},
}

function D.ScaleCampaignEnemy(enemy, prestige)
	if not enemy or (prestige or 0) == 0 then return enemy end
	local scale = 1 + prestige * 0.20
	local e = {}
	for k, v in pairs(enemy) do e[k] = v end
	e.hp    = math.floor((enemy.hp    or 0) * scale)
	e.atk   = math.floor((enemy.atk   or 0) * scale)
	e.xp    = math.floor((enemy.xp    or 0) * scale)
	e.funds = math.floor((enemy.funds or 0) * scale)
	if enemy.regen     then e.regen     = math.floor(enemy.regen     * scale) end
	if enemy.bossBonus then e.bossBonus = math.floor(enemy.bossBonus * scale) end
	return e
end

D.RAIDS = {
	{id="raid_female",   name="Female Titan Raid",    titanId="female", desc="The Armored Female Titan rampages.", baseHp=8000,  baseAtk=160, xp=2000,  funds=1200, regen=200, unlockChapter=2, behavior="armored", drops={"titan_flesh","odm_elite","leonhart_ring"}},
	{id="raid_beast",    name="Beast Titan Raid",     titanId="beast", desc="The Beast Titan hurls boulders.", baseHp=14000, baseAtk=220, xp=3500,  funds=2000, regen=350, unlockChapter=3, behavior="telegraph", drops={"beast_core","refined_ore","odm_legendary"}},
	{id="raid_armored",  name="Armored Titan Raid",   titanId="armored", desc="Armored Titan charges.", baseHp=22000, baseAtk=290, xp=5500,  funds=3200, regen=500, unlockChapter=4, behavior="armored", drops={"armored_plate","elite_armour","marley_medal"}},
	{id="raid_colossal", name="Colossal Titan Raid",  titanId="colossal", desc="The Colossal Titan emerges.", baseHp=40000, baseAtk=380, xp=9000,  funds=5500, regen=800, unlockChapter=5, behavior="telegraph", drops={"colossal_shard","odm_legendary","thunder_harness"}},
	{id="raid_jaw",      name="Jaw Titan Raid",       titanId="jaw", desc="The Jaw Titan strikes.", baseHp=18000, baseAtk=250, xp=4500,  funds=2800, regen=300, unlockChapter=3, drops={"titan_flesh","gas_canister","ackerman_ring"}},
	{id="raid_warhammer",name="War Hammer Raid",      titanId="warhammer", desc="Crystalline lances erupt.", baseHp=55000, baseAtk=420, xp=14000, funds=9000, regen=900, unlockChapter=6, behavior="telegraph", drops={"warhammer_frag","warhammer_spike","tybur_seal"}},
	{id="raid_founding", name="Founding Titan Siege", titanId="founding", desc="The Founding Titan's power.", baseHp=120000,baseAtk=600, xp=25000, funds=16000,regen=2000, unlockChapter=7, behavior="telegraph", drops={"founding_relic","coordinate_blade","founders_eye","founding_robe"}},
}

function D.ScaleRaid(raid, partySize, avgPrestige)
	local ps = math.max(1, partySize or 1)
	local pr = math.max(0, avgPrestige or 0)
	local hpMult  = 1 + (ps - 1) * 0.70
	local atkMult = 1 + pr * 0.18
	return {
		hp    = math.floor(raid.baseHp  * hpMult * (1 + pr * 0.15)),
		atk   = math.floor(raid.baseAtk * atkMult),
		regen = math.floor((raid.regen or 0) * (1 + pr * 0.10)),
	}
end

D.DROP_TABLES = {
	weak = {{id="titan_flesh", chance=0.40}, {id="gas_canister", chance=0.20}, {id="recruit_uniform",chance=0.08}, {id="odm_basic", chance=0.05}, {id="wing_pin", chance=0.05}},
	medium = {{id="titan_flesh", chance=0.35}, {id="gas_canister", chance=0.20}, {id="refined_ore", chance=0.12}, {id="odm_survey", chance=0.08}, {id="survey_cloak", chance=0.06}, {id="survey_badge", chance=0.04}},
	strong = {{id="titan_flesh", chance=0.30}, {id="refined_ore", chance=0.18}, {id="gas_canister", chance=0.12}, {id="odm_elite", chance=0.08}, {id="garrison_plate",chance=0.06}, {id="thunder_blade", chance=0.04}, {id="thunder_vest", chance=0.03}},
	boss = {{id="refined_ore", chance=0.25}, {id="colossal_shard",chance=0.12}, {id="odm_legendary", chance=0.08}, {id="elite_armour", chance=0.08}, {id="thunder_harness",chance=0.06}, {id="reiss_crown", chance=0.04}, {id="marley_medal", chance=0.04}, {id="founding_relic",chance=0.02}},
}

function D.RollDrop(tier)
	local tbl = D.DROP_TABLES[tier] or D.DROP_TABLES.weak
	local roll = math.random()
	local cum  = 0
	for _, e in ipairs(tbl) do
		cum = cum + (e.chance or 0)
		if roll < cum then return e.id end
	end
	return nil
end

D.BEHAVIORS = { default = "default", aberrant = "aberrant", crawler = "crawler", armored = "armored", telegraph = "telegraph" }

-- ==========================================
-- ENDLESS & ACHIEVEMENTS
-- ==========================================
function D.EndlessEnemy(floor, prestige)
	prestige = prestige or 0
	local scale   = 1 + (floor - 1) * 0.18 + prestige * 0.25 + math.max(0, floor - 30) * 0.05
	local isBoss  = (floor % 10 == 0)
	local behav   = isBoss and (floor % 20 == 0 and "telegraph" or floor % 30 == 0 and "armored" or nil) or (floor % 3 == 0 and "aberrant" or floor % 5 == 0 and "crawler" or nil)
	return {
		name      = isBoss and ("FLOOR " .. floor .. " TITAN") or ("Floor " .. floor .. " Titan"),
		hp        = math.floor((isBoss and 4000 or 800) * scale),
		atk       = math.floor((isBoss and 120  or 40)  * scale),
		xp        = math.floor((isBoss and 800  or 160) * scale),
		funds     = math.floor((isBoss and 500  or 100) * scale),
		regen     = isBoss and math.floor(200 * scale) or nil,
		isBoss    = isBoss, tier = isBoss and "boss" or "medium",
		bossBonus = isBoss and math.floor(200 * scale) or nil,
		behavior  = behav, isEndless = true, floor = floor,
	}
end

D.ACHIEVEMENTS = {
	{id="first_blood", label="First Blood", track="totalKills", goal=1, reward={xp=100}},
	{id="soldier", label="Soldier", track="totalKills", goal=50, reward={xp=500, funds=1000}},
	{id="veteran", label="Veteran", track="totalKills", goal=500, reward={serums=1, funds=3000}},
	{id="titan_slayer", label="Titan Slayer", track="totalKills", goal=2000, reward={serums=2, vials=1}},
	{id="boss_hunter", label="Boss Hunter", track="bossKills", goal=10, reward={serums=1, funds=2000}},
	{id="boss_master", label="Boss Master", track="bossKills", goal=50, reward={serums=3, vials=1}},
	{id="first_prestige", label="Beyond the Walls", track="prestige", goal=1, reward={serums=2, vials=2, funds=5000}},
	{id="paths_chosen", label="The Paths", track="prestige", goal=2, reward={serums=3, vials=3}},
	{id="rumbling", label="The Rumbling", track="prestige", goal=5, reward={serums=5, vials=5, funds=20000}},
	{id="pvp_debut", label="PvP Debut", track="pvpWins", goal=1, reward={funds=500}},
	{id="pvp_champion", label="PvP Champion", track="pvpWins", goal=25, reward={serums=2, funds=5000}},
	{id="streak_5", label="Kill Streak", track="bestStreak", goal=5, reward={funds=500}},
	{id="streak_20", label="Unstoppable", track="bestStreak", goal=20, reward={serums=1, funds=2000}},
	{id="titan_master", label="Titan Master", track="titanFusions", goal=3, reward={serums=2}},
	{id="max_level", label="Survey Corps Elite", track="level", goal=100, reward={serums=2, vials=2, funds=10000}},
}

D.PVP_STARTING_ELO    = 1000
D.PVP_ELO_WIN_BASE    = 25
D.PVP_ELO_LOSS_BASE   = 20
D.PVP_MAX_TURNS       = 20
D.PVP_INVITE_TIMEOUT  = 30

function D.CalcEloChange(myElo, oppElo, won)
	local expected = 1 / (1 + 10 ^ ((oppElo - myElo) / 400))
	local k = 32
	local change = math.floor(k * ((won and 1 or 0) - expected))
	return math.max(-40, math.min(40, change))
end

D.PRESTIGE_TITLES = { [0]="Recruit", [1]="Survey Corps", [2]="Veteran Soldier", [3]="Titan Hunter", [4]="Wall Defender", [5]="Survey Elite", [6]="Titan Slayer", [7]="Corps Legend", [8]="Paths Walker", [9]="Rumbling Survivor", [10]="Founding Blood" }

function D.GetPrestigeTitle(prestige)
	return D.PRESTIGE_TITLES[prestige] or ("Prestige " .. prestige)
end

D.DAILY_CHALLENGES = {
	{id="dc_kills_10", label="Titan Patrol", type="kill", goal=10, reward={xp=800, funds=500}},
	{id="dc_kills_25", label="Extermination", type="kill", goal=25, reward={xp=1500, funds=1000}},
	{id="dc_boss_1", label="Hunt the Aberrant", type="bossKill", goal=1, reward={xp=2000, funds=1500, serums=1}},
	{id="dc_spears_5", label="Thunder Volley", type="spearUse", goal=5, reward={xp=1000, funds=800}},
	{id="dc_streak_10", label="Killing Streak", type="streak", goal=10, reward={xp=1200, funds=900}},
	{id="dc_titan_shift", label="Titan Awakening", type="titanShift", goal=3, reward={xp=1000, funds=600}},
}

D.WEEKLY_CHALLENGES = {
	{id="wc_kills_200", label="Corpse Counter", type="kill", goal=200, reward={serums=2, vials=1, funds=5000}},
	{id="wc_boss_10", label="Boss Rush", type="bossKill", goal=10, reward={serums=3, funds=8000}},
	{id="wc_prestige", label="The Paths", type="prestige", goal=1, reward={serums=5, vials=3, funds=15000}},
	{id="wc_pvp_5", label="Blood Sport", type="pvpWin", goal=5, reward={serums=2, vials=2, funds=6000}},
	{id="wc_raid_3", label="Raid Veteran", type="raidClear", goal=3, reward={serums=4, vials=2, funds=10000}},
}

function D.GetActiveChallenges(dayNumber)
	local dSeed    = dayNumber % #D.DAILY_CHALLENGES
	local dailies  = {}
	for i = 1, math.min(3, #D.DAILY_CHALLENGES) do
		local idx = (dSeed + i - 1) % #D.DAILY_CHALLENGES + 1
		table.insert(dailies, D.DAILY_CHALLENGES[idx])
	end
	local wSeed    = math.floor(dayNumber / 7) % #D.WEEKLY_CHALLENGES
	local weeklies = {}
	for i = 1, math.min(2, #D.WEEKLY_CHALLENGES) do
		local idx = (wSeed + i - 1) % #D.WEEKLY_CHALLENGES + 1
		table.insert(weeklies, D.WEEKLY_CHALLENGES[idx])
	end
	return dailies, weeklies
end

D.ADMIN_IDS = {}

D.UPDATE_LOG = {
	{version="1.1.0", date="2026", entries={
		"AOT Incremental Complete O(1) Rebuild",
		"Optimized backend data arrays",
		"Anti-Exploit move execution added",
	}},
}

return D