-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- AOT_Sessions (Optimized & Secured)
-- Place in: ServerScriptService > AOT_Sessions

local DataStoreService = game:GetService("DataStoreService")
local RS               = game:GetService("ReplicatedStorage")
local AOT              = RS:WaitForChild("AOT", 10)
local D                = require(AOT:WaitForChild("AOT_Data"))

local S = {}

-- ============================================================================
-- 1. DATASTORE & REMOTES SETUP
-- ============================================================================
S.DS = DataStoreService:GetDataStore("AOT_v1")

local RemFolder = AOT:FindFirstChild("Remotes") or (function()
	local f = Instance.new("Folder")
	f.Name, f.Parent = "Remotes", AOT
	return f
end)()

local function RE(name)
	local r = RemFolder:FindFirstChild(name)
	if not r then r = Instance.new("RemoteEvent"); r.Name = name; r.Parent = RemFolder end
	return r
end

local function RF(name)
	local r = RemFolder:FindFirstChild(name)
	if not r then r = Instance.new("RemoteFunction"); r.Name = name; r.Parent = RemFolder end
	return r
end

-- Remote Declarations
S.RE_Push         = RE("Push")
S.RE_Log          = RE("Log")
S.RE_Notify       = RE("Notify")
S.RE_EnemyAct     = RE("EnemyAction")
S.RE_SelectMission= RE("SelectMission")
S.RE_CombatAction = RE("CombatAction")
S.RE_Retreat      = RE("Retreat")
S.RE_AllocStat    = RE("AllocStat")
S.RE_AllocMany    = RE("AllocStatMany")
S.RE_Train        = RE("DoTraining")
S.RE_RollTitan    = RE("RollTitan")
S.RE_EquipTitan   = RE("EquipTitan")
S.RE_DiscardTitan = RE("DiscardTitan")
S.RE_FeedTitan    = RE("FeedTitan")
S.RE_FuseTitans   = RE("FuseTitans")
S.RE_EquipItem    = RE("EquipItem")
S.RE_SellItem     = RE("SellItem")
S.RE_ForgeItem    = RE("ForgeItem")
S.RE_CraftSpears  = RE("CraftSpears")
S.RE_UpgradeODM   = RE("UpgradeODM")
S.RE_RollClan     = RE("RollClan")
S.RE_UpgradeClan  = RE("UpgradeClan")
S.RE_VIPClanReroll= RE("VIPClanReroll")
S.RE_Prestige     = RE("Prestige")
S.RE_ChoosePath   = RE("ChoosePath")
S.RE_BuyProduct   = RE("BuyProduct")
S.RE_BuyPass      = RE("BuyPass")
S.RE_RedeemCode   = RE("RedeemCode")
S.RE_ShopBuy      = RE("ShopBuy")
S.RE_ShopReroll   = RE("ShopReroll")
S.RE_ClaimDaily   = RE("ClaimDaily")
S.RE_ClaimAchieve = RE("ClaimAchieve")
S.RE_PVPChallenge = RE("PVPChallenge")
S.RE_PVPResponse  = RE("PVPResponse")
S.RE_PVPAction    = RE("PVPAction")
S.RE_RaidInvite   = RE("RaidInvite")
S.RE_RaidInviteResp= RE("RaidInviteResponse")
S.RE_RaidStart    = RE("RaidStart")
S.RE_RaidAction   = RE("RaidAction")
S.RE_RaidShift    = RE("RaidShift")
S.RE_RaidState    = RE("RaidState")
S.RF_GetState     = RF("GetState")
S.RF_GetLeaderboard= RF("GetLeaderboard")

-- Runtime Tables
S.sessions       = {}
S.raidParties    = {}
S.pvpMatches     = {}
S.pendingInvites = {}

