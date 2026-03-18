-- @ScriptType: ModuleScript
-- AOT_Sessions  (ModuleScript)
-- Place in: ServerScriptService > AOT_Sessions
-- Central hub: player save schema, DataStore I/O, all RemoteEvents/Functions,
-- stat calculation (CalcCS), payload builder (BuildPayload), and helpers.
-- Every other server module requires this; nothing requires them back.
-- v1.0.0

local DataStoreService = game:GetService("DataStoreService")
local RS               = game:GetService("ReplicatedStorage")
local AOT              = RS:WaitForChild("AOT", 10)
local D                = require(AOT:WaitForChild("AOT_Data"))

local S = {}

-- ────────────────────────────────────────────────────────────
-- DATASTORE
-- ────────────────────────────────────────────────────────────
S.DS = DataStoreService:GetDataStore("AOT_v1")

-- ────────────────────────────────────────────────────────────
-- REMOTES
-- All RemoteEvents and RemoteFunctions live here so that every
-- server module and the client reference the same objects.
-- ────────────────────────────────────────────────────────────
local RemFolder = AOT:FindFirstChild("Remotes") or (function()
	local f = Instance.new("Folder")
	f.Name   = "Remotes"
	f.Parent = AOT
	return f
end)()

local function RE(name)
	local r = RemFolder:FindFirstChild(name)
	if not r then
		r        = Instance.new("RemoteEvent")
		r.Name   = name
		r.Parent = RemFolder
	end
	return r
end

local function RF(name)
	local r = RemFolder:FindFirstChild(name)
	if not r then
		r        = Instance.new("RemoteFunction")
		r.Name   = name
		r.Parent = RemFolder
	end
	return r
end

-- ── State sync ────────────────────────────────────────────
S.RE_Push         = RE("Push")           -- server → client: full state snapshot
S.RE_Log          = RE("Log")            -- server → client: combat log message
S.RE_Notify       = RE("Notify")         -- server → client: popup notification
S.RE_EnemyAct     = RE("EnemyAction")    -- server → client: enemy turn animation cue

-- ── Combat ────────────────────────────────────────────────
S.RE_SelectMission= RE("SelectMission")  -- client → server: start a campaign/raid/quick battle
S.RE_CombatAction = RE("CombatAction")   -- client → server: player chooses a move
S.RE_Retreat      = RE("Retreat")        -- client → server: abandon current mission

-- ── Character ─────────────────────────────────────────────
S.RE_AllocStat    = RE("AllocStat")      -- client → server: spend a free stat point
S.RE_AllocMany    = RE("AllocStatMany")  -- client → server: spend multiple stat points at once
S.RE_Train        = RE("DoTraining")     -- client → server: convert trainingXP → stat point

-- ── Titans ────────────────────────────────────────────────
S.RE_RollTitan    = RE("RollTitan")      -- client → server: spend a serum
S.RE_EquipTitan   = RE("EquipTitan")     -- client → server: equip titan slot
S.RE_DiscardTitan = RE("DiscardTitan")   -- client → server: remove titan from slot
S.RE_FeedTitan    = RE("FeedTitan")      -- client → server: feed XP to a titan slot
S.RE_FuseTitans   = RE("FuseTitans")     -- client → server: fuse two titans

-- ── Items ─────────────────────────────────────────────────
S.RE_EquipItem    = RE("EquipItem")      -- client → server: equip weapon/armor/accessory
S.RE_SellItem     = RE("SellItem")       -- client → server: sell an inventory item
S.RE_ForgeItem    = RE("ForgeItem")      -- client → server: upgrade an equipped item
S.RE_CraftSpears  = RE("CraftSpears")    -- client → server: craft thunder spears

-- ── ODM ───────────────────────────────────────────────────
S.RE_UpgradeODM   = RE("UpgradeODM")    -- client → server: purchase ODM tier

-- ── Clans ─────────────────────────────────────────────────
S.RE_RollClan     = RE("RollClan")       -- client → server: spend a blood vial
S.RE_UpgradeClan  = RE("UpgradeClan")   -- client → server: spend vials to raise clan tier
S.RE_VIPClanReroll= RE("VIPClanReroll") -- client → server: VIP free daily clan reroll

-- ── Prestige ──────────────────────────────────────────────
S.RE_Prestige     = RE("Prestige")       -- client → server: initiate prestige
S.RE_ChoosePath   = RE("ChoosePath")    -- client → server: select prestige path

-- ── Shop / Economy ────────────────────────────────────────
S.RE_BuyProduct   = RE("BuyProduct")    -- client → server: DevProduct purchase callback
S.RE_BuyPass      = RE("BuyPass")       -- client → server: Gamepass purchase callback
S.RE_RedeemCode   = RE("RedeemCode")    -- client → server: promo code
S.RE_ShopBuy      = RE("ShopBuy")       -- client → server: buy from daily shop
S.RE_ShopReroll   = RE("ShopReroll")    -- client → server: reroll daily shop

