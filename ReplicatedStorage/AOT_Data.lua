-- @ScriptType: ModuleScript
-- AOT_Data  (ModuleScript)
-- Place in: ReplicatedStorage > AOT > AOT_Data
-- Pure constants and pure helper functions only.
-- No side effects. Safe to require on server AND client.
-- v1.0.0

local D = {}

-- ────────────────────────────────────────────────────────────
-- SCHEMA VERSION
-- Bump this when Blank() fields are added/renamed.
-- AOT_Sessions.Load() migrates saves that have a lower version.
-- ────────────────────────────────────────────────────────────
D.SCHEMA_VERSION  = 2
D.DATASTORE_KEY   = "AOT_v1_"   -- prefix + userId
D.GAME_VERSION    = "1.0.0"

-- ────────────────────────────────────────────────────────────
-- MONETISATION IDs  (replace 0 with real IDs before publishing)
-- ────────────────────────────────────────────────────────────
D.GP_VIP          = 0   -- 2× XP/funds, daily clan vial reroll, badge
D.GP_PATHS        = 0   -- unlocks Wandering + Royal paths (free gets Eldian/Marleyan)
D.GP_AUTOTRAIN    = 0   -- offline training gains, +20 XP per kill
D.GP_VAULT        = 0   -- titan slots 4 → 8, weekly serum + vial
D.GP_ARSENAL      = 0   -- thunder spear craft cost ÷2, start each mission with 2 spears

D.DP_FUNDS_SM     = 0   --   5 000 funds
D.DP_FUNDS_MD     = 0   --  25 000 funds
D.DP_FUNDS_LG     = 0   -- 100 000 funds
D.DP_SERUMS_1     = 0   -- 1 titan serum
D.DP_SERUMS_5     = 0   -- 5 titan serums
D.DP_VIALS_1      = 0   -- 1 blood vial
D.DP_VIALS_5      = 0   -- 5 blood vials
D.DP_SPEARS_10    = 0   -- 10 thunder spears
D.DP_BOOST_24H    = 0   -- 24-hour 2× XP+funds boost

-- ────────────────────────────────────────────────────────────
-- STAT DEFINITIONS
-- Seven stats. Each entry describes what the stat does and
-- what it gates so the rest of the codebase has one truth source.
-- ────────────────────────────────────────────────────────────
D.STATS = {
	str = {
		name        = "Strength",
		desc        = "Base melee damage. Scales slash, heavy strike, and titan punches.",
		startValue  = 5,
		pointCost   = 1,
		scaledBy    = {"slash","heavy_strike","titan_punch","titan_kick","titan_special"},
	},
	def = {
		name        = "Defense",
		desc        = "Flat damage reduction each hit. Also scales passive HP regen between fights.",
		startValue  = 5,
		pointCost   = 1,
		scaledBy    = {"damage_reduction"},
	},
	spd = {
		name        = "Speed",
		desc        = "Evasion success chance on Evasive Maneuver. Determines PvP turn order.",
		startValue  = 5,
		pointCost   = 1,
		scaledBy    = {"evasive_maneuver","pvp_turn_order"},
	},
	wil = {
		name        = "Willpower",
		desc        = "Recover heal strength. Titan heat decay bonus. Status effect resist chance.",
		startValue  = 5,
		pointCost   = 1,
		scaledBy    = {"recover","titan_heat_decay","status_resist"},
	},
	bladeMastery = {
		name        = "Blade Mastery",
		desc        = "ODM gear damage multiplier. Unlocks ODM Dash at 20 and Advanced Slash at 40.",
		startValue  = 0,
		pointCost   = 2,   -- costs 2 stat points per rank (rarer resource)
		scaledBy    = {"slash","odm_dash","advanced_slash","clan_ackerman"},
		unlocks     = {
			[20] = "odm_dash",
			[40] = "advanced_slash",
		},
	},
	titanAffinity = {
		name        = "Titan Affinity",
		desc        = "Reduces heat cost per titan action. Amplifies titan special move damage.",
		startValue  = 0,
		pointCost   = 2,
		scaledBy    = {"titan_punch","titan_kick","titan_roar","titan_special"},
		heatCostReductionPer10 = 2,    -- -2 heat cost per titan action per 10 affinity
		specialDmgPer10        = 0.05, -- +5% titan special damage per 10 affinity
	},
	fortitude = {
		name        = "Fortitude",
		desc        = "Scales max HP. Each point adds HP and increases bleed/slow/fear resist.",
		startValue  = 0,
		pointCost   = 2,
		scaledBy    = {"max_hp","status_resist"},
		hpPerPoint  = 8,               -- each fortitude adds 8 max HP (before prestige mult)
		resistPerPoint = 0.005,        -- 0.5% resist per point (cap 50%)
	},
}

-- Convenience: stat ids in display order
D.STAT_ORDER = {"str","def","spd","wil","bladeMastery","titanAffinity","fortitude"}

-- ────────────────────────────────────────────────────────────
-- LEVEL / XP
-- ────────────────────────────────────────────────────────────
D.MAX_LEVEL = 100

-- XP required to reach `level` from level-1.
-- Formula: floor(120 * level^1.6)
-- Level 1 → 120   Level 10 → 3017   Level 50 → 84853   Level 100 → 478,706
function D.XpToNext(level)
	if level >= D.MAX_LEVEL then return math.huge end
	return math.floor(120 * (level ^ 1.6))
end

-- Stat points awarded on level-up
D.STAT_POINTS_PER_LEVEL  = 3
-- Training XP cost to gain 1 stat point via the training menu
D.TRAINING_XP_PER_POINT  = 80

-- ────────────────────────────────────────────────────────────
-- SOFTCAP
-- Used in CalcCS to prevent single-stat stacking.
-- ────────────────────────────────────────────────────────────
function D.SoftCap(val, cap)
	if val <= cap then return val end
	return math.floor(cap + math.sqrt((val - cap) * cap))
end

-- ────────────────────────────────────────────────────────────
-- DAY NUMBER  (UTC days since epoch, used for daily resets)
-- ────────────────────────────────────────────────────────────
function D.DayNumber()
	return math.floor(os.time() / 86400)
end

-- ────────────────────────────────────────────────────────────
-- PRESTIGE PATHS
-- Paths are chosen once per prestige at the reset screen.
-- Free players may only choose Eldian or Marleyan.
-- GP_PATHS unlocks Wandering and Royal.
-- ────────────────────────────────────────────────────────────
D.PATHS = {
	eldian = {
		id          = "eldian",
		name        = "Eldian",
		desc        = "Titans answer your blood. Titan synergy and coordinate power.",
		requiresPass= false,
		passives    = {
			titanSynergyMult  = 0.15,  -- +15% to all equipped titan bonuses
			titanHeatDecay    = 5,     -- extra heat decay per turn
			coordinateUnlock  = true,  -- access to Coordinate special at prestige 5+
		},
	},
	marleyan = {
		id          = "marleyan",
		name        = "Marleyan",
		desc        = "Warriors of Marley. Thunder spear mastery and anti-titan weapons.",
		requiresPass= false,
		passives    = {
			spearCostMult     = 0.75,  -- thunder spear crafting costs 25% less
			spearDamageMult   = 1.20,  -- thunder spear damage ×1.2
			antiTitanStrMult  = 1.10,  -- str bonus vs titan enemies ×1.1
		},
	},
	wandering = {
		id          = "wandering",
		name        = "Wandering",
		desc        = "Between walls and nations. ODM mastery and clan amplification.",
		requiresPass= true,
		passives    = {
			odmMult           = 1.25,  -- ODM gear bonuses ×1.25
			clanBonusMult     = 1.30,  -- clan stat bonuses ×1.3
			evasionCDReduce   = 1,     -- evasive maneuver cooldown -1 turn
		},
	},
	royal = {
		id          = "royal",
		name        = "Royal Blood",
		desc        = "The Reiss line endures. Founding synergy and PvP supremacy.",
		requiresPass= true,
		passives    = {
			foundingMult      = 1.40,  -- Founding Titan bonuses ×1.4
			pvpStrMult        = 1.15,  -- PvP damage dealt ×1.15
			pvpDefMult        = 1.10,  -- PvP damage taken ×0.9
			maxHpFlatBonus    = 200,   -- +200 max HP
		},
	},
}

-- Per-prestige stacking bonuses (apply regardless of path).
-- Index = prestige level (0 = no bonus).
-- Values are additive each prestige.
D.PRESTIGE_PER_LEVEL = {
	strFlat          = 2,    -- +2 STR per prestige
	defFlat          = 2,    -- +2 DEF per prestige
	spdFlat          = 1,    -- +1 SPD per prestige
	wilFlat          = 1,    -- +1 WIL per prestige
	bladeMasteryFlat = 1,    -- +1 Blade Mastery per prestige
	titanAffinityFlat= 1,    -- +1 Titan Affinity per prestige
	fortitudeFlat    = 1,    -- +1 Fortitude per prestige
	xpPct            = 0.05, -- +5% XP per prestige
	fundsPct         = 0.05, -- +5% funds per prestige
}

function D.GetPrestigePassiveTotals(prestige)
	local p = prestige or 0
	local pl = D.PRESTIGE_PER_LEVEL
	return {
		strFlat           = p * pl.strFlat,
		defFlat           = p * pl.defFlat,
		spdFlat           = p * pl.spdFlat,
		wilFlat           = p * pl.wilFlat,
		bladeMasteryFlat  = p * pl.bladeMasteryFlat,
		titanAffinityFlat = p * pl.titanAffinityFlat,
		fortitudeFlat     = p * pl.fortitudeFlat,
		xpPct             = p * pl.xpPct,
		fundsPct          = p * pl.fundsPct,
	}
end