-- ============================================================================
-- 2. SCHEMA & VOLATILE RESET
-- ============================================================================
function S.Blank()
	return {
		schemaVersion = D.SCHEMA_VERSION,
		level = 1, xp = 0, freeStatPoints = 0, str = 5, def = 5, spd = 5, wil = 5,
		bladeMastery = 0, titanAffinity = 0, fortitude = 0, trainingXP = 0, funds = 400,
		prestige = 0, path = nil, pathChosen = false,
		titanSlots = {}, equippedTitan = nil, titanSerums = 0, titanPity = 0, titanFusions = 0,
		clan = nil, clanTier = 0, clanVials = 0, clanPity = 0,
		inventory = {}, equippedWeapon = nil, equippedArmor = nil, equippedAccessory = nil,
		thunderSpears = 0, odmGearLevel = 0, consumables = {}, pendingTitan = nil, itemLevels = {},
		campaignChapter = 1, campaignEnemy = 1, chapterClearCounts = {}, raidUnlocks = {}, raidHighScores = {},
		totalKills = 0, bossKills = 0, killStreak = 0, bestStreak = 0, endlessHighFloor = 0, achievementsClaimed = {}, redeemedCodes = {},
		loginStreak = 0, loginStreakBest = 0, lastLoginDay = 0, dailyChallengeDay = 0, dailyProgress = {}, dailyClaimed = {}, weeklyResetWeek = 0, weeklyProgress = {}, weeklyClaimed = {},
		pvpElo = D.PVP_STARTING_ELO, pvpWins = 0, pvpLosses = 0,
		hasVIP = false, hasPathsPass = false, hasAutoTrain = false, hasVault = false, hasArsenal = false, boostExpiry = 0, vipLastClanReroll = 0, vaultLastWeeklySerum = 0,
		shopSeed = 0, shopRerolled = false, tutorialDone = false, prestigeTitle = "Recruit"
	}
end

function S.ResetVolatile(d)
	d.hp, d.inCombat, d.awaitingTurn = d.maxHp or 100, false, false
	d.enemyHp, d.enemyMaxHp, d.enemyName, d.enemyIsBoss, d.enemyAtk = 0, 0, "", false, 20
	d.enemyRegen, d.enemyTier, d.enemyBehavior, d.enemyTitanId = nil, "weak", nil, nil
	d.enemyBurnTurns, d.enemyStunned, d.enemyFearTurns, d.enemyAtkDebuffTurns, d.enemyAtkDebuffPct = 0, false, 0, 0, 0
	d.telegraphWindup, d.titanShifterMode, d.titanHeat, d.titanSuppressTurns = false, false, 0, 0
	d.bossPhase2, d.bossPhase3, d.bossGimmickState, d.bossActiveMechanic, d.bossHeavyStreak = false, false, {}, nil, 0
	d.evasionActive, d.wanderingEvadeTurns, d.wanderingCritPending = false, 0, false
	d.nextAttackMult, d.nextTitanSpecialBoost, d.tyburShieldHits, d.tyburCounterDmgMult = 1, 1, 0, 0
	d.playerBleedTurns, d.playerSlowTurns, d.playerFearTurns, d._activeEnemy = 0, 0, 0, nil
	d.moveCooldowns = {}
end