-- ── Daily / Achievements ──────────────────────────────────
S.RE_ClaimDaily   = RE("ClaimDaily")    -- client → server: claim login streak reward
S.RE_ClaimAchieve = RE("ClaimAchieve")  -- client → server: claim achievement (auto in most cases)

-- ── PvP ───────────────────────────────────────────────────
S.RE_PVPChallenge = RE("PVPChallenge")  -- client → server: challenge a player to a duel
S.RE_PVPResponse  = RE("PVPResponse")   -- client → server: accept/decline a duel invite
S.RE_PVPAction    = RE("PVPAction")     -- client → server: take a turn in an active duel

-- ── Co-op Raids ───────────────────────────────────────────
S.RE_RaidInvite     = RE("RaidInvite")         -- client → server: invite player to raid party
S.RE_RaidInviteResp = RE("RaidInviteResponse") -- client → server: accept/decline raid invite
S.RE_RaidStart    = RE("RaidStart")     -- client → server: party leader starts the raid
S.RE_RaidAction   = RE("RaidAction")    -- client → server: take a turn in co-op raid
S.RE_RaidShift    = RE("RaidShift")     -- client → server: titan shift during raid
S.RE_RaidState    = RE("RaidState")     -- server → all clients: broadcast raid state

-- ── RemoteFunctions ───────────────────────────────────────
S.RF_GetState     = RF("GetState")      -- client ↔ server: initial state fetch on join
S.RF_GetLeaderboard= RF("GetLeaderboard")-- client ↔ server: leaderboard query

-- ────────────────────────────────────────────────────────────
-- RUNTIME TABLES
-- ────────────────────────────────────────────────────────────
S.sessions       = {}   -- [userId] = player data table (d)
S.raidParties    = {}   -- [partyId] = {leader, members, raidId, state}
S.pvpMatches     = {}   -- [matchId] = {p1Id, p2Id, turn, state}
S.pendingInvites = {}   -- [targetUserId] = {type, fromUserId, data, expiry}
-- Note: promo code redemption is persisted in d.redeemedCodes (per-player DataStore field)
-- S.codeUsed was the old in-memory approach and has been removed.

-- ────────────────────────────────────────────────────────────
-- PLAYER DATA SCHEMA
-- Blank() returns the canonical default player save.
-- Add every new field here with its default value.
-- ────────────────────────────────────────────────────────────
function S.Blank()
	return {
		-- ── Schema ──────────────────────────────────────────
		schemaVersion   = D.SCHEMA_VERSION,

		-- ── Character ───────────────────────────────────────
		level           = 1,
		xp              = 0,
		freeStatPoints  = 0,
		str             = 5,
		def             = 5,
		spd             = 5,
		wil             = 5,
		bladeMastery    = 0,   -- costs 2 stat points per rank; scales ODM + unlocks moves
		titanAffinity   = 0,   -- costs 2 stat points per rank; reduces heat + amplifies specials
		fortitude       = 0,   -- costs 2 stat points per rank; scales maxHp + status resist
		trainingXP      = 0,   -- pool spent in training menu for extra stat points
		funds           = 400,

		-- ── Prestige / Path ─────────────────────────────────
		prestige        = 0,
		path            = nil,     -- "eldian"|"marleyan"|"wandering"|"royal"|nil
		pathChosen      = false,   -- set true once path is chosen after prestige

		-- ── Titan system ────────────────────────────────────
		titanSlots      = {},      -- array of {id,name,rarity,bonus,titanLevel,titanXP}
		equippedTitan   = nil,     -- integer index into titanSlots
		titanSerums     = 0,
		titanPity       = 0,       -- pity counter (resets on Legendary+, see D.TITAN_PITY_*)
		titanFusions    = 0,

		-- ── Clan system ─────────────────────────────────────
		clan            = nil,     -- clan id string or nil
		clanTier        = 0,       -- 0–3
		clanVials       = 0,
		clanPity        = 0,       -- pity counter for clan rolls

		-- ── Inventory ───────────────────────────────────────
		inventory       = {},      -- array of {id, forgeLevel}
		equippedWeapon  = nil,
		equippedArmor   = nil,
		equippedAccessory = nil,
		thunderSpears   = 0,       -- consumable count
		odmGearLevel    = 0,       -- 0–6
		consumables     = {},      -- {[id] = count} for misc consumables
		pendingTitan    = nil,     -- titan rolled when slots full; claimed on next discard

		-- ── Mission progress ────────────────────────────────
		campaignChapter = 1,
		campaignEnemy   = 1,
		chapterClearCounts = {},   -- {[chapterId] = clearCount} for diminishing returns
		raidUnlocks     = {},      -- {[raidId] = true}
		raidHighScores  = {},      -- {[raidId] = bestFundsEarned}

		-- ── Progression / Stats ─────────────────────────────
		totalKills      = 0,
		bossKills       = 0,
		killStreak      = 0,
		bestStreak      = 0,
		endlessHighFloor = 0,  -- highest floor reached in endless mode
		achievementsClaimed = {},  -- {[achievementId] = true}
		redeemedCodes   = {},  -- {[codeId] = true} persisted per-player to survive restarts

		-- ── Daily / Login ───────────────────────────────────
		loginStreak     = 0,
		loginStreakBest = 0,
		lastLoginDay    = 0,       -- D.DayNumber() value of last login claim
		dailyChallengeDay = 0,
		dailyProgress   = {},
		dailyClaimed    = {},
		weeklyResetWeek = 0,
		weeklyProgress  = {},
		weeklyClaimed   = {},

		-- ── PvP ─────────────────────────────────────────────
		pvpElo          = D.PVP_STARTING_ELO,
		pvpWins         = 0,
		pvpLosses       = 0,

		-- ── Gamepasses ──────────────────────────────────────
		hasVIP          = false,
		hasPathsPass    = false,
		hasAutoTrain    = false,
		hasVault        = false,
		hasArsenal      = false,
		boostExpiry     = 0,       -- os.time() when active boost expires
		vipLastClanReroll   = 0,   -- os.time() of last VIP free clan reroll
		vaultLastWeeklySerum= 0,   -- os.time() of last Vault weekly serum

		-- ── Shop ────────────────────────────────────────────
		shopSeed        = 0,       -- determines today's shop rotation
		shopRerolled    = false,   -- reset each day

		-- ── Misc ────────────────────────────────────────────
		tutorialDone    = false,
		prestigeTitle   = "Recruit",

		-- ── Volatile fields (never saved — reset on join) ───
		-- Listed here as documentation; SAVE_SKIP below excludes them.
		-- hp, maxHp, inCombat, awaitingTurn, enemyHp, enemyMaxHp,
		-- enemyName, enemyAtk, enemyIsBoss, enemyTier, titanShifterMode,
		-- titanHeat, titanSuppressTurns, moveCooldowns, playerStatus,
		-- evasionActive, bossPhase2, raidPhase, nextAttackMult
	}