-- ────────────────────────────────────────────────────────────
-- COMBAT MOVES
-- Used by the client for button display and server for validation.
-- ────────────────────────────────────────────────────────────
D.MOVES = {
	-- ── Layer 1: base moveset (always available) ──────────────
	slash = {
		id          = "slash",
		name        = "Slash",
		desc        = "A precise ODM blade strike. Damage scales with STR + Blade Mastery.",
		layer       = 1,
		type        = "attack",
		statKeys    = {"str","bladeMastery"},  -- both contribute
		strMult     = 1.0,
		bladeMult   = 0.4,   -- bladeMastery adds 40% of its value to damage
		baseDamage  = 12,
		cooldown    = 0,
		accuracy    = 0.95,
		unlockLevel = 1,
	},
	heavy_strike = {
		id          = "heavy_strike",
		name        = "Heavy Strike",
		desc        = "Powerful overhead blow. High risk, high reward.",
		layer       = 1,
		type        = "attack",
		statKeys    = {"str"},
		strMult     = 1.6,
		baseDamage  = 24,
		cooldown    = 2,
		accuracy    = 0.75,
		unlockLevel = 5,
	},
	recover = {
		id          = "recover",
		name        = "Recover",
		desc        = "Bind wounds. Heals based on WIL. Fortitude extends the window before bleed ticks.",
		layer       = 1,
		type        = "heal",
		statKeys    = {"wil"},
		healBase    = 20,
		healMult    = 1.2,
		cooldown    = 3,
		unlockLevel = 1,
	},
	evasive_maneuver = {
		id          = "evasive_maneuver",
		name        = "Evasive Maneuver",
		desc        = "Fire ODM gas and dodge the next attack. Success chance scales with SPD.",
		layer       = 1,
		type        = "evade",
		statKeys    = {"spd"},
		baseEvadeChance = 0.70,         -- base 70% block chance
		spdBonusPer10   = 0.03,         -- +3% per 10 SPD (cap 95%)
		evadeTurns  = 1,
		cooldown    = 4,
		unlockLevel = 1,
	},
	retreat = {
		id          = "retreat",
		name        = "Retreat",
		desc        = "Abandon the mission. No rewards.",
		layer       = 1,
		type        = "retreat",
		cooldown    = 0,
		unlockLevel = 1,
	},

	-- ── Layer 2: unlocked moves ────────────────────────────────
	spear_strike = {
		id          = "spear_strike",
		name        = "Thunder Spear",
		desc        = "Detonate a thunder spear. Pierces armour. Scales STR + Marleyan path.",
		layer       = 2,
		type        = "attack",
		statKeys    = {"str"},
		strMult     = 2.0,
		baseDamage  = 40,
		cooldown    = 0,
		accuracy    = 0.92,
		spearCost   = 1,
		pierceDef   = true,
		unlockCond  = "thunderSpears >= 1",
		unlockLevel = 10,
	},
	spear_volley = {
		id          = "spear_volley",
		name        = "Spear Volley",
		desc        = "Launch multiple thunder spears. Massive damage, costs 2 spears.",
		layer       = 2,
		type        = "attack",
		statKeys    = {"str"},
		strMult     = 3.0,
		baseDamage  = 70,
		cooldown    = 3,
		accuracy    = 0.85,
		spearCost   = 2,
		pierceDef   = true,
		unlockCond  = "thunderSpears >= 2",
		unlockLevel = 20,
	},
	odm_dash = {
		id          = "odm_dash",
		name        = "ODM Dash",
		desc        = "Burst through with ODM gear. High speed strike, ignores 25% DEF.",
		layer       = 2,
		type        = "attack",
		statKeys    = {"bladeMastery","spd"},
		bladeMult   = 1.4,
		spdMult     = 0.3,
		baseDamage  = 18,
		cooldown    = 1,
		accuracy    = 0.97,
		partialPierce = 0.25,           -- ignores 25% of enemy DEF
		unlockCond  = "bladeMastery >= 20",
		unlockLevel = 1,
	},
	advanced_slash = {
		id          = "advanced_slash",
		name        = "Advanced Slash",
		desc        = "Master-level blade work. Damage scales entirely off Blade Mastery.",
		layer       = 2,
		type        = "attack",
		statKeys    = {"bladeMastery"},
		bladeMult   = 2.2,
		baseDamage  = 30,
		cooldown    = 2,
		accuracy    = 0.93,
		unlockCond  = "bladeMastery >= 40",
		unlockLevel = 1,
	},

	-- ── Layer 3a: titan shifter moves ─────────────────────────
	titan_punch = {
		id          = "titan_punch",
		name        = "Titan Fist",
		desc        = "Crush the enemy. STR + Titan Affinity scale damage.",
		layer       = 3,
		type        = "titan_attack",
		statKeys    = {"str","titanAffinity"},
		strMult     = 1.8,
		affinityMult= 0.3,              -- titanAffinity adds 30% of its value
		baseDamage  = 35,
		cooldown    = 0,
		heatCost    = 25,               -- reduced by titanAffinity at runtime
		unlockCond  = "titanShifterMode == true",
	},
	titan_kick = {
		id          = "titan_kick",
		name        = "Titan Kick",
		desc        = "Sweeping kick that can stun. Heat cost reduced by Titan Affinity.",
		layer       = 3,
		type        = "titan_attack",
		statKeys    = {"str","titanAffinity"},
		strMult     = 2.0,
		affinityMult= 0.25,
		baseDamage  = 50,
		cooldown    = 2,
		heatCost    = 30,
		special     = "stun",
		stunChance  = 0.30,
		unlockCond  = "titanShifterMode == true",
	},
	titan_roar = {
		id          = "titan_roar",
		name        = "Titan Roar",
		desc        = "Thunderous roar. WIL + Titan Affinity extend the buff duration.",
		layer       = 3,
		type        = "titan_buff",
		statKeys    = {"wil","titanAffinity"},
		buffKey     = "nextAttackMult",
		buffValue   = 1.5,
		buffTurns   = 1,
		wilBonusTurns = 0.1,            -- +0.1 bonus turns per 10 wil
		cooldown    = 4,
		heatCost    = 20,
		unlockCond  = "titanShifterMode == true",
	},
	titan_special = {
		id          = "titan_special",
		name        = "Titan Special",
		desc        = "Your titan's unique ability. Titan Affinity amplifies damage by up to +50%.",
		layer       = 3,
		type        = "titan_special",
		statKeys    = {"str","titanAffinity"},
		cooldown    = 5,
		heatCost    = 40,
		unlockCond  = "titanShifterMode == true",
	},
}

-- Helper: compute actual heat cost for a titan move, accounting for Titan Affinity.
-- Called at combat resolution time.
function D.GetHeatCost(moveId, titanAffinity)
	local move = D.MOVES[moveId]
	if not move or not move.heatCost then return 0 end
	local reduction = math.floor((titanAffinity or 0) / 10)
		* (D.STATS.titanAffinity.heatCostReductionPer10 or 2)
	return math.max(5, move.heatCost - reduction)   -- minimum 5 heat per action
end

-- Helper: compute titan special damage multiplier from Titan Affinity.
function D.GetAffinitySpecialMult(titanAffinity)
	local bonusPer10 = D.STATS.titanAffinity.specialDmgPer10 or 0.05
	return 1 + math.floor((titanAffinity or 0) / 10) * bonusPer10
end

-- Helper: compute Evasive Maneuver success chance from SPD.
function D.GetEvadeChance(spd)
	local m = D.MOVES.evasive_maneuver
	return math.min(0.95, m.baseEvadeChance + math.floor(spd / 10) * m.spdBonusPer10)
end

-- Helper: compute Recover heal amount from WIL and max HP.
function D.GetRecoverHeal(wil, maxHp)
	return math.floor(maxHp * 0.20 + wil * 2.5)
end

-- Base heat values — actual per-action cost is reduced by titanAffinity at runtime
-- via D.GetHeatCost(). See STAT_DEFINITIONS for the formula.
D.TITAN_HEAT_MAX         = 100
D.TITAN_HEAT_DECAY       = 10   -- base heat lost per non-titan turn (wil adds to this)
D.TITAN_SUPPRESS_TURNS   = 2    -- turns forced out of titan at max heat

-- Fortitude HP formula: maxHp = base + (fortitude * hpPerPoint) + (def * 0.5)
-- See D.STATS.fortitude.hpPerPoint for the per-point value.
D.BASE_HP                = 100  -- everyone starts with 100 HP before stats

-- ────────────────────────────────────────────────────────────
-- TITAN POOL
-- Rolled via titan serums. Pity guarantees Legendary at 50, Mythical at 200.
-- ────────────────────────────────────────────────────────────
D.TITAN_PITY_LEGENDARY = 50
D.TITAN_PITY_MYTHICAL  = 200

D.TITAN_POOL = {
	-- Mythical
	{id="founding",  name="Founding Titan",   rarity="Mythical",  weight=2,
		bonus={str=100, wil=80, def=50},
		specialMove="The Coordinate",  specialDesc="Command all titans. Confuse and mass-damage.",
		special="coordinate"},
	{id="warhammer", name="War Hammer Titan",  rarity="Mythical",  weight=4,
		bonus={str=70,  wil=50},
		specialMove="Crystal Lance",   specialDesc="Erupt hardened spikes. Pierces all armour.",
		special="pierce"},
	{id="colossal",  name="Colossal Titan",    rarity="Mythical",  weight=4,
		bonus={str=80,  def=30},
		specialMove="Steam Release",   specialDesc="Boiling steam burns and staggers.",
		special="burn"},
	-- Legendary
	{id="attack",    name="Attack Titan",      rarity="Legendary", weight=18,
		bonus={str=40,  wil=20},
		specialMove="Battle Hardening", specialDesc="Crystallise and strike. No special effect.",
		special="none"},
	{id="armored",   name="Armored Titan",     rarity="Legendary", weight=16,
		bonus={def=60,  str=20},
		specialMove="Armored Charge",  specialDesc="Full armour rampage. Chance to stun.",
		special="stun"},
	{id="female",    name="Female Titan",      rarity="Legendary", weight=16,
		bonus={spd=40,  wil=30},
		specialMove="Crystal Shatter", specialDesc="Shatter strike + minor heal on hit.",
		special="lifesteal"},
	{id="beast",     name="Beast Titan",       rarity="Legendary", weight=16,
		bonus={str=50,  wil=40},
		specialMove="Boulder Volley",  specialDesc="Hurls boulders. High damage.",
		special="none"},
	-- Rare
	{id="cart",      name="Cart Titan",        rarity="Rare",      weight=450,
		bonus={spd=30,  def=20},
		specialMove="Cannon Barrage",  specialDesc="Rapid cannon fire. Moderate damage.",
		special="none"},
	{id="jaw",       name="Jaw Titan",         rarity="Rare",      weight=450,
		bonus={str=30,  spd=20},
		specialMove="Jaw Devour",      specialDesc="Bites through hardening. Pierces armour.",
		special="pierce"},
}