-- ============================================================================
-- 3. STAT CALCULATION ENGINE (Highly Optimized)
-- ============================================================================
function S.CalcCS(d)
	local str = d.str or 5
	local def = d.def or 5
	local spd = d.spd or 5
	local wil = d.wil or 5
	local bladeMastery = d.bladeMastery or 0
	local titanAffinity = d.titanAffinity or 0
	local fortitude = d.fortitude or 0

	-- Prestige Passives
	local pp = D.GetPrestigePassiveTotals(d.prestige or 0)
	str, def, spd, wil = str + pp.strFlat, def + pp.defFlat, spd + pp.spdFlat, wil + pp.wilFlat
	bladeMastery = bladeMastery + pp.bladeMasteryFlat
	titanAffinity = titanAffinity + pp.titanAffinityFlat
	fortitude = fortitude + pp.fortitudeFlat

	-- Equipped Titan Bonuses
	if d.equippedTitan and d.titanSlots[d.equippedTitan] then
		local slot = d.titanSlots[d.equippedTitan]
		local tlGain = (slot.titanLevel or 0) * (D.TITAN_STAT_PER_LEVEL.str or 1)
		str = str + D.SoftCap(((slot.bonus and slot.bonus.str) or 0) + tlGain, 60)
		def = def + D.SoftCap(((slot.bonus and slot.bonus.def) or 0) + tlGain, 60)
		spd = spd + D.SoftCap(((slot.bonus and slot.bonus.spd) or 0) + tlGain, 60)
		wil = wil + D.SoftCap(((slot.bonus and slot.bonus.wil) or 0) + tlGain, 60)
		titanAffinity = titanAffinity + D.SoftCap(((slot.bonus and slot.bonus.titanAffinity) or 0), 30)
	end

	-- Equipment Bonuses (O(1) lookups via D.ITEM_MAP)
	local ib = {str=0, def=0, spd=0, wil=0, bladeMastery=0, titanAffinity=0, fortitude=0, hp=0, xpBonus=0}
	for _, slotId in ipairs({d.equippedWeapon, d.equippedArmor, d.equippedAccessory}) do
		local item = slotId and D.ITEM_MAP[slotId]
		if item and item.bonus then
			for k, v in pairs(item.bonus) do if ib[k] ~= nil then ib[k] = ib[k] + v end end
			local fl = (d.itemLevels and d.itemLevels[slotId .. "_forge"]) or 0
			if fl > 0 then
				local fb = fl * D.FORGE_BONUS_PER_LEVEL
				local halfFb = math.floor(fb * 0.5)
				ib.str, ib.def, ib.spd, ib.wil = ib.str + fb, ib.def + fb, ib.spd + fb, ib.wil + fb
				ib.bladeMastery, ib.titanAffinity, ib.fortitude = ib.bladeMastery + halfFb, ib.titanAffinity + halfFb, ib.fortitude + halfFb
			end
		end
	end

	str = str + ib.str; def = def + ib.def; spd = spd + ib.spd; wil = wil + ib.wil
	bladeMastery = bladeMastery + ib.bladeMastery; titanAffinity = titanAffinity + ib.titanAffinity; fortitude = fortitude + ib.fortitude

	-- Set Bonuses & ODM Gear
	local sb = D.GetSetBonus(d.equippedWeapon, d.equippedArmor, d.equippedAccessory)
	str, def, spd, wil = str + (sb.str or 0), def + (sb.def or 0), spd + (sb.spd or 0), wil + (sb.wil or 0)

	if (d.odmGearLevel or 0) > 0 then
		for _, up in ipairs(D.ODM_UPGRADES) do
			if up.tier <= d.odmGearLevel then
				for k, v in pairs(up.bonus) do
					if k == "str" then str = str + v elseif k == "def" then def = def + v elseif k == "spd" then spd = spd + v elseif k == "wil" then wil = wil + v elseif k == "bladeMastery" then bladeMastery = bladeMastery + v end
				end
			end
		end
	end

	-- Clan & Path Modifiers
	if d.path == "wandering" then bladeMastery = math.floor(bladeMastery * (D.PATHS.wandering.passives.odmMult or 1.25)) end

	if d.clan then
		for _, cl in ipairs(D.CLAN_POOL) do
			if cl.id == d.clan then
				local tierData = cl.tiers[math.min(d.clanTier or 0, 3)]
				if tierData and tierData.bonus then
					local mult = d.path == "wandering" and (D.PATHS.wandering.passives.clanBonusMult or 1.30) or 1.0
					for k, v in pairs(tierData.bonus) do
						local scaled = math.floor(v * mult)
						if k == "str" then str = str + scaled elseif k == "def" then def = def + scaled elseif k == "spd" then spd = spd + scaled elseif k == "wil" then wil = wil + scaled elseif k == "bladeMastery" then bladeMastery = bladeMastery + scaled elseif k == "titanAffinity" then titanAffinity = titanAffinity + scaled elseif k == "fortitude" then fortitude = fortitude + scaled end
					end
				end
				break
			end
		end
	end

	-- Max HP Calculation
	local maxHp = math.floor(D.BASE_HP + (fortitude * D.STATS.fortitude.hpPerPoint) + (def * 1.5) + (wil * 0.5) + ((d.level or 1) * 5) + ib.hp + (sb.maxHpBonus or 0))
	if d.path == "royal" then maxHp = maxHp + (D.PATHS.royal.passives.maxHpFlatBonus or 200) end

	-- Multipliers
	local xpMult, fundMult = 1, 1
	if d.hasVIP then xpMult, fundMult = xpMult * 2, fundMult * 2 end
	if d.boostExpiry and os.time() < d.boostExpiry then xpMult, fundMult = xpMult * 2, fundMult * 2 end
	xpMult = xpMult * (1 + pp.xpPct)
	fundMult = fundMult * (1 + pp.fundsPct)

	return {
		str = math.max(1, str), def = math.max(1, def), spd = math.max(1, spd), wil = math.max(1, wil),
		bladeMastery = math.max(0, bladeMastery), titanAffinity = math.max(0, titanAffinity), fortitude = math.max(0, fortitude),
		maxHp = math.max(10, maxHp), xpMult = xpMult, fundMult = fundMult, streakMult = math.min(2.0, 1 + (d.killStreak or 0) * 0.05),
		xpBonus = ib.xpBonus or 0, spearDamageMult = (sb.spearDamageMult or 0) + (d.path == "marleyan" and (D.PATHS.marleyan.passives.spearDamageMult - 1) or 0)
	}