end

-- ────────────────────────────────────────────────────────────
-- VOLATILE RESET
-- Called on player join and at the start of each mission.
-- ────────────────────────────────────────────────────────────
function S.ResetVolatile(d)
	d.hp                  = d.maxHp or 100
	d.inCombat            = false
	d.awaitingTurn        = false
	d.enemyHp             = 0
	d.enemyMaxHp          = 0
	d.enemyName           = ""
	d.enemyIsBoss         = false
	d.enemyAtk            = 20
	d.enemyRegen          = nil
	d.enemyTier           = "weak"
	d.enemyBehavior       = nil
	d.enemyTitanId        = nil
	d.enemyBurnTurns      = 0
	d.enemyStunned        = false
	d.enemyFearTurns      = 0
	d.enemyAtkDebuffTurns = 0
	d.enemyAtkDebuffPct   = 0
	d.telegraphWindup     = false
	d.titanShifterMode    = false
	d.titanHeat           = 0
	d.titanSuppressTurns  = 0
	d.bossPhase2          = false
	d.bossPhase3          = false
	d.bossGimmickState    = {}
	d.bossActiveMechanic  = nil
	d.bossHeavyStreak     = 0
	d.evasionActive       = false
	d.wanderingEvadeTurns = 0
	d.wanderingCritPending= false
	d.nextAttackMult      = 1
	d.nextTitanSpecialBoost = 1
	d.tyburShieldHits     = 0
	d.tyburCounterDmgMult = 0
	d.playerBleedTurns    = 0
	d.playerSlowTurns     = 0
	d.playerFearTurns     = 0
	d._activeEnemy        = nil
	d.moveCooldowns       = {
		heavy_strike      = 0,
		recover           = 0,
		evasive_maneuver  = 0,
		spear_volley      = 0,
		odm_dash          = 0,
		advanced_slash    = 0,
		titan_kick        = 0,
		titan_roar        = 0,
		titan_special     = 0,
		-- clan/path actives reset each fight too
		yeager_coordinate = 0,
		ackerman_surge    = 0,
		reiss_royal_vow   = 0,
		tybur_war_hammer  = 0,
		eldian_coordinate = 0,
		marleyan_barrage  = 0,
		wandering_ghost_step = 0,
		royal_founding_scream = 0,
	}
end

