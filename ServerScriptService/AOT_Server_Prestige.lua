-- @ScriptType: Script
-- @ScriptType: Script
-- AOT_Server_Prestige (Optimized)
-- Place in: ServerScriptService > AOT_Server_Prestige

local SS       = game:GetService("ServerScriptService")
local S        = require(SS:WaitForChild("AOT_Sessions"))
local D        = require(game:GetService("ReplicatedStorage"):WaitForChild("AOT"):WaitForChild("AOT_Data"))
local sessions = S.sessions

local FUNDS_KEEP_ON_PRESTIGE = 500

local KEEP_KEYS = {
	"inventory", "titanSlots", "equippedTitan", "equippedWeapon", "equippedArmor", "equippedAccessory",
	"odmGearLevel", "clan", "clanTier", "clanVials", "clanPity", "titanSerums", "achievementsClaimed",
	"pvpElo", "pvpWins", "pvpLosses", "itemLevels", "bossKills", "totalKills", "bestStreak", "titanFusions",
	"loginStreak", "loginStreakBest", "tutorialDone", "thunderSpears", "consumables", "raidHighScores",
	"hasVIP", "hasPathsPass", "hasAutoTrain", "hasVault", "hasArsenal", "boostExpiry"
}

S.RE_Prestige.OnServerEvent:Connect(function(player)
	local d = sessions[player.UserId]
	if not d or d.inCombat then S.Msg(player, "Cannot prestige right now.", "warn") return end
	if (d.level or 1) < D.MAX_LEVEL then S.Msg(player, "Must reach level " .. D.MAX_LEVEL .. " to prestige.", "warn") return end

	local newPrestige = (d.prestige or 0) + 1
	local keepData = {}
	for _, key in ipairs(KEEP_KEYS) do keepData[key] = d[key] end

	local fresh = S.Blank()
	for k, v in pairs(fresh) do d[k] = v end

	for k, v in pairs(keepData) do d[k] = v end

	d.prestige, d.pathChosen, d.path, d.funds = newPrestige, false, nil, FUNDS_KEEP_ON_PRESTIGE

	local serumBonus, vialBonus = 1 + math.floor(newPrestige / 5), math.floor(newPrestige / 3)
	d.titanSerums, d.clanVials = d.titanSerums + serumBonus, d.clanVials + vialBonus
	d.prestigeTitle = S.GetPrestigeTitle(newPrestige)

	S.ResetVolatile(d)
	local cs = S.CalcCS(d)
	d.maxHp, d.hp = cs.maxHp, cs.maxHp

	S.Msg(player, "== PRESTIGE " .. newPrestige .. " — " .. d.prestigeTitle .. " ==", "system")
	S.Pop(player, "PRESTIGE " .. newPrestige, "You have entered The Paths. Choose your allegiance.\n+" .. serumBonus .. " Serums  +" .. vialBonus .. " Vials", "amber")

	S.CheckAchievements(player, d)
	S.BumpChallenge(player, d, "prestige", 1)
	S.Push(player, d)
end)

S.RE_ChoosePath.OnServerEvent:Connect(function(player, pathId)
	local d = sessions[player.UserId]
	if not d or d.pathChosen then return end

	local pathData = D.PATHS[pathId]
	if not pathData then return end

	if pathData.requiresPass and not d.hasPathsPass then S.Msg(player, pathData.name .. " requires the Paths gamepass.", "warn") return end

	local minP = ({wandering=2, royal=2})[pathId] or 0
	if (d.prestige or 0) < minP then S.Msg(player, pathData.name .. " requires Prestige " .. minP .. "+.", "warn") return end

	d.path, d.pathChosen = pathId, true
	S.Msg(player, "== PATH CHOSEN: " .. pathData.name .. " — " .. pathData.desc .. " ==", "system")
	S.Pop(player, "PATH: " .. pathData.name:upper(), pathData.desc, "amber")
	S.Push(player, d)
end)

print("[AOT_Server_Prestige] Optimized Module Loaded.")