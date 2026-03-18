-- @ScriptType: Script
-- AOT_Server_Prestige  (Script)
-- Place in: ServerScriptService > AOT_Server_Prestige
-- Handles: prestige reset, path selection screen, passive accumulation.
-- v1.0.0

local SS      = game:GetService("ServerScriptService")
local S       = require(SS:WaitForChild("AOT_Sessions"))
local D       = require(game:GetService("ReplicatedStorage"):WaitForChild("AOT"):WaitForChild("AOT_Data"))
local sessions = S.sessions

-- ────────────────────────────────────────────────────────────
-- PRESTIGE
-- Requirements: must be level MAX_LEVEL (100) and not in combat.
-- Keeps: inventory, titanSlots, clan, clanTier, clanVials,
--        odmGearLevel, achievements, pvpElo.
-- Resets: level, xp, str/def/spd/wil, funds (partial keep), campaign.
-- ────────────────────────────────────────────────────────────
local FUNDS_KEEP_ON_PRESTIGE = 500   -- flat funds carried over

S.RE_Prestige.OnServerEvent:Connect(function(player)
	local d = sessions[player.UserId]
	if not d then return end

	if d.inCombat then
		S.Msg(player, "Cannot prestige while in combat.", "warn")
		return
	end

	if (d.level or 1) < D.MAX_LEVEL then
		S.Msg(player, "You must reach level " .. D.MAX_LEVEL .. " before prestiging. (Current: " .. (d.level or 1) .. ")", "warn")
		return
	end

	-- Path chapter unlock check: some paths need specific prestige tiers
	-- (handled gracefully — player can always prestige, path unlocks differ)

	local oldPrestige = d.prestige or 0
	local newPrestige = oldPrestige + 1

	-- ── Items & Progress to KEEP ─────────────────────────────
	local keepInventory     = d.inventory
	local keepTitanSlots    = d.titanSlots
	local keepEquipTitan    = d.equippedTitan
	local keepWeapon        = d.equippedWeapon
	local keepArmor         = d.equippedArmor
	local keepAccy          = d.equippedAccessory
	local keepODM           = d.odmGearLevel
	local keepClan          = d.clan
	local keepClanTier      = d.clanTier
	local keepClanVials     = d.clanVials
	local keepClanPity      = d.clanPity
	local keepSerums        = d.titanSerums
	local keepAchievements  = d.achievementsClaimed
	local keepPvpElo        = d.pvpElo
	local keepPvpWins       = d.pvpWins
	local keepPvpLosses     = d.pvpLosses
	local keepItemLevels    = d.itemLevels
	local keepBossKills     = d.bossKills
	local keepTotalKills    = d.totalKills
	local keepBestStreak    = d.bestStreak
	local keepTitanFusions  = d.titanFusions
	local keepLoginStreak   = d.loginStreak
	local keepLoginBest     = d.loginStreakBest
	local keepTutorial      = d.tutorialDone
	local keepGPFlags       = {
		hasVIP=d.hasVIP, hasPathsPass=d.hasPathsPass, hasAutoTrain=d.hasAutoTrain,
		hasVault=d.hasVault, hasArsenal=d.hasArsenal, boostExpiry=d.boostExpiry
	}
	local keepSpears        = d.thunderSpears
	local keepConsumables   = d.consumables
	local keepRaidHighScores= d.raidHighScores

	-- ── Reset character to a fresh Blank ─────────────────────
	local fresh       = S.Blank()
	for k, v in pairs(fresh) do d[k] = v end

	-- ── Restore kept values ──────────────────────────────────
	d.prestige           = newPrestige
	d.pathChosen         = false   -- must choose path this prestige
	d.path               = nil     -- cleared until chosen
	d.funds              = FUNDS_KEEP_ON_PRESTIGE
	d.inventory          = keepInventory
	d.titanSlots         = keepTitanSlots
	d.equippedTitan      = keepEquipTitan
	d.equippedWeapon     = keepWeapon
	d.equippedArmor      = keepArmor
	d.equippedAccessory  = keepAccy
	d.odmGearLevel       = keepODM
	d.clan               = keepClan
	d.clanTier           = keepClanTier
	d.clanVials          = keepClanVials
	d.clanPity           = keepClanPity
	d.titanSerums        = keepSerums
	d.achievementsClaimed= keepAchievements
	d.pvpElo             = keepPvpElo
	d.pvpWins            = keepPvpWins
	d.pvpLosses          = keepPvpLosses
	d.itemLevels         = keepItemLevels
	d.bossKills          = keepBossKills
	d.totalKills         = keepTotalKills
	d.bestStreak         = keepBestStreak
	d.titanFusions       = keepTitanFusions
	d.loginStreak        = keepLoginStreak
	d.loginStreakBest    = keepLoginBest
	d.tutorialDone       = keepTutorial
	d.thunderSpears      = keepSpears
	d.consumables        = keepConsumables
	d.raidHighScores     = keepRaidHighScores
	for k, v in pairs(keepGPFlags) do d[k] = v end

	-- Prestige bonus: serum + vial reward
	local serumBonus = 1 + math.floor(newPrestige / 5)   -- +1 serum per 5 prestiges
	local vialBonus  = math.floor(newPrestige / 3)        -- +1 vial per 3 prestiges
	d.titanSerums    = d.titanSerums + serumBonus
	d.clanVials      = d.clanVials   + vialBonus

	d.prestigeTitle = S.GetPrestigeTitle(newPrestige)

	S.ResetVolatile(d)
	local cs = S.CalcCS(d)
	d.maxHp  = cs.maxHp
	d.hp     = d.maxHp

	S.Msg(player, "== PRESTIGE " .. newPrestige .. " — " .. d.prestigeTitle .. " ==", "system")
	S.Msg(player, "Choose your path in the Paths menu. Each path grants unique permanent bonuses.", "system")
	S.Pop(player,
		"PRESTIGE " .. newPrestige,
		"You have entered The Paths. Choose your allegiance.\n+" .. serumBonus .. " Serums  +" .. vialBonus .. " Vials",
		"amber"
	)

	S.CheckAchievements(player, d)
	S.BumpChallenge(player, d, "prestige", 1)
	S.Push(player, d)
end)
-- Called once per prestige after the Prestige event.
-- ────────────────────────────────────────────────────────────
S.RE_ChoosePath.OnServerEvent:Connect(function(player, pathId)
	local d = sessions[player.UserId]
	if not d then return end

	if d.pathChosen then
		S.Msg(player, "Path already chosen for this prestige.", "warn")
		return
	end

	local pathData = D.PATHS[pathId]
	if not pathData then
		S.Msg(player, "Invalid path selection.", "warn")
		return
	end

	-- Check if path requires Paths gamepass
	if pathData.requiresPass and not d.hasPathsPass then
		S.Msg(player, pathData.name .. " requires the Paths gamepass.", "warn")
		return
	end

	-- Validate prestige minimum for some paths (Royal / Wandering require prestige 2+)
	local pathMinPrestige = {wandering=2, royal=2}
	local minP = pathMinPrestige[pathId] or 0
	if (d.prestige or 0) < minP then
		S.Msg(player, pathData.name .. " requires Prestige " .. minP .. "+.", "warn")
		return
	end

	d.path       = pathId
	d.pathChosen = true

	S.Msg(player, "== PATH CHOSEN: " .. pathData.name .. " — " .. pathData.desc .. " ==", "system")
	S.Pop(player, "PATH: " .. pathData.name:upper(), pathData.desc, "amber")
	S.Push(player, d)
end)

print("[AOT_Server_Prestige] Loaded.")