-- Per-titan stat gains from leveling (XP feeding)
D.TITAN_LEVEL_MAX        = 50
D.TITAN_XP_PER_LEVEL     = 500  -- flat; scaled by rarity below
D.TITAN_RARITY_XP_SCALE  = {Rare=1.0, Legendary=1.5, Mythical=2.5}
D.TITAN_STAT_PER_LEVEL   = {str=1, def=1, spd=1, wil=1}  -- each level adds 1 to each

-- Titan attacks used by enemy titans in missions/raids
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

-- ────────────────────────────────────────────────────────────
-- CLANS
-- Obtained via blood vials. Tiers 0-3 unlock deeper traits.
-- Tier upgrades cost additional vials of the same clan.
-- ────────────────────────────────────────────────────────────
D.CLAN_TIER_COSTS = {[0]=0, [1]=3, [2]=8, [3]=20}  -- cumulative vials to reach tier

D.CLAN_POOL = {
	{id="yeager",    name="Yeager",     rarity="Legendary", weight=10,
		desc = "Carriers of the Attack Titan's will.",
		tiers = {
			[0] = {bonus={str=12}, traits={"attack_synergy"}},                          -- Attack Titan bonus ×1.2
			[1] = {bonus={str=20, wil=8}, traits={"attack_synergy","freedom_drive"}},   -- +move after kill
			[2] = {bonus={str=28, wil=14}, traits={"attack_synergy","freedom_drive","titan_special_boost"}}, -- titan special cd -1
			[3] = {bonus={str=40, wil=20}, traits={"attack_synergy","freedom_drive","titan_special_boost","rumbling_echo"}}, -- massive titan atk boost
		}},
	{id="ackerman",  name="Ackerman",   rarity="Legendary", weight=10,
		desc = "Engineered soldiers. No titan, but unmatched ODM.",
		tiers = {
			[0] = {bonus={str=8,  spd=15}, traits={"no_titan","odm_mastery"}},
			[1] = {bonus={str=16, spd=22}, traits={"no_titan","odm_mastery","ackerman_peak"}},  -- streak multiplier
			[2] = {bonus={str=24, spd=30}, traits={"no_titan","odm_mastery","ackerman_peak","killing_reflex"}}, -- counter on evade
			[3] = {bonus={str=36, spd=42}, traits={"no_titan","odm_mastery","ackerman_peak","killing_reflex","awakening"}}, -- massive spd+str
		}},
	{id="reiss",     name="Reiss",      rarity="Legendary", weight=8,
		desc = "Royal blood flows through you. Founding Titan amplified.",
		tiers = {
			[0] = {bonus={wil=15, def=5}, traits={"founding_synergy"}},
			[1] = {bonus={wil=22, def=10}, traits={"founding_synergy","royal_grace"}},        -- heal on win
			[2] = {bonus={wil=30, def=16}, traits={"founding_synergy","royal_grace","coordinate_touch"}}, -- coordinate unlocks earlier
			[3] = {bonus={wil=44, def=24}, traits={"founding_synergy","royal_grace","coordinate_touch","true_king"}},
		}},
	{id="tybur",     name="Tybur",      rarity="Legendary", weight=8,
		desc = "Holders of the War Hammer lineage.",
		tiers = {
			[0] = {bonus={str=10, def=10}, traits={"warhammer_synergy"}},
			[1] = {bonus={str=18, def=16}, traits={"warhammer_synergy","crystal_armour"}},   -- 10% dmg reduction
			[2] = {bonus={str=26, def=22}, traits={"warhammer_synergy","crystal_armour","lance_mastery"}}, -- spear dmg ×1.15
			[3] = {bonus={str=38, def=32}, traits={"warhammer_synergy","crystal_armour","lance_mastery","world_nobility"}},
		}},
	{id="braun",     name="Braun",      rarity="Rare",      weight=25,
		desc = "Warriors. Armored Titan's might flows here.",
		tiers = {
			[0] = {bonus={def=14, str=6}, traits={"armored_synergy"}},
			[1] = {bonus={def=22, str=12}, traits={"armored_synergy","iron_skin"}},           -- -15% incoming dmg
			[2] = {bonus={def=30, str=18}, traits={"armored_synergy","iron_skin","shield_slam"}},
			[3] = {bonus={def=44, str=28}, traits={"armored_synergy","iron_skin","shield_slam","unbreakable"}},
		}},
	{id="leonhart",  name="Leonhart",   rarity="Rare",      weight=25,
		desc = "Grace and deadly precision. Female Titan bloodline.",
		tiers = {
			[0] = {bonus={spd=14, wil=6}, traits={"female_synergy"}},
			[1] = {bonus={spd=22, wil=12}, traits={"female_synergy","crystal_reflex"}},      -- evade +10% success
			[2] = {bonus={spd=30, wil=18}, traits={"female_synergy","crystal_reflex","scream"}},
			[3] = {bonus={spd=44, wil=28}, traits={"female_synhardt","crystal_reflex","scream","apex_predator"}},
		}},
	{id="zoe",       name="Zoe",        rarity="Rare",      weight=30,
		desc = "Survey Corps genius. Science and strategy.",
		tiers = {
			[0] = {bonus={wil=10, spd=8}, traits={"survey_bonus"}},                          -- extra XP from bosses
			[1] = {bonus={wil=16, spd=14}, traits={"survey_bonus","field_notes"}},           -- see enemy stats
			[2] = {bonus={wil=22, spd=20}, traits={"survey_bonus","field_notes","test_subject"}},
			[3] = {bonus={wil=32, spd=28}, traits={"survey_bonus","field_notes","test_subject","beautiful"}},
		}},
	{id="springer",  name="Springer",   rarity="Common",    weight=60,
		desc = "Connie's kin. Stubborn and reliable.",
		tiers = {
			[0] = {bonus={def=6,  spd=6},  traits={"garrison_heart"}},
			[1] = {bonus={def=12, spd=10}, traits={"garrison_heart","stubborn"}},
			[2] = {bonus={def=18, spd=15}, traits={"garrison_heart","stubborn","home_defender"}},
			[3] = {bonus={def=28, spd=22}, traits={"garrison_heart","stubborn","home_defender","never_give_up"}},
		}},
	{id="blouse",    name="Blouse",     rarity="Common",    weight=60,
		desc = "Sasha's lineage. Evasion and survival instincts.",
		tiers = {
			[0] = {bonus={spd=10, wil=4}, traits={"hunter_instinct"}},                       -- +5% evade chance
			[1] = {bonus={spd=16, wil=8}, traits={"hunter_instinct","forager"}},              -- recover heals 10% more
			[2] = {bonus={spd=22, wil=13}, traits={"hunter_instinct","forager","potato_power"}},
			[3] = {bonus={spd=32, wil=20}, traits={"hunter_instinct","forager","potato_power","survival_mode"}},
		}},
	{id="smith",     name="Smith",      rarity="Common",    weight=55,
		desc = "Erwin's bloodline. Leadership and resolve.",
		tiers = {
			[0] = {bonus={wil=8,  str=6},  traits={"commanders_will"}},                       -- +10% boss XP
			[1] = {bonus={wil=14, str=10}, traits={"commanders_will","calculated_risk"}},
			[2] = {bonus={wil=20, str=16}, traits={"commanders_will","calculated_risk","devote_your_hearts"}},
			[3] = {bonus={wil=30, str=24}, traits={"commanders_will","calculated_risk","devote_your_hearts","beyond_the_walls"}},
		}},
}

-- Total weight for clan rolling (precomputed)
local _clanTotalWeight = 0
for _, c in ipairs(D.CLAN_POOL) do _clanTotalWeight = _clanTotalWeight + c.weight end
D.CLAN_TOTAL_WEIGHT = _clanTotalWeight

function D.RollClan(pity)
	pity = pity or 0
	-- Pity: at 30 vials guaranteed Rare+, at 80 guaranteed Legendary
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