-- ────────────────────────────────────────────────────────────
-- STAT CALCULATION  (CalcCS)
-- Returns a table of derived combat stats.
-- Called before every Push; result is not saved, always recalculated.
-- ────────────────────────────────────────────────────────────
function S.CalcCS(d)
	-- 1. Base stats (raw allocated values)
	local str          = d.str          or 5
	local def          = d.def          or 5
	local spd          = d.spd          or 5
	local wil          = d.wil          or 5
	local bladeMastery = d.bladeMastery or 0
	local titanAffinity= d.titanAffinity or 0
	local fortitude    = d.fortitude    or 0

	-- 2. Prestige flat passives
	local pp = D.GetPrestigePassiveTotals(d.prestige or 0)
	str           = str           + (pp.strFlat           or 0)
	def           = def           + (pp.defFlat           or 0)
	spd           = spd           + (pp.spdFlat           or 0)
	wil           = wil           + (pp.wilFlat           or 0)
	bladeMastery  = bladeMastery  + (pp.bladeMasteryFlat  or 0)
	titanAffinity = titanAffinity + (pp.titanAffinityFlat or 0)
	fortitude     = fortitude     + (pp.fortitudeFlat     or 0)

	-- 3. Equipped titan bonuses (softcapped at 60 per stat)
	if d.equippedTitan and d.titanSlots[d.equippedTitan] then
		local slot  = d.titanSlots[d.equippedTitan]
		local bn    = slot.bonus or {}
		local tLv   = slot.titanLevel or 0
		local tlGain= tLv * (D.TITAN_STAT_PER_LEVEL and D.TITAN_STAT_PER_LEVEL.str or 1)
		str           = str + D.SoftCap((bn.str           or 0) + tlGain, 60)
		def           = def + D.SoftCap((bn.def           or 0) + tlGain, 60)
		spd           = spd + D.SoftCap((bn.spd           or 0) + tlGain, 60)
		wil           = wil + D.SoftCap((bn.wil           or 0) + tlGain, 60)
		titanAffinity = titanAffinity + D.SoftCap((bn.titanAffinity or 0), 30)
	end

	-- 4. Equipped item bonuses (all seven stats + hp + forge bonus)
	local ib = {str=0,def=0,spd=0,wil=0,bladeMastery=0,titanAffinity=0,fortitude=0,hp=0,xpBonus=0}
	for _, slot in ipairs({d.equippedWeapon, d.equippedArmor, d.equippedAccessory}) do
		local item = slot and D.ITEM_MAP[slot]
		if item and item.bonus then
			for k, v in pairs(item.bonus) do
				if ib[k] ~= nil then ib[k] = ib[k] + v end
			end
			-- Forge bonus adds to all primary combat stats
			local forgeKey = slot .. "_forge"
			local fl = d.itemLevels and d.itemLevels[forgeKey] or 0
			if fl > 0 then
				local fb = fl * D.FORGE_BONUS_PER_LEVEL
				ib.str          = ib.str          + fb
				ib.def          = ib.def          + fb
				ib.spd          = ib.spd          + fb
				ib.wil          = ib.wil          + fb
				ib.bladeMastery = ib.bladeMastery + math.floor(fb * 0.5)
				ib.titanAffinity= ib.titanAffinity+ math.floor(fb * 0.5)
				ib.fortitude    = ib.fortitude    + math.floor(fb * 0.5)
			end
		end
	end
	str           = str           + ib.str
	def           = def           + ib.def
	spd           = spd           + ib.spd
	wil           = wil           + ib.wil
	bladeMastery  = bladeMastery  + ib.bladeMastery
	titanAffinity = titanAffinity + ib.titanAffinity
	fortitude     = fortitude     + ib.fortitude

	-- 5. Equipment set bonuses
	local sb = D.GetSetBonus(d.equippedWeapon, d.equippedArmor, d.equippedAccessory)
	str           = str           + (sb.str           or 0)
	def           = def           + (sb.def           or 0)
	spd           = spd           + (sb.spd           or 0)
	wil           = wil           + (sb.wil           or 0)

	-- 6. ODM gear bonuses
	if d.odmGearLevel and d.odmGearLevel > 0 then
		for _, up in ipairs(D.ODM_UPGRADES) do
			if up.tier <= d.odmGearLevel then
				for k, v in pairs(up.bonus) do
					if     k == "str"          then str           = str           + v
					elseif k == "def"          then def           = def           + v
					elseif k == "spd"          then spd           = spd           + v
					elseif k == "wil"          then wil           = wil           + v
					elseif k == "bladeMastery" then bladeMastery  = bladeMastery  + v
					end
				end
			end
		end
	end

	-- Wandering path: ODM gear bonuses multiplied
	if d.path == "wandering" then
		local odmMult = D.PATHS.wandering.passives.odmMult or 1.25
		bladeMastery = math.floor(bladeMastery * odmMult)
	end

	-- 7. Clan bonuses (all seven stats, scaled by tier)
	if d.clan then
		for _, cl in ipairs(D.CLAN_POOL) do
			if cl.id == d.clan then
				local tier     = math.min(d.clanTier or 0, 3)
				local tierData = cl.tiers[tier]
				if tierData and tierData.bonus then
					local mult = 1.0
					if d.path == "wandering" then
						mult = D.PATHS.wandering.passives.clanBonusMult or 1.30
					end
					for k, v in pairs(tierData.bonus) do
						local scaled = math.floor(v * mult)
						if     k == "str"          then str           = str           + scaled
						elseif k == "def"          then def           = def           + scaled
						elseif k == "spd"          then spd           = spd           + scaled
						elseif k == "wil"          then wil           = wil           + scaled
						elseif k == "bladeMastery" then bladeMastery  = bladeMastery  + scaled
						elseif k == "titanAffinity"then titanAffinity = titanAffinity + scaled
						elseif k == "fortitude"    then fortitude     = fortitude     + scaled
						end
					end
				end
				break
			end
		end
	end

	-- 8. Path bonuses
	-- (Royal HP bonus handled below; Eldian/Marleyan bonuses applied at combat resolution
	--  via D.PATHS references to keep CalcCS pure)

	-- 9. Final max HP  (fortitude is the primary HP stat now)
	local hpPerFort = D.STATS.fortitude.hpPerPoint or 8
	local maxHp = math.floor(
		D.BASE_HP
			+ fortitude * hpPerFort
			+ def       * 1.5          -- def still contributes a little
			+ wil       * 0.5          -- wil contributes a little (removed big mult)
			+ (d.level  or 1) * 5
			+ (ib.hp    or 0)
			+ (sb.maxHpBonus or 0)
	)
	if d.path == "royal" then
		maxHp = maxHp + (D.PATHS.royal.passives.maxHpFlatBonus or 200)
	end

	-- 10. XP / funds multipliers
	local xpMult   = 1
	local fundMult = 1
	if d.hasVIP then xpMult = xpMult * 2 fundMult = fundMult * 2 end
	if d.boostExpiry and os.time() < d.boostExpiry then
		xpMult   = xpMult   * 2
		fundMult = fundMult * 2
	end
	xpMult   = xpMult   * (1 + (pp.xpPct    or 0))
	fundMult = fundMult * (1 + (pp.fundsPct  or 0))

	-- 11. Kill streak XP multiplier (caps at ×2)
	local streakMult = math.min(2.0, 1 + (d.killStreak or 0) * 0.05)

	return {
		str           = math.max(1, str),
		def           = math.max(1, def),
		spd           = math.max(1, spd),
		wil           = math.max(1, wil),
		bladeMastery  = math.max(0, bladeMastery),
		titanAffinity = math.max(0, titanAffinity),
		fortitude     = math.max(0, fortitude),
		maxHp         = math.max(10, maxHp),
		xpMult        = xpMult,
		fundMult      = fundMult,
		streakMult    = streakMult,
		xpBonus       = ib.xpBonus or 0,
		spearDamageMult = (sb.spearDamageMult or 0)
			+ (d.path == "marleyan" and (D.PATHS.marleyan.passives.spearDamageMult - 1) or 0),
	}