end

-- ============================================================================
-- 4. PAYLOAD BUILDER & HELPERS
-- ============================================================================
function S.BuildPayload(d, cs)
	local activeSets, clanTraits = {}, {}
	for _, set in ipairs(D.EQUIPMENT_SETS) do
		local matches = 0
		for _, piece in ipairs(set.pieces) do
			if d.equippedWeapon == piece or d.equippedArmor == piece or d.equippedAccessory == piece then matches = matches + 1 end
		end
		if matches >= 2 then table.insert(activeSets, {name=set.name, pieces=matches, bonus=(matches >= 3 and set.threeBonus or set.twoBonus)}) end
	end

	if d.clan then
		for _, cl in ipairs(D.CLAN_POOL) do
			if cl.id == d.clan then clanTraits = (cl.tiers[math.min(d.clanTier or 0, 3)] and cl.tiers[math.min(d.clanTier or 0, 3)].traits) or {} break end
		end
	end

	return {
		level = d.level, xp = d.xp, xpToNext = D.XpToNext(d.level), freeStatPoints = d.freeStatPoints,
		str = d.str, def = d.def, spd = d.spd, wil = d.wil, bladeMastery = d.bladeMastery, titanAffinity = d.titanAffinity, fortitude = d.fortitude,
		trainingXP = d.trainingXP, funds = d.funds, hp = d.hp, maxHp = cs.maxHp,
		csStr = cs.str, csDef = cs.def, csSpd = cs.spd, csWil = cs.wil, csBladeMastery = cs.bladeMastery, csTitanAffinity = cs.titanAffinity, csFortitude = cs.fortitude,
		availableMoves = D.GetAvailableMoves(d), xpMult = cs.xpMult, fundMult = cs.fundMult, streakMult = cs.streakMult, spearDamageMult = cs.spearDamageMult,
		prestige = d.prestige, path = d.path, pathChosen = d.pathChosen,
		titanSlots = d.titanSlots, equippedTitan = d.equippedTitan, titanSerums = d.titanSerums, titanPity = d.titanPity, titanFusions = d.titanFusions, titanShifterMode = d.titanShifterMode, titanHeat = d.titanHeat or 0, titanSuppressTurns = d.titanSuppressTurns or 0,
		clan = d.clan, clanTier = d.clanTier, clanVials = d.clanVials, clanPity = d.clanPity, clanTraits = clanTraits,
		inventory = d.inventory, equippedWeapon = d.equippedWeapon, equippedArmor = d.equippedArmor, equippedAccessory = d.equippedAccessory, thunderSpears = d.thunderSpears, odmGearLevel = d.odmGearLevel, consumables = d.consumables, itemLevels = d.itemLevels, activeSets = activeSets,
		campaignChapter = d.campaignChapter, campaignEnemy = d.campaignEnemy, raidUnlocks = d.raidUnlocks, raidHighScores = d.raidHighScores,
		inCombat = d.inCombat, awaitingTurn = d.awaitingTurn, enemyHp = d.enemyHp, enemyMaxHp = d.enemyMaxHp, enemyName = d.enemyName, enemyIsBoss = d.enemyIsBoss, bossPhase2 = d.bossPhase2, bossPhase3 = d.bossPhase3, evasionActive = d.evasionActive, moveCooldowns = d.moveCooldowns, playerBleedTurns = d.playerBleedTurns or 0, playerSlowTurns = d.playerSlowTurns or 0, playerFearTurns = d.playerFearTurns or 0,
		totalKills = d.totalKills, bossKills = d.bossKills, killStreak = d.killStreak, bestStreak = d.bestStreak, endlessHighFloor = d.endlessHighFloor or 0, achievementsClaimed = d.achievementsClaimed,
		loginStreak = d.loginStreak, loginStreakBest = d.loginStreakBest, lastLoginDay = d.lastLoginDay, dailyProgress = d.dailyProgress, dailyClaimed = d.dailyClaimed, weeklyProgress = d.weeklyProgress, weeklyClaimed = d.weeklyClaimed,
		pvpElo = d.pvpElo, pvpWins = d.pvpWins, pvpLosses = d.pvpLosses,
		hasVIP = d.hasVIP, hasPathsPass = d.hasPathsPass, hasAutoTrain = d.hasAutoTrain, hasVault = d.hasVault, hasArsenal = d.hasArsenal, boostActive = os.time() < (d.boostExpiry or 0), boostSecsLeft = math.max(0, (d.boostExpiry or 0) - os.time()),
		shopSeed = d.shopSeed, shopRerolled = d.shopRerolled, tutorialDone = d.tutorialDone, prestigeTitle = d.prestigeTitle
	}