-- ────────────────────────────────────────────────────────────
-- CLAN ACTIVE MOVES  (Layer 3b)
-- Legendary clans only. One active move per clan, keyed by clan id.
-- Rare/Common clans are passive — their traits apply via CalcCS only.
-- ────────────────────────────────────────────────────────────
D.CLAN_MOVES = {
	yeager = {
		id          = "yeager_coordinate",
		name        = "Coordinating Scream",
		desc        = "Yeager's will surges. Inflict fear on the enemy for 2 turns and boost your next titan special damage by 50%.",
		type        = "clan_active",
		statKeys    = {"wil","titanAffinity"},
		cooldown    = 6,
		heatCost    = 0,                 -- usable outside titan form too
		effects     = {"fear_enemy_2","self_titan_boost_50"},
		unlockCond  = function(d)        -- clan tier 2+ OR prestige 5+
			return (d.clanTier or 0) >= 2 or (d.prestige or 0) >= 5
		end,
		unlockDesc  = "Requires Yeager tier 2 OR prestige 5+",
	},
	ackerman = {
		id          = "ackerman_surge",
		name        = "Ackerman Awakening",
		desc        = "The Ackerman bloodline ignites. A burst attack that scales entirely off Blade Mastery and Speed — deals true damage (ignores all DEF).",
		type        = "clan_active",
		statKeys    = {"bladeMastery","spd"},
		bladeMult   = 2.8,
		spdMult     = 0.6,
		baseDamage  = 20,
		cooldown    = 5,
		heatCost    = 0,
		trueDamage  = true,              -- bypasses enemy DEF entirely
		effects     = {"true_damage"},
		unlockCond  = function(d)
			return (d.clanTier or 0) >= 1  -- unlocks at tier 1
		end,
		unlockDesc  = "Requires Ackerman tier 1+",
	},
	reiss = {
		id          = "reiss_royal_vow",
		name        = "Royal Vow",
		desc        = "Channel royal blood. Once per fight: restore 30% max HP, grant immunity to all status effects for 3 turns.",
		type        = "clan_active",
		statKeys    = {"wil","fortitude"},
		cooldown    = 999,               -- effectively once per fight
		heatCost    = 0,
		effects     = {"heal_pct_30","status_immune_3"},
		healPct     = 0.30,
		immuneTurns = 3,
		unlockCond  = function(d)
			return (d.clanTier or 0) >= 1
		end,
		unlockDesc  = "Requires Reiss tier 1+",
	},
	tybur = {
		id          = "tybur_war_hammer",
		name        = "War Hammer Construct",
		desc        = "Manifest a crystal construct. Absorbs the next 2 hits directed at you and counterattacks for moderate damage on absorption.",
		type        = "clan_active",
		statKeys    = {"def","wil"},
		counterDmgMult = 0.8,            -- counter hit scales off incoming damage
		shieldHits  = 2,
		cooldown    = 5,
		heatCost    = 0,
		effects     = {"shield_2_hits","counter_on_absorb"},
		unlockCond  = function(d)
			return (d.clanTier or 0) >= 1
		end,
		unlockDesc  = "Requires Tybur tier 1+",
	},
}

-- ────────────────────────────────────────────────────────────
-- PATH ACTIVE MOVES  (Layer 4)
-- One signature move per path, gated by prestige thresholds.
-- ────────────────────────────────────────────────────────────
D.PATH_MOVES = {
	eldian = {
		id          = "eldian_coordinate",
		name        = "The Coordinate",
		desc        = "Invoke the power of all titans. Massive damage + confuse the enemy for 1 turn. Titan Affinity amplifies.",
		type        = "path_active",
		statKeys    = {"str","titanAffinity"},
		strMult     = 3.5,
		affinityMult= 0.8,
		cooldown    = 8,
		heatCost    = 50,
		effects     = {"confuse_enemy_1"},
		unlockCond  = function(d)
			return (d.prestige or 0) >= 5
		end,
		unlockDesc  = "Requires Eldian path + prestige 5+",
	},
	marleyan = {
		id          = "marleyan_barrage",
		name        = "Anti-Titan Barrage",
		desc        = "Call down a coordinated spear strike. Consumes 3 spears. Massive piercing damage; Blade Mastery amplifies.",
		type        = "path_active",
		statKeys    = {"str","bladeMastery"},
		strMult     = 2.5,
		bladeMult   = 1.0,
		spearCost   = 3,
		cooldown    = 6,
		heatCost    = 0,
		pierceDef   = true,
		effects     = {},
		unlockCond  = function(d)
			return (d.prestige or 0) >= 3
		end,
		unlockDesc  = "Requires Marleyan path + prestige 3+",
	},
	wandering = {
		id          = "wandering_ghost_step",
		name        = "Ghost Step",
		desc        = "Vanish and reposition. Dodge all attacks for 2 turns, then deal a guaranteed critical hit. Scales SPD + Blade Mastery.",
		type        = "path_active",
		statKeys    = {"spd","bladeMastery"},
		spdMult     = 1.2,
		bladeMult   = 1.5,
		evadeTurns  = 2,
		guaranteedCrit = true,
		critMult    = 2.0,
		cooldown    = 7,
		heatCost    = 0,
		effects     = {"evade_2","guaranteed_crit"},
		unlockCond  = function(d)
			return (d.prestige or 0) >= 2
		end,
		unlockDesc  = "Requires Wandering path + prestige 2+",
	},
	royal = {
		id          = "royal_founding_scream",
		name        = "Founding Scream",
		desc        = "Unleash the Founding Titan's authority. Halve the enemy's effective ATK for 3 turns and restore 20% max HP. Fortitude amplifies.",
		type        = "path_active",
		statKeys    = {"wil","fortitude"},
		wilMult     = 1.0,
		healPct     = 0.20,
		enemyAtkDebuffTurns = 3,
		enemyAtkDebuffPct   = 0.50,
		cooldown    = 7,
		heatCost    = 0,
		effects     = {"enemy_atk_half_3","heal_pct_20"},
		unlockCond  = function(d)
			return (d.prestige or 0) >= 2
		end,
		unlockDesc  = "Requires Royal Blood path + prestige 2+",
	},
}

-- ────────────────────────────────────────────────────────────
-- GetAvailableMoves
-- Returns an ordered array of move IDs the player `d` can use
-- right now in combat. Called each turn to build the action menu.
-- ────────────────────────────────────────────────────────────
function D.GetAvailableMoves(d)
	local moves = {}

	-- ── Layer 1: base (always) ──────────────────────────────
	table.insert(moves, "slash")
	table.insert(moves, "heavy_strike")
	table.insert(moves, "recover")
	table.insert(moves, "evasive_maneuver")
	table.insert(moves, "retreat")

	-- ── Layer 2: unlocked by progress ──────────────────────
	if (d.thunderSpears or 0) >= 1 then
		table.insert(moves, "spear_strike")
	end
	if (d.thunderSpears or 0) >= 2 then
		table.insert(moves, "spear_volley")
	end
	if (d.bladeMastery or 0) >= 20 then
		table.insert(moves, "odm_dash")
	end
	if (d.bladeMastery or 0) >= 40 then
		table.insert(moves, "advanced_slash")
	end

	-- ── Layer 3a: titan shifter ─────────────────────────────
	if d.titanShifterMode and d.clan ~= "ackerman" then
		table.insert(moves, "titan_punch")
		table.insert(moves, "titan_kick")
		table.insert(moves, "titan_roar")
		if d.equippedTitan and d.titanSlots and d.titanSlots[d.equippedTitan] then
			table.insert(moves, "titan_special")
		end
	end

	-- ── Layer 3b: clan active (Legendary only) ──────────────
	if d.clan then
		local clanMove = D.CLAN_MOVES[d.clan]
		if clanMove and clanMove.unlockCond(d) then
			table.insert(moves, clanMove.id)
		end
	end

	-- ── Layer 4: path active ────────────────────────────────
	if d.path then
		local pathMove = D.PATH_MOVES[d.path]
		if pathMove and pathMove.unlockCond(d) then
			table.insert(moves, pathMove.id)
		end
	end

	return moves
end

-- Convenience: get the full move definition regardless of which
-- table it lives in (D.MOVES, D.CLAN_MOVES, or D.PATH_MOVES).
function D.GetMoveDef(moveId)
	if D.MOVES[moveId] then return D.MOVES[moveId] end
	for _, cm in pairs(D.CLAN_MOVES) do
		if cm.id == moveId then return cm end
	end
	for _, pm in pairs(D.PATH_MOVES) do
		if pm.id == moveId then return pm end
	end
	return nil
end
D.FORGE_BONUS_PER_LEVEL = 2     -- each forge level adds +2 to each stat in the item's bonus
D.FORGE_MAX_LEVEL       = 10
D.FORGE_COST_BASE       = 300   -- funds cost for level 1; scales with item level

function D.ForgeCost(currentLevel, hasBoost)
	local base = math.floor(D.FORGE_COST_BASE * (1.6 ^ currentLevel))
	return hasBoost and math.floor(base * 0.75) or base
end