end

-- ────────────────────────────────────────────────────────────
-- BUILD PAYLOAD
-- Constructs the safe client-facing snapshot from d + cs.
-- Never exposes raw d to the client; only include what the UI needs.
-- ────────────────────────────────────────────────────────────
function S.BuildPayload(d, cs)
	-- Resolve active set bonuses for display
	local activeSets = {}
	for _, set in ipairs(D.EQUIPMENT_SETS) do
		local equipped = {d.equippedWeapon, d.equippedArmor, d.equippedAccessory}
		local matches = 0
		for _, piece in ipairs(set.pieces) do
			for _, e in ipairs(equipped) do if e == piece then matches = matches + 1 break end end
		end
		if matches >= 2 then
			local bonus = matches >= 3 and set.threeBonus or set.twoBonus
			table.insert(activeSets, {name=set.name, pieces=matches, bonus=bonus})
		end
	end

	-- Active clan traits
	local clanTraits = {}
	if d.clan then
		for _, cl in ipairs(D.CLAN_POOL) do
			if cl.id == d.clan then
				local tier = math.min(d.clanTier or 0, 3)
				clanTraits = cl.tiers[tier] and cl.tiers[tier].traits or {}
				break
			end
		end
	end

	return {
		-- Character
		level           = d.level,
		xp              = d.xp,
		xpToNext        = D.XpToNext(d.level),
		freeStatPoints  = d.freeStatPoints,
		str             = d.str,  def=d.def, spd=d.spd, wil=d.wil,
		bladeMastery    = d.bladeMastery    or 0,
		titanAffinity   = d.titanAffinity   or 0,
		fortitude       = d.fortitude       or 0,
		trainingXP      = d.trainingXP,
		funds           = d.funds,
		hp              = d.hp,
		maxHp           = cs.maxHp,
		-- CalcCS results
		csStr           = cs.str,  csDef=cs.def, csSpd=cs.spd, csWil=cs.wil,
		csBladeMastery  = cs.bladeMastery,
		csTitanAffinity = cs.titanAffinity,
		csFortitude     = cs.fortitude,
		availableMoves  = D.GetAvailableMoves(d),
		xpMult          = cs.xpMult,
		fundMult        = cs.fundMult,
		streakMult      = cs.streakMult,
		spearDamageMult = cs.spearDamageMult,
		-- Prestige / Path
		prestige        = d.prestige,
		path            = d.path,
		pathChosen      = d.pathChosen,
		-- Titan
		titanSlots      = d.titanSlots,
		equippedTitan   = d.equippedTitan,
		titanSerums     = d.titanSerums,
		titanPity       = d.titanPity,
		titanFusions    = d.titanFusions,
		titanShifterMode= d.titanShifterMode,
		titanHeat       = d.titanHeat or 0,
		titanSuppressTurns= d.titanSuppressTurns or 0,
		-- Clan
		clan            = d.clan,
		clanTier        = d.clanTier,
		clanVials       = d.clanVials,
		clanPity        = d.clanPity,
		clanTraits      = clanTraits,
		-- Inventory
		inventory       = d.inventory,
		equippedWeapon  = d.equippedWeapon,
		equippedArmor   = d.equippedArmor,
		equippedAccessory= d.equippedAccessory,
		thunderSpears   = d.thunderSpears,
		odmGearLevel    = d.odmGearLevel,
		consumables     = d.consumables,
		itemLevels      = d.itemLevels,
		activeSets      = activeSets,
		-- Mission
		campaignChapter = d.campaignChapter,
		campaignEnemy   = d.campaignEnemy,
		raidUnlocks     = d.raidUnlocks,
		raidHighScores  = d.raidHighScores,
		-- Combat (volatile, shown during fight)
		inCombat        = d.inCombat,
		awaitingTurn    = d.awaitingTurn,
		enemyHp         = d.enemyHp,
		enemyMaxHp      = d.enemyMaxHp,
		enemyName       = d.enemyName,
		enemyIsBoss     = d.enemyIsBoss,
		bossPhase2      = d.bossPhase2,
		bossPhase3      = d.bossPhase3,
		evasionActive   = d.evasionActive,
		moveCooldowns   = d.moveCooldowns,
		playerBleedTurns= d.playerBleedTurns or 0,
		playerSlowTurns = d.playerSlowTurns  or 0,
		playerFearTurns = d.playerFearTurns  or 0,
		-- Progression
		totalKills      = d.totalKills,
		bossKills       = d.bossKills,
		killStreak      = d.killStreak,
		bestStreak      = d.bestStreak,
		endlessHighFloor= d.endlessHighFloor or 0,
		achievementsClaimed= d.achievementsClaimed,
		-- Daily
		loginStreak     = d.loginStreak,
		loginStreakBest = d.loginStreakBest,
		lastLoginDay    = d.lastLoginDay,
		dailyProgress   = d.dailyProgress,
		dailyClaimed    = d.dailyClaimed,
		weeklyProgress  = d.weeklyProgress,
		weeklyClaimed   = d.weeklyClaimed,
		-- PvP
		pvpElo          = d.pvpElo,
		pvpWins         = d.pvpWins,
		pvpLosses       = d.pvpLosses,
		-- Gamepasses
		hasVIP          = d.hasVIP,
		hasPathsPass    = d.hasPathsPass,
		hasAutoTrain    = d.hasAutoTrain,
		hasVault        = d.hasVault,
		hasArsenal      = d.hasArsenal,
		boostActive     = os.time() < (d.boostExpiry or 0),
		boostSecsLeft   = math.max(0, (d.boostExpiry or 0) - os.time()),
		-- Shop
		shopSeed        = d.shopSeed,
		shopRerolled    = d.shopRerolled,
		-- Misc
		tutorialDone    = d.tutorialDone,
		prestigeTitle   = d.prestigeTitle,
	}