end

function S.Push(player, d)
	local cs = S.CalcCS(d)
	d.maxHp = cs.maxHp
	d.hp = math.min(d.hp or d.maxHp, d.maxHp)
	S.RE_Push:FireClient(player, S.BuildPayload(d, cs), cs)
end

function S.Msg(player, text, msgType) S.RE_Log:FireClient(player, text, msgType or "system") end
function S.Pop(player, title, body, color) S.RE_Notify:FireClient(player, title, body, color or "amber") end
function S.Notify(player, title, body, color) S.RE_Notify:FireClient(player, title, body, color or "amber") end

function S.AwardXP(player, d, rawXp, cs)
	if not cs then cs = S.CalcCS(d) end
	local gained = math.floor(rawXp * cs.xpMult * cs.streakMult + (cs.xpBonus or 0))
	local levelsGained = 0
	d.xp = (d.xp or 0) + gained
	d.trainingXP = (d.trainingXP or 0) + gained

	while (d.level or 1) < D.MAX_LEVEL do
		local needed = D.XpToNext(d.level)
		if d.xp >= needed then
			d.xp = d.xp - needed
			d.level = d.level + 1
			d.freeStatPoints = (d.freeStatPoints or 0) + D.STAT_POINTS_PER_LEVEL
			levelsGained = levelsGained + 1
			S.Msg(player, "== LEVEL UP! Level " .. d.level .. " — +" .. D.STAT_POINTS_PER_LEVEL .. " stat points! ==", "level")
		else break end
	end
	return gained, levelsGained
end

function S.AwardFunds(player, d, rawFunds, cs)
	if not cs then cs = S.CalcCS(d) end
	local gained = math.floor(rawFunds * cs.fundMult)
	d.funds = (d.funds or 0) + gained
	return gained