D.ITEMS = {
	-- ── Weapons ──────────────────────────────────────────────
	{id="odm_basic",       name="Standard ODM Gear",     type="weapon", rarity="Common",    bonus={str=4,  spd=2,  bladeMastery=1},                  setGroup="survey"},
	{id="odm_survey",      name="Survey Corps ODM",      type="weapon", rarity="Uncommon",  bonus={str=8,  spd=5,  bladeMastery=3},                  setGroup="survey"},
	{id="odm_elite",       name="Elite ODM Gear",        type="weapon", rarity="Rare",      bonus={str=14, spd=8,  bladeMastery=6},                  setGroup="elite_corps"},
	{id="thunder_blade",   name="Thunder Blade",         type="weapon", rarity="Rare",      bonus={str=16, wil=4,  bladeMastery=4},                  setGroup="thunder"},
	{id="odm_legendary",   name="Legendary ODM Rig",     type="weapon", rarity="Legendary", bonus={str=24, spd=14, bladeMastery=12},                 setGroup="elite_corps"},
	{id="warhammer_spike", name="War Hammer Spike",      type="weapon", rarity="Legendary", bonus={str=30, def=8,  titanAffinity=6},                 setGroup="marley"},
	{id="coordinate_blade",name="Coordinate Blade",      type="weapon", rarity="Mythical",  bonus={str=40, wil=20, spd=10, titanAffinity=14},        setGroup="royal"},

	-- ── Armors ───────────────────────────────────────────────
	{id="recruit_uniform", name="Recruit Uniform",       type="armor",  rarity="Common",    bonus={def=4,  fortitude=2},                             setGroup="survey"},
	{id="survey_cloak",    name="Survey Corps Cloak",    type="armor",  rarity="Uncommon",  bonus={def=8,  wil=3,  fortitude=3},                     setGroup="survey"},
	{id="garrison_plate",  name="Garrison Plate",        type="armor",  rarity="Rare",      bonus={def=14, fortitude=8},                             setGroup="garrison"},
	{id="thunder_vest",    name="Thunder Spear Vest",    type="armor",  rarity="Rare",      bonus={def=12, wil=6,  fortitude=5},                     setGroup="thunder"},
	{id="elite_armour",    name="Elite Corps Armour",    type="armor",  rarity="Legendary", bonus={def=22, fortitude=14},                            setGroup="elite_corps"},
	{id="marley_armour",   name="Marleyan Battle Plate", type="armor",  rarity="Legendary", bonus={def=26, str=6,  fortitude=10},                    setGroup="marley"},
	{id="founding_robe",   name="Founding Robe",         type="armor",  rarity="Mythical",  bonus={def=36, wil=18, fortitude=22},                    setGroup="royal"},

	-- ── Accessories ──────────────────────────────────────────
	{id="wing_pin",        name="Wings of Freedom Pin",  type="accessory", rarity="Common",    bonus={wil=4,  xpBonus=0.05}},
	{id="survey_badge",    name="Survey Corps Badge",    type="accessory", rarity="Uncommon",  bonus={wil=6,  spd=3,  bladeMastery=2},               setGroup="survey"},
	{id="thunder_harness", name="Thunder Spear Harness", type="accessory", rarity="Rare",      bonus={str=8,  wil=8}},
	{id="ackerman_ring",   name="Ackerman Ring",         type="accessory", rarity="Rare",      bonus={spd=12, str=6,  bladeMastery=8}},
	{id="titan_core",      name="Titan Core Fragment",   type="accessory", rarity="Rare",      bonus={titanAffinity=10, wil=4}},
	{id="reiss_crown",     name="Reiss Crown Fragment",  type="accessory", rarity="Legendary", bonus={wil=20, def=10, fortitude=8},                  setGroup="royal"},
	{id="marley_medal",    name="Marley War Medal",      type="accessory", rarity="Legendary", bonus={str=16, def=12}},
	{id="founders_eye",    name="Founder's Eye",         type="accessory", rarity="Mythical",  bonus={wil=30, str=15, spd=8, titanAffinity=12},      setGroup="royal"},
}

-- Map for O(1) lookup
D.ITEM_MAP = {}
for _, item in ipairs(D.ITEMS) do D.ITEM_MAP[item.id] = item end