end

-- ────────────────────────────────────────────────────────────
-- PUSH
-- Recalculate CS, clamp HP, fire state to client.
-- ────────────────────────────────────────────────────────────
function S.Push(player, d)
	local cs  = S.CalcCS(d)
	d.maxHp   = cs.maxHp
	d.hp      = math.min(d.hp or d.maxHp, d.maxHp)
	S.RE_Push:FireClient(player, S.BuildPayload(d, cs), cs)
end

-- ────────────────────────────────────────────────────────────
-- HELPERS
-- ────────────────────────────────────────────────────────────
function S.Msg(player, text, msgType)
	S.RE_Log:FireClient(player, text, msgType or "system")
end

-- S.Pop is the preferred notification shorthand (maps to RE_Notify)
function S.Pop(player, title, body, color)
	S.RE_Notify:FireClient(player, title, body, color or "amber")
end

function S.Notify(player, title, body, color)
	S.RE_Notify:FireClient(player, title, body, color or "amber")
end

function S.GetD(player)
	return S.sessions[player.UserId]
end

-- Award XP to player, handle level-ups, return levels gained
function S.AwardXP(player, d, rawXp, cs)
	if not cs then cs = S.CalcCS(d) end
	local gained = math.floor(rawXp * cs.xpMult * cs.streakMult + (cs.xpBonus or 0))
	local levelsGained = 0

	d.xp         = (d.xp         or 0) + gained
	d.trainingXP = (d.trainingXP or 0) + gained

	while (d.level or 1) < D.MAX_LEVEL do
		local needed = D.XpToNext(d.level)
		if d.xp >= needed then
			d.xp             = d.xp - needed
			d.level          = d.level + 1
			d.freeStatPoints = (d.freeStatPoints or 0) + D.STAT_POINTS_PER_LEVEL
			levelsGained     = levelsGained + 1
			S.Msg(player, "== LEVEL UP! Level " .. d.level
				.. " — +" .. D.STAT_POINTS_PER_LEVEL .. " stat points! ==", "level")
		else
			break
		end
	end

	return gained, levelsGained
end

-- Award funds to player
function S.AwardFunds(player, d, rawFunds, cs)
	if not cs then cs = S.CalcCS(d) end
	local gained = math.floor(rawFunds * cs.fundMult)
	d.funds = (d.funds or 0) + gained
	return gained