end

function S.BumpChallenge(player, d, challengeType, amount)
	d.dailyProgress = d.dailyProgress or {}
	d.weeklyProgress = d.weeklyProgress or {}
	local day = D.DayNumber()

	if (d.dailyChallengeDay or 0) ~= day then
		d.dailyChallengeDay, d.dailyProgress, d.dailyClaimed = day, {}, {}
		local weekNum = math.floor(day / 7)
		if (d.weeklyResetWeek or 0) ~= weekNum then d.weeklyResetWeek, d.weeklyProgress, d.weeklyClaimed = weekNum, {}, {} end
	end

	local dailies, weeklies = D.GetActiveChallenges(day)
	for _, ch in ipairs(dailies) do
		if ch.type == challengeType then
			d.dailyProgress[ch.id] = (d.dailyProgress[ch.id] or 0) + (amount or 1)
			if d.dailyProgress[ch.id] >= ch.goal and not (d.dailyClaimed or {})[ch.id] then
				d.dailyClaimed = d.dailyClaimed or {}; d.dailyClaimed[ch.id] = true
				if ch.reward.xp then d.xp = (d.xp or 0) + ch.reward.xp end
				if ch.reward.funds then d.funds = (d.funds or 0) + ch.reward.funds end
				if ch.reward.serums then d.titanSerums = (d.titanSerums or 0) + ch.reward.serums end
				if ch.reward.vials then d.clanVials = (d.clanVials or 0) + ch.reward.vials end
				S.Msg(player, "DAILY CHALLENGE COMPLETE: " .. ch.label, "reward"); S.Pop(player, "DAILY COMPLETE", ch.label, "amber")
			end
		end
	end
	for _, ch in ipairs(weeklies) do
		if ch.type == challengeType then
			d.weeklyProgress[ch.id] = (d.weeklyProgress[ch.id] or 0) + (amount or 1)
			if d.weeklyProgress[ch.id] >= ch.goal and not (d.weeklyClaimed or {})[ch.id] then
				d.weeklyClaimed = d.weeklyClaimed or {}; d.weeklyClaimed[ch.id] = true
				if ch.reward.xp then d.xp = (d.xp or 0) + ch.reward.xp end
				if ch.reward.funds then d.funds = (d.funds or 0) + ch.reward.funds end
				if ch.reward.serums then d.titanSerums = (d.titanSerums or 0) + ch.reward.serums end
				if ch.reward.vials then d.clanVials = (d.clanVials or 0) + ch.reward.vials end
				S.Msg(player, "WEEKLY CHALLENGE COMPLETE: " .. ch.label, "reward"); S.Pop(player, "WEEKLY COMPLETE", ch.label, "amber")
			end
		end
	end
end

function S.CheckAchievements(player, d)
	if not d.achievementsClaimed then d.achievementsClaimed = {} end
	local progress = { totalKills = d.totalKills or 0, bossKills = d.bossKills or 0, prestige = d.prestige or 0, pvpWins = d.pvpWins or 0, bestStreak = d.bestStreak or 0, titanFusions = d.titanFusions or 0, level = d.level or 1, endlessHighFloor = d.endlessHighFloor or 0 }

	for _, ach in ipairs(D.ACHIEVEMENTS) do
		if not d.achievementsClaimed[ach.id] and (progress[ach.track] or 0) >= ach.goal then
			d.achievementsClaimed[ach.id] = true
			local rewStr = ""
			for stat, bonus in pairs(ach.reward) do
				if stat == "serums" then d.titanSerums = (d.titanSerums or 0) + bonus
				elseif stat == "vials" then d.clanVials = (d.clanVials or 0) + bonus
				elseif stat == "xp" then d.xp = (d.xp or 0) + bonus
				elseif stat == "funds" then d.funds = (d.funds or 0) + bonus end
				rewStr = rewStr .. "+" .. bonus .. " " .. stat:upper() .. "  "
			end
			S.Msg(player, "== ACHIEVEMENT: " .. ach.label .. "!  " .. rewStr .. " ==", "system")
			S.Notify(player, "ACHIEVEMENT UNLOCKED", ach.label .. "\n" .. rewStr, "amber")
		end
	end