-- Equipment set bonuses (2-piece and 3-piece)
D.EQUIPMENT_SETS = {
	{name="Survey Corps",    pieces={"odm_survey","survey_cloak","survey_badge"},
		twoBonus={wil=8,xpBonus=0.10},    threeBonus={str=10,spd=10,wil=12,xpBonus=0.15}},
	{name="Elite Corps",     pieces={"odm_elite","elite_armour"},
		twoBonus={str=14,def=10}},
	{name="Thunder Arsenal", pieces={"thunder_blade","thunder_vest","thunder_harness"},
		twoBonus={str=10,wil=8},           threeBonus={str=18,wil=14,spearDamageMult=0.15}},
	{name="Royal Legacy",    pieces={"coordinate_blade","founding_robe","founders_eye"},
		twoBonus={wil=20,def=14},          threeBonus={wil=36,def=24,str=16,maxHpBonus=200}},
	{name="Marleyan Warrior",pieces={"warhammer_spike","marley_armour","marley_medal"},
		twoBonus={str=16,def=12},          threeBonus={str=28,def=22,spearDamageMult=0.20}},
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

-- ────────────────────────────────────────────────────────────
-- ODM GEAR UPGRADES
-- Purchased with funds. Tier stacks cumulatively.
-- ────────────────────────────────────────────────────────────
D.ODM_UPGRADES = {
	{tier=1, name="Better Blades",         cost=1500,  bonus={str=4}},
	{tier=2, name="Refined Gas Canisters", cost=3500,  bonus={spd=5}},
	{tier=3, name="Reinforced Wires",      cost=7000,  bonus={def=4, spd=3}},
	{tier=4, name="Survey Corps Rig",      cost=15000, bonus={str=8, spd=8}},
	{tier=5, name="Custom Vertical Gear",  cost=30000, bonus={str=14,spd=14,wil=6}},
	{tier=6, name="Legendary ODM Frame",   cost=70000, bonus={str=20,spd=20,def=10,wil=10}},
}

-- ────────────────────────────────────────────────────────────
-- THUNDER SPEAR CRAFTING
-- Material IDs reference DROP_TABLE entries.
-- ────────────────────────────────────────────────────────────
D.SPEAR_RECIPES = {
	{id="spear_basic",  name="Thunder Spear (×5)",
		yields=5, cost=800,
		materials={{id="titan_flesh",qty=3},{id="gas_canister",qty=2}}},
	{id="spear_pack",   name="Thunder Spear Pack (×15)",
		yields=15, cost=2000,
		materials={{id="titan_flesh",qty=8},{id="gas_canister",qty=5},{id="refined_ore",qty=2}}},
	{id="spear_bundle", name="Thunder Spear Bundle (×30)",
		yields=30, cost=4500,
		materials={{id="titan_flesh",qty=15},{id="gas_canister",qty=10},{id="colossal_shard",qty=1}}},
}

-- ────────────────────────────────────────────────────────────
-- SHOP
-- Rotating daily shop of 6 items. Weights control rarity frequency.
-- ────────────────────────────────────────────────────────────
D.SHOP_PRICES   = {Common=600, Uncommon=1500, Rare=3500, Legendary=9000, Mythical=28000}
D.SHOP_WEIGHTS  = {Common=40,  Uncommon=28,   Rare=18,   Legendary=8,    Mythical=1}
D.SHOP_SLOTS    = 6   -- items visible in daily shop
D.SHOP_REROLL_COST = 500  -- funds to reroll shop (one reroll per day)

-- ────────────────────────────────────────────────────────────
-- PROMO CODES
-- used = {} is server-only; not stored in D (populated at runtime by AOT_Server_Shop).
-- ────────────────────────────────────────────────────────────
D.PROMO_CODES = {
	ATTACKONTITAN  = {funds=1000, serums=1,  xp=500,  vials=0, active=true},
	SURVEYKORPS    = {funds=2000, serums=2,  xp=1000, vials=0, active=true},
	WALLMARIA      = {funds=500,  serums=0,  xp=0,    vials=2, active=true},
	RUMBLING       = {funds=3000, serums=3,  xp=2000, vials=0, active=true},
	COLOSSAL       = {funds=1500, serums=0,  xp=0,    vials=3, active=true},
	PATHS          = {funds=500,  serums=1,  xp=250,  vials=1, active=true},
}

-- ────────────────────────────────────────────────────────────
-- DAILY LOGIN STREAK
-- ────────────────────────────────────────────────────────────
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

-- ────────────────────────────────────────────────────────────
-- CAMPAIGN
-- 8 chapters following the AoT storyline.
-- Each chapter is a sequence of enemies; the last is always a boss.
-- unlockPrestige: minimum prestige level to replay at this chapter.
-- ────────────────────────────────────────────────────────────
-- ────────────────────────────────────────────────────────────
-- BOSS MECHANICS
-- Per-boss gimmicks. Each boss entry in CAMPAIGN references one
-- by id. The combat server reads these to apply effects each turn.
--
-- BRUTE-FORCE vs COUNTER design principle:
--   Every mechanic can be tanked through with enough raw stats,
--   but the right build bypasses it efficiently or flips it.
-- ────────────────────────────────────────────────────────────
D.BOSS_MECHANICS = {

	-- Female Titan — Crystal Hardening
	-- Activates at Phase 2. Non-pierce attacks do 60% less damage.
	-- Each pierce move has a 30% chance to shatter the hardening early.
	-- COUNTER: Marleyan path + spears / Jaw Titan equipped / odm_dash / advanced_slash
	-- BRUTE:   Stack STR high enough to kill before Phase 2, or endure the reduction.
	crystal_hardening = {
		id                  = "crystal_hardening",
		name                = "Crystal Hardening",
		activatesAtPhase    = 2,
		activeByDefault     = false,
		announcement        = "Annie hardens her crystal armour! Non-pierce attacks deal reduced damage!",
		shatterMsg          = "A pierce strike shatters the hardening! Full damage restored!",
		-- Runtime state key stored in d.bossGimmickState: { active=bool }
		damageReductionPct  = 0.60,   -- non-pierce attacks deal 40% of normal
		pierceBreakChance   = 0.30,   -- each pierce move: 30% chance to shatter hardening
		-- Moves considered "pierce": pierceDef=true in D.MOVES, trueDamage=true clan moves,
		-- or titan specials with special="pierce"
	},

	-- Armored Titan — Armored Nape
	-- Active from the start (Phase 1). All attacks reduced 70%.
	-- The armor has its own HP pool. Pierce moves and consecutive
	-- heavy_strike chains deal full damage to the armor HP.
	-- When armor HP hits 0 the mechanic deactivates entirely.
	-- COUNTER: War Hammer Spike + spear_volley / Tybur clan / warhammer titan special
	-- BRUTE:   Chip slowly through the reduction — takes much longer but works.
	nape_armor = {
		id                  = "nape_armor",
		name                = "Armored Nape",
		activatesAtPhase    = 1,
		activeByDefault     = true,   -- active from fight start, not just phase 2+
		announcement        = "Reiner's armour is impenetrable. Find a way to break through!",
		shatterMsg          = "The armour CRACKS! Reiner is fully exposed!",
		damageReductionPct  = 0.70,   -- all attacks deal 30% of normal while active
		-- Armor HP pool — tracked in d.bossGimmickState.armorHp
		armorHp             = 500,
		-- Pierce moves deal FULL damage directly to armorHp (bypass the 70% reduction)
		-- Consecutive heavy_strike (2+ in a row) deal 2× to armorHp
		heavyStreakBonus     = 2.0,
	},

	-- Beast Titan — Boulder Barrage
	-- Every 3 enemy turns, Zeke telegraphs and hurls boulders:
	--   2× ATK damage + 2-turn slow on player.
	-- Evasive Maneuver gets +15% success chance specifically vs the barrage.
	-- Fortitude reduces the slow duration by 1 turn per 10 fortitude.
	-- COUNTER: High SPD + evasive_maneuver, Ackerman bloodline, Blouse hunter_instinct
	-- BRUTE:   High DEF + Fortitude to absorb the hits and shrug off slows.
	boulder_barrage = {
		id                  = "boulder_barrage",
		name                = "Boulder Barrage",
		activatesAtPhase    = 1,
		activeByDefault     = true,
		announcement        = "The Beast Titan readies a boulder. BRACE FOR IMPACT!",
		barrageInterval     = 3,      -- triggers every 3 enemy turns
		barrageDamageMult   = 2.0,    -- 2× normal ATK
		inflictsSlowTurns   = 2,
		evadeChanceBonus    = 0.15,   -- Evasive Maneuver gets +15% vs barrage
		fortitudeSlowReduce = 0.1,    -- -0.1 slow turns per 10 fortitude (min 0)
		-- Runtime state: d.bossGimmickState.barrageTimer (counts up to barrageInterval)
	},

	-- Colossal Titan — Steam Release
	-- Activates at Phase 2 (below 50% HP).
	-- Alternates: STEAM turns → all player attacks deal 20% damage + player takes
	-- 8% max HP burn. WINDOW turns → full damage, no steam.
	-- WIL reduces steam burn by 1% per 10 WIL. Royal Vow immunity skips the burn.
	-- COUNTER: High WIL + Recover timing, Royal path Founding Scream immune window
	-- BRUTE:   Burst the boss down during window turns before steam turns stack up.
	steam_release = {
		id                  = "steam_release",
		name                = "Steam Release",
		activatesAtPhase    = 2,
		activeByDefault     = false,
		announcement        = "The Colossal Titan vents scalding steam! Damage is drastically reduced on steam turns!",
		steamDmgReductionPct= 0.80,   -- player attacks deal 20% during steam turns
		steamBurnPct        = 0.08,   -- player takes 8% max HP as steam burn each steam turn
		wilBurnReductePer10 = 0.01,   -- -1% burn per 10 WIL
		-- Runtime state: d.bossGimmickState.steamActive (bool, flips each enemy turn)
	},

	-- Warhammer Titan — Crystal Construct
	-- At Phase 2, Lara erects a crystal barrier with its own HP pool.
	-- All damage is redirected to the barrier until it's destroyed.
	-- Titan Affinity moves (titan_punch, titan_special) deal 2× damage to the barrier.
	-- Path move: Eldian Coordinate deals 3× to the barrier.
	-- COUNTER: Eldian path + high Titan Affinity spec, equipped titan with affinity
	-- BRUTE:   Just deal enough total damage — the barrier has fixed HP.
	crystal_construct = {
		id                  = "crystal_construct",
		name                = "Crystal Construct",
		activatesAtPhase    = 2,
		activeByDefault     = false,
		announcement        = "Lara Tybur raises a crystal construct! All damage is absorbed by the barrier!",
		shatterMsg          = "The crystal SHATTERS! The War Hammer Titan is exposed!",
		barrierHp           = 2000,
		titanAffinityDamageMult = 2.0,  -- titan moves deal double to barrier
		coordinateDamageMult    = 3.0,  -- eldian Coordinate move deals triple
	},

	-- Founding Titan / Eren — Coordinate Authority
	-- Activates at Phase 3 (below 30% HP).
	-- Each enemy turn: inflicts a cycling status (bleed → slow → fear → repeat).
	-- Non-pierce attacks have 20% chance to reflect half damage back at the player.
	-- Fortitude reduces each status duration. Reiss Royal Vow negates everything.
	-- COUNTER: Reiss tier 1+ (Royal Vow), high WIL + Fortitude build
	-- BRUTE:   Push through statuses with healing. Requires strong recovery loop.
	coordinate_authority = {
		id                  = "coordinate_authority",
		name                = "Coordinate Authority",
		activatesAtPhase    = 3,
		activeByDefault     = false,
		announcement        = "The Founding Titan's authority warps reality! Status effects each turn!",
		statusCycle         = {"bleed", "slow", "fear"},   -- inflicts in order, cycling
		statusDuration      = 2,        -- base duration of each inflicted status
		reflectChance       = 0.20,     -- non-pierce attacks have 20% reflect chance
		reflectPct          = 0.50,     -- reflected damage = 50% of damage dealt
		fortitudeStatusReduce = 0.05,   -- -0.05 turns per 10 fortitude (min 1)
		-- Royal Vow (Reiss clan active) grants full immunity while active
	},
}

-- ────────────────────────────────────────────────────────────
-- Helper: check if a move counts as "pierce" for mechanic purposes.
-- ────────────────────────────────────────────────────────────
function D.IsPierceMove(moveId)
	local def = D.GetMoveDef(moveId)
	if not def then return false end
	-- Explicit pierce flag on base moves
	if def.pierceDef or def.trueDamage then return true end
	-- Titan specials with pierce effect
	if def.type == "titan_special" then return false end  -- resolved at runtime by titanId
	return false
end

-- Helper: check if a move deals full damage to crystal/armor HP pools.
-- Titan affinity moves + pierce moves qualify.
function D.IsTitanAffinityMove(moveId)
	local def = D.GetMoveDef(moveId)
	if not def then return false end
	return def.type == "titan_attack" or def.type == "titan_special"
		or def.type == "titan_buff" or def.type == "path_active"
end

D.CAMPAIGN = {
	{id="ch1", name="The Fall of Wall Maria",
		desc="Wall Maria is breached. Pure Titans flood Shiganshina.",
		unlockPrestige=0,
		enemies={
			{name="5M Pure Titan",   hp=120,  atk=14, xp=28,  funds=14, tier="weak"},
			{name="8M Rogue Titan",  hp=200,  atk=22, xp=50,  funds=25, tier="weak"},
			{name="10M Titan",       hp=300,  atk=30, xp=75,  funds=38, tier="medium"},
			{name="Titan Pair",      hp=420,  atk=38, xp=100, funds=55, tier="medium"},
			{name="12M Aberrant",    hp=580,  atk=46, xp=140, funds=80, tier="medium", behavior="aberrant"},
			{name="Titan Vanguard",  hp=750,  atk=55, xp=180, funds=110,tier="strong"},
			{name="COLOSSAL TITAN",  hp=1200, atk=90, xp=600, funds=400, tier="boss",
				isBoss=true, regen=60, bossBonus=200, behavior="telegraph",
				titanId="colossal",
				drops={"titan_flesh","colossal_shard"},
				-- Ch1: introductory boss, no special mechanic — teaches phase transitions
				phases={
					[2]={hpThreshold=0.60, atkMult=1.25, regenMult=1.20,
						msg="The Colossal Titan bellows — its heat intensifies!"},
					[3]={hpThreshold=0.30, atkMult=1.20,
						msg="The Colossal Titan rears back for a final surge!"},
				}},
		}},
	{id="ch2", name="Wall Rose Breach",
		desc="Titans appear inside Wall Rose. The Garrison scrambles.",
		unlockPrestige=0,
		enemies={
			{name="10M Aberrant",    hp=500,  atk=44, xp=130, funds=75, tier="medium", behavior="aberrant"},
			{name="10M Crawler",     hp=500,  atk=44, xp=130, funds=75, tier="medium", behavior="crawler"},
			{name="12M Titan",       hp=800,  atk=58, xp=200, funds=120,tier="strong"},
			{name="14M Titan",       hp=1000, atk=68, xp=250, funds=150,tier="strong"},
			{name="Garrison Captain",hp=900,  atk=62, xp=220, funds=140,tier="strong"},
			{name="FEMALE TITAN",    hp=3200, atk=105,xp=900, funds=600, tier="boss",
				isBoss=true, regen=90, bossBonus=300, behavior="telegraph",
				titanId="female",
				drops={"titan_flesh","gas_canister","odm_elite"},
				mechanic="crystal_hardening",
				phases={
					[2]={hpThreshold=0.60, atkMult=1.20, regenMult=1.15,
						msg="Annie crystallises! Hardening activates!",
						activateMechanic=true},
					[3]={hpThreshold=0.30, atkMult=1.25,
						msg="She roars and reinforces the hardening — break through!"},
				}},
		}},
	{id="ch3", name="Forest of Giant Trees",
		desc="Survey Corps territory. The Beast Titan commands from the ridge.",
		unlockPrestige=0,
		enemies={
			{name="15M Titan",       hp=1100, atk=72, xp=280, funds=170,tier="strong"},
			{name="Titan Patrol",    hp=1400, atk=82, xp=360, funds=210,tier="strong"},
			{name="Armoured Scout",  hp=1800, atk=92, xp=420, funds=260,tier="strong", behavior="armored"},
			{name="Titan Commander", hp=2800, atk=115,xp=600, funds=370,tier="boss",   regen=100},
			{name="BEAST TITAN",     hp=5500, atk=145,xp=1600,funds=1000, tier="boss",
				isBoss=true, regen=140, bossBonus=500, behavior="telegraph",
				titanId="beast",
				drops={"titan_flesh","refined_ore","beast_core"},
				mechanic="boulder_barrage",
				phases={
					[2]={hpThreshold=0.60, atkMult=1.20, regenMult=1.15,
						msg="Zeke roars — the boulder volleys accelerate!"},
					[3]={hpThreshold=0.30, atkMult=1.25,
						msg="Zeke screams in fury — the barrage becomes relentless!"},
				}},
		}},
	{id="ch4", name="Assault on Stohess",
		desc="Chaos inside Wall Sina. The Female Titan rampages through the city.",
		unlockPrestige=0,
		enemies={
			{name="Military Police", hp=1800, atk=95, xp=460, funds=290,tier="strong"},
			{name="MP Elite",        hp=2200, atk=105,xp=520, funds=320,tier="strong"},
			{name="Crystal Titan",   hp=3500, atk=120,xp=800, funds=500,tier="boss", regen=120, behavior="armored"},
			{name="ARMORED TITAN",   hp=9000, atk=190,xp=2800,funds=1800, tier="boss",
				isBoss=true, regen=200, bossBonus=800, behavior="telegraph",
				titanId="armored",
				drops={"titan_flesh","refined_ore","armored_plate","garrison_plate"},
				mechanic="nape_armor",
				phases={
					[2]={hpThreshold=0.60, atkMult=1.20,
						msg="Reiner's armour glows red-hot — but cracks are forming!"},
					[3]={hpThreshold=0.30, atkMult=1.30, regenMult=1.20,
						msg="Reiner roars and charges! The nape is almost exposed!"},
				}},
		}},
	{id="ch5", name="Retaking Wall Maria",
		desc="The final march to Shiganshina. The Colossal blocks the gate.",
		unlockPrestige=0,
		enemies={
			{name="Titan Horde",     hp=4000, atk=130,xp=900, funds=600,tier="strong"},
			{name="Gate Titan",      hp=5500, atk=150,xp=1100,funds=700,tier="boss", regen=160, behavior="armored"},
			{name="Wall Sentinel",   hp=6500, atk=165,xp=1300,funds=820,tier="boss", regen=180},
			{name="COLOSSAL TITAN II",hp=16000,atk=260,xp=5000,funds=3000, tier="boss",
				isBoss=true, regen=320, bossBonus=1500, behavior="telegraph",
				titanId="colossal",
				drops={"colossal_shard","refined_ore","odm_legendary"},
				mechanic="steam_release",
				phases={
					[2]={hpThreshold=0.50, atkMult=1.20, regenMult=1.15,
						msg="The Colossal Titan vents steam — the air burns!",
						activateMechanic=true},
					[3]={hpThreshold=0.25, atkMult=1.25,
						msg="Steam fills the entire arena — find the windows!"},
				}},
		}},
	{id="ch6", name="The War for Paradis",
		desc="Marleyan forces land on Paradis. Warriors and soldiers clash.",
		unlockPrestige=1,
		enemies={
			{name="Marleyan Soldier", hp=8000, atk=180,xp=1800,funds=1100,tier="strong"},
			{name="Thunder Squad",    hp=11000,atk=210,xp=2400,funds=1500,tier="strong"},
			{name="Titan Knight",     hp=15000,atk=230,xp=2800,funds=1700,tier="boss", regen=250},
			{name="WARHAMMER TITAN",  hp=35000,atk=340,xp=8000,funds=5000, tier="boss",
				isBoss=true, regen=600, bossBonus=3000, behavior="telegraph",
				titanId="warhammer",
				drops={"warhammer_frag","war_hammer_spike","refined_ore"},
				mechanic="crystal_construct",
				phases={
					[2]={hpThreshold=0.65, atkMult=1.20,
						msg="Lara retreats into a crystal construct! Destroy the barrier!",
						activateMechanic=true},
					[3]={hpThreshold=0.30, atkMult=1.30, regenMult=1.25,
						msg="The War Hammer Titan erects a second construct — and fights back!"},
				}},
		}},
	{id="ch7", name="The Rumbling Begins",
		desc="Eren has activated the Rumbling. Wall Titans march on the world.",
		unlockPrestige=2,
		enemies={
			{name="Wall Titan",       hp=18000,atk=240,xp=3200,funds=2000,tier="strong"},
			{name="Titan Battalion",  hp=25000,atk=270,xp=4500,funds=2800,tier="strong"},
			{name="Elder Wall Titan", hp=35000,atk=310,xp=6000,funds=3800,tier="boss", regen=500, behavior="armored"},
			{name="FOUNDING TITAN",   hp=80000,atk=480,xp=18000,funds=12000, tier="boss",
				isBoss=true, regen=1200, bossBonus=8000, behavior="telegraph",
				titanId="founding",
				drops={"founding_relic","coordinate_blade","founders_eye"},
				mechanic="coordinate_authority",
				phases={
					[2]={hpThreshold=0.60, atkMult=1.25, regenMult=1.20,
						msg="The Founding Titan's power surges — status effects begin!"},
					[3]={hpThreshold=0.30, atkMult=1.30,
						msg="The Coordinate activates! Reality itself fights back!",
						activateMechanic=true},
				}},
		}},
	{id="ch8", name="The Battle of Heaven and Earth",
		desc="The Alliance makes its final stand against Eren and the Rumbling.",
		unlockPrestige=3,
		enemies={
			{name="Yeagerist Vanguard",hp=28000,atk=300,xp=5000,funds=3200,tier="strong"},
			{name="Pure Titan Wave",   hp=32000,atk=320,xp=5800,funds=3600,tier="strong", behavior="aberrant"},
			{name="Armored Wall Titan",hp=45000,atk=370,xp=8000,funds=5000,tier="boss", regen=700, behavior="armored"},
			{name="EREN — FOUNDING",  hp=150000,atk=600,xp=30000,funds=20000, tier="boss",
				isBoss=true, regen=2000, bossBonus=15000, behavior="telegraph",
				titanId="founding",
				drops={"founders_eye","founding_relic","coordinate_blade","founding_robe"},
				-- Ch8 final boss: two stacked mechanics — coordinate_authority always active,
				-- crystal_hardening added at Phase 2 to force build diversity.
				mechanic="coordinate_authority",
				mechanicPhase2="crystal_hardening",
				phases={
					[2]={hpThreshold=0.65, atkMult=1.20, regenMult=1.15,
						msg="Eren hardens — the Coordinate AND crystal armour converge!",
						activateMechanic=true, activateMechanic2=true},
					[3]={hpThreshold=0.30, atkMult=1.30, regenMult=1.20,
						msg="FINAL FORM — Eren's power is absolute. Everything reflects!"},
				}},
		}},
}

-- Scale campaign enemy stats for prestige replay
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

-- ────────────────────────────────────────────────────────────
-- RAIDS
-- Unlocked by completing the specified campaign chapter.
-- Can be soloed or run co-op (up to 3 players).
-- Difficulty scales with party size and average prestige.
-- ────────────────────────────────────────────────────────────
D.RAIDS = {
	{id="raid_female",   name="Female Titan Raid",    titanId="female",
		desc="The Armored Female Titan rampages.",
		baseHp=8000,  baseAtk=160, xp=2000,  funds=1200, regen=200,
		unlockChapter=2, behavior="armored",
		drops={"titan_flesh","odm_elite","leonhart_ring"}},
	{id="raid_beast",    name="Beast Titan Raid",     titanId="beast",
		desc="The Beast Titan hurls boulders from the ridge.",
		baseHp=14000, baseAtk=220, xp=3500,  funds=2000, regen=350,
		unlockChapter=3, behavior="telegraph",
		drops={"beast_core","refined_ore","odm_legendary"}},
	{id="raid_armored",  name="Armored Titan Raid",   titanId="armored",
		desc="Armored Titan charges the gate.",
		baseHp=22000, baseAtk=290, xp=5500,  funds=3200, regen=500,
		unlockChapter=4, behavior="armored",
		drops={"armored_plate","elite_armour","marley_medal"}},
	{id="raid_colossal", name="Colossal Titan Raid",  titanId="colossal",
		desc="The Colossal Titan emerges from the Wall.",
		baseHp=40000, baseAtk=380, xp=9000,  funds=5500, regen=800,
		unlockChapter=5, behavior="telegraph",
		drops={"colossal_shard","odm_legendary","thunder_harness"}},
	{id="raid_jaw",      name="Jaw Titan Raid",       titanId="jaw",
		desc="The Jaw Titan strikes from above.",
		baseHp=18000, baseAtk=250, xp=4500,  funds=2800, regen=300,
		unlockChapter=3,
		drops={"titan_flesh","gas_canister","ackerman_ring"}},
	{id="raid_warhammer",name="War Hammer Raid",      titanId="warhammer",
		desc="Crystalline lances erupt from the ground.",
		baseHp=55000, baseAtk=420, xp=14000, funds=9000, regen=900,
		unlockChapter=6, behavior="telegraph",
		drops={"warhammer_frag","warhammer_spike","tybur_seal"}},
	{id="raid_founding", name="Founding Titan Siege", titanId="founding",
		desc="The Founding Titan's power echoes across the earth.",
		baseHp=120000,baseAtk=600, xp=25000, funds=16000,regen=2000,
		unlockChapter=7, behavior="telegraph",
		drops={"founding_relic","coordinate_blade","founders_eye","founding_robe"}},
}

-- Scale raid HP/ATK by party size and average prestige
function D.ScaleRaid(raid, partySize, avgPrestige)
	local ps = math.max(1, partySize or 1)
	local pr = math.max(0, avgPrestige or 0)
	local hpMult  = 1 + (ps - 1) * 0.70   -- +70% HP per extra player
	local atkMult = 1 + pr * 0.18
	return {
		hp    = math.floor(raid.baseHp  * hpMult * (1 + pr * 0.15)),
		atk   = math.floor(raid.baseAtk * atkMult),
		regen = math.floor((raid.regen or 0) * (1 + pr * 0.10)),
	}
end

-- ────────────────────────────────────────────────────────────
-- DROP TABLES
-- Items dropped after combat victory by enemy tier.
-- ────────────────────────────────────────────────────────────
D.DROP_TABLES = {
	weak = {
		{id="titan_flesh",   chance=0.40},
		{id="gas_canister",  chance=0.20},
		{id="recruit_uniform",chance=0.08},
		{id="odm_basic",     chance=0.05},
		{id="wing_pin",      chance=0.05},
	},
	medium = {
		{id="titan_flesh",   chance=0.35},
		{id="gas_canister",  chance=0.20},
		{id="refined_ore",   chance=0.12},
		{id="odm_survey",    chance=0.08},
		{id="survey_cloak",  chance=0.06},
		{id="survey_badge",  chance=0.04},
	},
	strong = {
		{id="titan_flesh",   chance=0.30},
		{id="refined_ore",   chance=0.18},
		{id="gas_canister",  chance=0.12},
		{id="odm_elite",     chance=0.08},
		{id="garrison_plate",chance=0.06},
		{id="thunder_blade", chance=0.04},
		{id="thunder_vest",  chance=0.03},
	},
	boss = {
		{id="refined_ore",   chance=0.25},
		{id="colossal_shard",chance=0.12},
		{id="odm_legendary", chance=0.08},
		{id="elite_armour",  chance=0.08},
		{id="thunder_harness",chance=0.06},
		{id="reiss_crown",   chance=0.04},
		{id="marley_medal",  chance=0.04},
		{id="founding_relic",chance=0.02},
	},
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

-- ────────────────────────────────────────────────────────────
-- ENEMY BEHAVIORS
-- Governs how enemy NPCs act on their turn.
-- ────────────────────────────────────────────────────────────
D.BEHAVIORS = {
	default    = "default",    -- standard attack every turn
	aberrant   = "aberrant",   -- random burst: sometimes skips, sometimes double-attacks
	crawler    = "crawler",    -- applies slow debuff on hit
	armored    = "armored",    -- takes 25% reduced damage, occasional power strike
	telegraph  = "telegraph",  -- telegraphs big attack one turn in advance
}

-- ────────────────────────────────────────────────────────────
-- ACHIEVEMENTS
-- Checked server-side on progression milestones.
-- ────────────────────────────────────────────────────────────
D.ACHIEVEMENTS = {
	{id="first_blood",   label="First Blood",        track="totalKills",     goal=1,     reward={xp=100}},
	{id="soldier",       label="Soldier",             track="totalKills",     goal=50,    reward={xp=500,  funds=1000}},
	{id="veteran",       label="Veteran",             track="totalKills",     goal=500,   reward={serums=1, funds=3000}},
	{id="titan_slayer",  label="Titan Slayer",        track="totalKills",     goal=2000,  reward={serums=2, vials=1}},
	{id="boss_hunter",   label="Boss Hunter",         track="bossKills",      goal=10,    reward={serums=1, funds=2000}},
	{id="boss_master",   label="Boss Master",         track="bossKills",      goal=50,    reward={serums=3, vials=1}},
	{id="first_prestige",label="Beyond the Walls",    track="prestige",       goal=1,     reward={serums=2, vials=2, funds=5000}},
	{id="paths_chosen",  label="The Paths",           track="prestige",       goal=2,     reward={serums=3, vials=3}},
	{id="rumbling",      label="The Rumbling",        track="prestige",       goal=5,     reward={serums=5, vials=5, funds=20000}},
	{id="pvp_debut",     label="PvP Debut",           track="pvpWins",        goal=1,     reward={funds=500}},
	{id="pvp_champion",  label="PvP Champion",        track="pvpWins",        goal=25,    reward={serums=2, funds=5000}},
	{id="streak_5",      label="Kill Streak",         track="bestStreak",     goal=5,     reward={funds=500}},
	{id="streak_20",     label="Unstoppable",         track="bestStreak",     goal=20,    reward={serums=1, funds=2000}},
	{id="titan_master",  label="Titan Master",        track="titanFusions",   goal=3,     reward={serums=2}},
	{id="max_level",     label="Survey Corps Elite",  track="level",          goal=100,   reward={serums=2, vials=2, funds=10000}},
}

-- ────────────────────────────────────────────────────────────
-- PVP
-- Turn-based duels. ELO-ranked. Players take alternating turns.
-- ────────────────────────────────────────────────────────────
D.PVP_STARTING_ELO    = 1000
D.PVP_ELO_WIN_BASE    = 25
D.PVP_ELO_LOSS_BASE   = 20
D.PVP_MAX_TURNS       = 20   -- if no winner by turn 20, higher HP % wins
D.PVP_INVITE_TIMEOUT  = 30   -- seconds before invite expires

function D.CalcEloChange(myElo, oppElo, won)
	local expected = 1 / (1 + 10 ^ ((oppElo - myElo) / 400))
	local k = 32
	local change = math.floor(k * ((won and 1 or 0) - expected))
	return math.max(-40, math.min(40, change))  -- clamp wild swings
end

-- ────────────────────────────────────────────────────────────
-- PRESTIGE TITLES
-- ────────────────────────────────────────────────────────────
D.PRESTIGE_TITLES = {
	[0]  = "Recruit",
	[1]  = "Survey Corps",
	[2]  = "Veteran Soldier",
	[3]  = "Titan Hunter",
	[4]  = "Wall Defender",
	[5]  = "Survey Elite",
	[6]  = "Titan Slayer",
	[7]  = "Corps Legend",
	[8]  = "Paths Walker",
	[9]  = "Rumbling Survivor",
	[10] = "Founding Blood",
}

function D.GetPrestigeTitle(prestige)
	return D.PRESTIGE_TITLES[prestige] or ("Prestige " .. prestige)
end

-- ────────────────────────────────────────────────────────────
-- ENDLESS MODE
-- Procedurally generated enemies for infinite grinding.
-- Every 10 floors is a boss. Scaling accelerates past floor 30.
-- ────────────────────────────────────────────────────────────
function D.EndlessEnemy(floor, prestige)
	prestige = prestige or 0
	local scale   = 1 + (floor - 1) * 0.18 + prestige * 0.25
		+ math.max(0, floor - 30) * 0.05
	local isBoss  = (floor % 10 == 0)
	local behav   = isBoss and (floor % 20 == 0 and "telegraph" or floor % 30 == 0 and "armored" or nil)
		or (floor % 3 == 0 and "aberrant" or floor % 5 == 0 and "crawler" or nil)
	return {
		name      = isBoss and ("FLOOR " .. floor .. " TITAN") or ("Floor " .. floor .. " Titan"),
		hp        = math.floor((isBoss and 4000 or 800) * scale),
		atk       = math.floor((isBoss and 120  or 40)  * scale),
		xp        = math.floor((isBoss and 800  or 160) * scale),
		funds     = math.floor((isBoss and 500  or 100) * scale),
		regen     = isBoss and math.floor(200 * scale) or nil,
		isBoss    = isBoss,
		tier      = isBoss and "boss" or "medium",
		bossBonus = isBoss and math.floor(200 * scale) or nil,
		behavior  = behav,
		isEndless = true,
		floor     = floor,
	}
end

-- ────────────────────────────────────────────────────────────
-- DAILY / WEEKLY CHALLENGES
-- ────────────────────────────────────────────────────────────
D.DAILY_CHALLENGES = {
	{id="dc_kills_10",    label="Titan Patrol",      type="kill",     goal=10,  reward={xp=800,  funds=500}},
	{id="dc_kills_25",    label="Extermination",     type="kill",     goal=25,  reward={xp=1500, funds=1000}},
	{id="dc_boss_1",      label="Hunt the Aberrant", type="bossKill", goal=1,   reward={xp=2000, funds=1500, serums=1}},
	{id="dc_spears_5",    label="Thunder Volley",    type="spearUse", goal=5,   reward={xp=1000, funds=800}},
	{id="dc_streak_10",   label="Killing Streak",    type="streak",   goal=10,  reward={xp=1200, funds=900}},
	{id="dc_titan_shift", label="Titan Awakening",   type="titanShift",goal=3,  reward={xp=1000, funds=600}},
}

D.WEEKLY_CHALLENGES = {
	{id="wc_kills_200",   label="Corpse Counter",    type="kill",     goal=200,  reward={serums=2, vials=1, funds=5000}},
	{id="wc_boss_10",     label="Boss Rush",         type="bossKill", goal=10,   reward={serums=3, funds=8000}},
	{id="wc_prestige",    label="The Paths",         type="prestige", goal=1,    reward={serums=5, vials=3, funds=15000}},
	{id="wc_pvp_5",       label="Blood Sport",       type="pvpWin",   goal=5,    reward={serums=2, vials=2, funds=6000}},
	{id="wc_raid_3",      label="Raid Veteran",      type="raidClear",goal=3,    reward={serums=4, vials=2, funds=10000}},
}

-- Returns {dailies, weeklies} for the given day number
-- Day seed rotates challenges so the same ones don't appear every day
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

-- ────────────────────────────────────────────────────────────
-- ADMIN IDS
-- Replace with real Roblox user IDs before publishing.
-- ────────────────────────────────────────────────────────────
D.ADMIN_IDS = {
	-- e.g. 12345678,  -- your Roblox user ID
}

-- ────────────────────────────────────────────────────────────
-- UPDATE LOG
-- ────────────────────────────────────────────────────────────
D.UPDATE_LOG = {
	{version="1.0.0", date="2025", entries={
		"Attack on Titan: Incremental — rebuilt from the ground up.",
		"NEW: 4 Prestige Paths — Eldian, Marleyan, Wandering, Royal",
		"NEW: 7 stats — Str, Def, Spd, Wil, Blade Mastery, Titan Affinity, Fortitude",
		"NEW: Clan Tiers — upgrade your clan up to Tier 3 for deeper traits",
		"NEW: Legendary clan active moves — Yeager, Ackerman, Reiss, Tybur",
		"NEW: Titan Leveling — feed XP to your titan slots",
		"NEW: Thunder Spears — craftable, consumable, pierce armour",
		"NEW: Boss Mechanics — every boss has a unique gimmick to overcome",
		"NEW: Co-op Raids — bring up to 3 allies against raid bosses",
		"NEW: PvP Duels — ELO-ranked turn-based player combat",
		"NEW: Endless Mode — infinitely scaling tower grind",
		"NEW: Full campaign — 8 chapters from Wall Maria to the Rumbling",
	}},
}

return D