end

-- ────────────────────────────────────────────────────────────
-- CHALLENGE PROGRESS
-- Call after any action that counts toward daily/weekly goals.
-- ────────────────────────────────────────────────────────────
function S.BumpChallenge(player, d, challengeType, amount)
	d.dailyProgress  = d.dailyProgress  or {}
	d.weeklyProgress = d.weeklyProgress or {}
	local day        = D.DayNumber()

	-- Reset daily progress if it's a new day
	if (d.dailyChallengeDay or 0) ~= day then
		d.dailyChallengeDay = day
		d.dailyProgress     = {}
		d.dailyClaimed      = {}
		local weekNum = math.floor(day / 7)
		if (d.weeklyResetWeek or 0) ~= weekNum then
			d.weeklyResetWeek = weekNum
			d.weeklyProgress  = {}
			d.weeklyClaimed   = {}
		end
	end

	local dailies, weeklies = D.GetActiveChallenges(day)
	for _, ch in ipairs(dailies) do
		if ch.type == challengeType then
			d.dailyProgress[ch.id] = (d.dailyProgress[ch.id] or 0) + (amount or 1)
			-- Auto-claim when goal met (rewards applied here, flag prevents duplicate)
			if d.dailyProgress[ch.id] >= ch.goal and not (d.dailyClaimed or {})[ch.id] then
				d.dailyClaimed = d.dailyClaimed or {}
				d.dailyClaimed[ch.id] = true
				local r = ch.reward
				if r.xp    then d.xp          = (d.xp         or 0) + r.xp    end
				if r.funds then d.funds        = (d.funds      or 0) + r.funds end
				if r.serums then d.titanSerums = (d.titanSerums or 0) + r.serums end
				if r.vials  then d.clanVials   = (d.clanVials   or 0) + r.vials  end
				S.Msg(player, "DAILY CHALLENGE COMPLETE: " .. ch.label
					.. "  +" .. (r.funds or 0) .. " Funds  +" .. (r.xp or 0) .. " XP", "reward")
				S.Pop(player, "DAILY COMPLETE", ch.label, "amber")
			end
		end
	end
	for _, ch in ipairs(weeklies) do
		if ch.type == challengeType then
			d.weeklyProgress[ch.id] = (d.weeklyProgress[ch.id] or 0) + (amount or 1)
			if d.weeklyProgress[ch.id] >= ch.goal and not (d.weeklyClaimed or {})[ch.id] then
				d.weeklyClaimed = d.weeklyClaimed or {}
				d.weeklyClaimed[ch.id] = true
				local r = ch.reward
				if r.xp     then d.xp          = (d.xp          or 0) + r.xp     end
				if r.funds  then d.funds        = (d.funds       or 0) + r.funds  end
				if r.serums then d.titanSerums  = (d.titanSerums  or 0) + r.serums end
				if r.vials  then d.clanVials    = (d.clanVials    or 0) + r.vials  end
				S.Msg(player, "WEEKLY CHALLENGE COMPLETE: " .. ch.label
					.. "  +" .. (r.funds or 0) .. " Funds  +" .. (r.serums or 0) .. " Serums", "reward")
				S.Pop(player, "WEEKLY COMPLETE", ch.label, "amber")
			end
		end
	end
end

-- ────────────────────────────────────────────────────────────
-- ACHIEVEMENT CHECKER
-- Call after any progression-changing event.
-- ────────────────────────────────────────────────────────────
function S.CheckAchievements(player, d)
	if not d.achievementsClaimed then d.achievementsClaimed = {} end
	local progress = {
		totalKills      = d.totalKills      or 0,
		bossKills       = d.bossKills       or 0,
		prestige        = d.prestige        or 0,
		pvpWins         = d.pvpWins         or 0,
		bestStreak      = d.bestStreak      or 0,
		titanFusions    = d.titanFusions    or 0,
		level           = d.level           or 1,
		endlessHighFloor= d.endlessHighFloor or 0,
	}
	for _, ach in ipairs(D.ACHIEVEMENTS) do
		if not d.achievementsClaimed[ach.id] then
			local val = progress[ach.track] or 0
			if val >= ach.goal then
				d.achievementsClaimed[ach.id] = true
				-- Apply rewards
				local rewStr = ""
				for stat, bonus in pairs(ach.reward) do
					if stat == "serums" then
						d.titanSerums = (d.titanSerums or 0) + bonus
					elseif stat == "vials" then
						d.clanVials = (d.clanVials or 0) + bonus
					elseif stat == "xp" then
						d.xp = (d.xp or 0) + bonus
					elseif stat == "funds" then
						d.funds = (d.funds or 0) + bonus
					end
					rewStr = rewStr .. "+" .. bonus .. " " .. stat:upper() .. "  "
				end
				S.Msg(player, "== ACHIEVEMENT: " .. ach.label .. "!  " .. rewStr .. " ==", "system")
				S.Notify(player, "ACHIEVEMENT UNLOCKED", ach.label .. "\n" .. rewStr, "amber")
			end
		end
	end
end