end

function S.GetPrestigeTitle(prestige) return D.GetPrestigeTitle(prestige) end

-- ============================================================================
-- 5. DATASTORE SAVE / LOAD
-- ============================================================================
local SAVE_SKIP = {
	hp=1, inCombat=1, awaitingTurn=1, enemyHp=1, enemyMaxHp=1, enemyName=1, enemyIsBoss=1,
	enemyAtk=1, enemyRegen=1, enemyTier=1, enemyBehavior=1, enemyTitanId=1, enemyBurnTurns=1, enemyStunned=1, enemyFearTurns=1,
	enemyAtkDebuffTurns=1, enemyAtkDebuffPct=1, telegraphWindup=1, titanShifterMode=1, titanHeat=1, titanSuppressTurns=1,
	bossPhase2=1, bossPhase3=1, bossGimmickState=1, bossActiveMechanic=1, bossHeavyStreak=1,
	evasionActive=1, wanderingEvadeTurns=1, wanderingCritPending=1, nextAttackMult=1, nextTitanSpecialBoost=1,
	tyburShieldHits=1, tyburCounterDmgMult=1, playerBleedTurns=1, playerSlowTurns=1, playerFearTurns=1,
	moveCooldowns=1, _activeEnemy=1, endlessFloor=1, boostFreeForgeUsed=1, maxHp=1
}

function S.Save(userId, d)
	local payload = {}
	for k, v in pairs(d) do if not SAVE_SKIP[k] then payload[k] = v end end
	local ok, err = pcall(function() S.DS:SetAsync(D.DATASTORE_KEY .. userId, payload) end)
	if not ok then warn("[AOT_Sessions] Save failed for " .. userId .. ": " .. tostring(err)) end
end

function S.Load(userId)
	local ok, saved = pcall(function() return S.DS:GetAsync(D.DATASTORE_KEY .. userId) end)
	local blank = S.Blank()

	if not ok or not saved then return blank end

	-- Migration
	for k, v in pairs(blank) do if saved[k] == nil then saved[k] = v end end
	local sv = saved.schemaVersion or 0
	if sv < 1 then
		if saved.clanSerums and not saved.clanVials then saved.clanVials, saved.clanSerums = saved.clanSerums, nil end
		saved.clanTier = saved.clanTier or 0
		saved.schemaVersion = 1
	end
	if sv < 2 then
		saved.bladeMastery, saved.titanAffinity, saved.fortitude, saved.endlessHighFloor, saved.redeemedCodes = saved.bladeMastery or 0, saved.titanAffinity or 0, saved.fortitude or 0, saved.endlessHighFloor or 0, saved.redeemedCodes or {}
		saved.schemaVersion = 2
	end

	-- Array Cleanup
	if saved.titanSlots then
		local clean = {}
		for _, v in pairs(saved.titanSlots) do if type(v) == "table" and v.id then table.insert(clean, v) end end
		saved.titanSlots = clean
	end

	if saved.equippedTitan ~= nil then
		saved.equippedTitan = tonumber(saved.equippedTitan)
		if saved.equippedTitan and (saved.equippedTitan < 1 or saved.equippedTitan > #(saved.titanSlots or {})) then
			saved.equippedTitan = #(saved.titanSlots or {}) > 0 and 1 or nil
		end
	end

	local chapter = math.max(1, math.min(saved.campaignChapter or 1, #D.CAMPAIGN))
	saved.campaignChapter = chapter
	if D.CAMPAIGN[chapter] and (saved.campaignEnemy or 1) > #D.CAMPAIGN[chapter].enemies then
		saved.campaignEnemy, saved.campaignChapter = 1, math.min(chapter + 1, #D.CAMPAIGN)
	end

	return saved
end

return S