-- ────────────────────────────────────────────────────────────
-- GetPrestigeTitle delegates to D so there's one source of truth
function S.GetPrestigeTitle(prestige)
	return D.GetPrestigeTitle(prestige)
end

-- ────────────────────────────────────────────────────────────
-- SAVE / LOAD
-- Fields in SAVE_SKIP are volatile and are never persisted.
-- ────────────────────────────────────────────────────────────
local SAVE_SKIP = {
	-- Volatile combat state
	hp=1, inCombat=1, awaitingTurn=1,
	enemyHp=1, enemyMaxHp=1, enemyName=1, enemyIsBoss=1,
	enemyAtk=1, enemyRegen=1, enemyTier=1, enemyBehavior=1, enemyTitanId=1,
	enemyBurnTurns=1, enemyStunned=1, enemyFearTurns=1,
	enemyAtkDebuffTurns=1, enemyAtkDebuffPct=1,
	telegraphWindup=1,
	titanShifterMode=1, titanHeat=1, titanSuppressTurns=1,
	bossPhase2=1, bossPhase3=1,
	bossGimmickState=1, bossActiveMechanic=1, bossHeavyStreak=1,
	evasionActive=1, wanderingEvadeTurns=1, wanderingCritPending=1,
	nextAttackMult=1, nextTitanSpecialBoost=1,
	tyburShieldHits=1, tyburCounterDmgMult=1,
	playerBleedTurns=1, playerSlowTurns=1, playerFearTurns=1,
	moveCooldowns=1, _activeEnemy=1,
	endlessFloor=1,    -- resets each server session; endlessHighFloor is persisted
	boostFreeForgeUsed=1,  -- {[itemId]=true} resets per session, not per save
	-- Derived — always recalculated
	maxHp=1,
}

function S.Save(userId, d)
	local payload = {}
	for k, v in pairs(d) do
		if not SAVE_SKIP[k] then
			payload[k] = v
		end
	end
	local ok, err = pcall(function()
		S.DS:SetAsync(D.DATASTORE_KEY .. userId, payload)
	end)
	if not ok then
		warn("[AOT_Sessions] Save failed for " .. userId .. ": " .. tostring(err))
	end
end

function S.Load(userId)
	local ok, saved = pcall(function()
		return S.DS:GetAsync(D.DATASTORE_KEY .. userId)
	end)

	local blank = S.Blank()

	if not ok or not saved then
		return blank
	end

	-- ── Migration ──────────────────────────────────────────
	-- Fill in any new fields the saved data doesn't have yet.
	for k, v in pairs(blank) do
		if saved[k] == nil then
			saved[k] = v
		end
	end

	-- Schema version upgrades
	local sv = saved.schemaVersion or 0
	if sv < 1 then
		-- v0 → v1: rename clanSerums → clanVials
		if saved.clanSerums and not saved.clanVials then
			saved.clanVials  = saved.clanSerums
			saved.clanSerums = nil
		end
		if not saved.clanTier then saved.clanTier = 0 end
		saved.schemaVersion = 1
	end
	if sv < 2 then
		-- v1 → v2: new stats default to 0 (already handled by blank fill-in above,
		-- but explicit here for clarity)
		saved.bladeMastery  = saved.bladeMastery  or 0
		saved.titanAffinity = saved.titanAffinity or 0
		saved.fortitude     = saved.fortitude     or 0
		saved.endlessHighFloor = saved.endlessHighFloor or 0
		saved.redeemedCodes = saved.redeemedCodes or {}
		-- Migrate old hp-based item bonuses (items now use fortitude for HP)
		-- No data change needed — item bonus tables were updated in AOT_Data
		saved.schemaVersion = 2
	end
	-- Future migrations go here:
	-- if sv < 3 then ... saved.schemaVersion = 3 end

	-- ── DataStore integer key fix ──────────────────────────
	-- DataStore serialises integer array keys as strings.
	-- Rebuild titanSlots as a clean integer-indexed array.
	if saved.titanSlots then
		local clean = {}
		for _, v in pairs(saved.titanSlots) do
			if type(v) == "table" and v.id then
				table.insert(clean, v)
			end
		end
		saved.titanSlots = clean
	end

	-- Normalise equippedTitan to integer, clamp to valid range
	if saved.equippedTitan ~= nil then
		saved.equippedTitan = tonumber(saved.equippedTitan)
		if saved.equippedTitan then
			local slotCount = #(saved.titanSlots or {})
			if saved.equippedTitan < 1 or saved.equippedTitan > slotCount then
				saved.equippedTitan = slotCount > 0 and 1 or nil
			end
		end
	end

	-- Clamp campaign pointers to valid ranges
	local chapter = saved.campaignChapter or 1
	chapter = math.max(1, math.min(chapter, #D.CAMPAIGN))
	saved.campaignChapter = chapter
	local ch = D.CAMPAIGN[chapter]
	if ch and (saved.campaignEnemy or 1) > #ch.enemies then
		saved.campaignEnemy   = 1
		saved.campaignChapter = math.min(chapter + 1, #D.CAMPAIGN)
	end

	return saved
end

return S
