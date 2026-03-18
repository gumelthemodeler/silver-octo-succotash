-- @ScriptType: Script
-- AOT_Server_Core  (Script)
-- Place in: ServerScriptService > AOT_Server_Core
-- Handles: player join/leave, auto-save loop, gamepass verification,
--          login streak, RF_GetState, and achievement bootstrapping.
-- v1.0.0

local Players            = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService         = game:GetService("RunService")
local SS                 = game:GetService("ServerScriptService")

local S        = require(SS:WaitForChild("AOT_Sessions"))
local D        = require(game:GetService("ReplicatedStorage"):WaitForChild("AOT"):WaitForChild("AOT_Data"))
local sessions = S.sessions

-- ────────────────────────────────────────────────────────────
-- GAMEPASS CHECK
-- Studio solo: grant all passes for easy testing.
-- ────────────────────────────────────────────────────────────
local function CheckPasses(player, d)
	if RunService:IsStudio() and #Players:GetPlayers() <= 1 then
		d.hasVIP      = true
		d.hasPathsPass= true
		d.hasAutoTrain= true
		d.hasVault    = true
		d.hasArsenal  = true
		return
	end

	local function Has(gpId)
		if gpId == 0 then return false end  -- placeholder ID → not purchased yet
		local ok, result = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gpId)
		end)
		return ok and result or false
	end

	d.hasVIP       = Has(D.GP_VIP)
	d.hasPathsPass = Has(D.GP_PATHS)
	d.hasAutoTrain = Has(D.GP_AUTOTRAIN)
	d.hasVault     = Has(D.GP_VAULT)
	d.hasArsenal   = Has(D.GP_ARSENAL)
end

-- ────────────────────────────────────────────────────────────
-- LOGIN STREAK
-- Awards daily rewards on first login of each UTC day.
-- ────────────────────────────────────────────────────────────
local function HandleLoginStreak(player, d)
	local today = D.DayNumber()
	if d.lastLoginDay == today then return end  -- already claimed today

	local yesterday = today - 1
	if d.lastLoginDay == yesterday then
		-- Consecutive day
		d.loginStreak = (d.loginStreak or 0) + 1
	else
		-- Streak broken
		d.loginStreak = 1
	end

	d.lastLoginDay    = today
	d.loginStreakBest = math.max(d.loginStreakBest or 0, d.loginStreak)

	local dayIdx = math.min(d.loginStreak, 7)
	local reward = D.LOGIN_STREAK_REWARDS[dayIdx]
	if not reward then return end

	local cs = S.CalcCS(d)

	-- Apply base reward (XP through proper helper for level-up handling)
	d.funds       = (d.funds or 0) + reward.funds
	d.titanSerums = (d.titanSerums or 0) + reward.serums
	d.clanVials   = (d.clanVials or 0) + reward.vials
	if (reward.xp or 0) > 0 then S.AwardXP(player, d, reward.xp, cs) end

	-- VIP bonus
	local vipBonus = ""
	if d.hasVIP then
		local vb      = D.LOGIN_STREAK_VIP_BONUS
		d.funds       = d.funds + vb.funds
		d.titanSerums = d.titanSerums + vb.serums
		d.clanVials   = d.clanVials + vb.vials
		if (vb.xp or 0) > 0 then S.AwardXP(player, d, vb.xp, cs) end
		vipBonus = "  +VIP Bonus"
	end

	-- Vault weekly serum: first login of each week
	if d.hasVault then
		local weekStart = math.floor(today / 7) * 7
		local lastVaultWeek = math.floor((d.vaultLastWeeklySerum or 0) / 7)
		local thisWeek      = math.floor(today / 7)
		if lastVaultWeek < thisWeek then
			d.titanSerums = d.titanSerums + 1
			d.vaultLastWeeklySerum = today
			vipBonus = vipBonus .. "  +1 Weekly Serum (Vault)"
		end
	end

	S.Pop(player,
		"DAILY LOGIN — DAY " .. d.loginStreak,
		reward.label .. vipBonus,
		"amber"
	)
	S.Msg(player, "== Daily login reward! " .. reward.label .. " ==", "system")
end

-- ────────────────────────────────────────────────────────────
-- PLAYER ADDED
-- ────────────────────────────────────────────────────────────
Players.PlayerAdded:Connect(function(player)
	-- Load from DataStore
	local d = S.Load(player.UserId)

	-- Check gamepasses (can yield — run synchronously before session is registered)
	CheckPasses(player, d)

	-- Reset all volatile fields
	S.ResetVolatile(d)

	-- Recalculate derived stats
	local cs  = S.CalcCS(d)
	d.maxHp   = cs.maxHp
	d.hp      = d.maxHp   -- respawn at full health

	-- Register session
	sessions[player.UserId] = d

	-- Handle login streak
	HandleLoginStreak(player, d)

	-- Refresh daily shop seed if needed
	local today = D.DayNumber()
	if (d.shopSeed or 0) ~= today then
		d.shopSeed    = today
		d.shopRerolled = false
	end

	-- Welcome message
	task.delay(0.6, function()
		if not player.Parent then return end
		local titleStr = S.GetPrestigeTitle(d.prestige)
		S.Msg(player,
			"== ATTACK ON TITAN: INCREMENTAL — " ..
				titleStr .. "  Prestige " .. d.prestige ..
				"  Level " .. d.level .. " ==",
			"system"
		)
		S.Push(player, d)
	end)

	-- Tutorial trigger for new players
	if not d.tutorialDone then
		task.delay(2.0, function()
			if player.Parent then
				S.Pop(player, "WELCOME", "Complete missions to earn XP, funds, and rare drops. Use serums to roll titans. Good luck, soldier.", "amber")
			end
		end)
	end

	-- Arsenal gamepass: grant 2 free spears at the start of each server session
	if d.hasArsenal then
		d.thunderSpears = (d.thunderSpears or 0) + 2
		S.Msg(player, "Arsenal: +2 Thunder Spears to start.", "system")
	end

	-- Auto-save every 60 seconds while the player is in the game
	task.spawn(function()
		while task.wait(60) do
			if not player.Parent then break end
			local dd = sessions[player.UserId]
			if dd then S.Save(player.UserId, dd) end
		end
	end)
end)

-- ────────────────────────────────────────────────────────────
-- PLAYER REMOVING
-- ────────────────────────────────────────────────────────────
Players.PlayerRemoving:Connect(function(player)
	local d = sessions[player.UserId]
	if d then
		S.Save(player.UserId, d)
		sessions[player.UserId] = nil
	end

	-- Clean up any active PvP match
	for matchId, match in pairs(S.pvpMatches) do
		if match.p1Id == player.UserId or match.p2Id == player.UserId then
			-- Award forfeit win to the other player
			local winnerId = match.p1Id == player.UserId and match.p2Id or match.p1Id
			local winnerD  = sessions[winnerId]
			local winner   = Players:GetPlayerByUserId(winnerId)
			if winnerD and winner then
				local eloChange = D.CalcEloChange(winnerD.pvpElo, d and d.pvpElo or 1000, true)
				winnerD.pvpElo  = (winnerD.pvpElo or 1000) + eloChange
				winnerD.pvpWins = (winnerD.pvpWins or 0) + 1
				S.Msg(winner, "== Your PvP opponent disconnected. Victory awarded! +" .. eloChange .. " ELO ==", "system")
				S.Push(winner, winnerD)
			end
			S.pvpMatches[matchId] = nil
		end
	end

	-- Clean up any raid party
	for partyId, party in pairs(S.raidParties) do
		if party.leaderId == player.UserId then
			-- Disband party — notify members
			for _, memberId in ipairs(party.memberIds or {}) do
				local mem = Players:GetPlayerByUserId(memberId)
				if mem then
					S.Pop(mem, "RAID DISBANDED", "The party leader left.", "amber")
				end
			end
			S.raidParties[partyId] = nil
		else
			-- Remove from member list
			for i, memberId in ipairs(party.memberIds or {}) do
				if memberId == player.UserId then
					table.remove(party.memberIds, i)
					-- Notify leader
					local leader = Players:GetPlayerByUserId(party.leaderId)
					if leader then
						S.Msg(leader, player.DisplayName .. " left the raid party.", "system")
					end
					break
				end
			end
		end
	end
end)

-- ────────────────────────────────────────────────────────────
-- SERVER SHUTDOWN — save all sessions
-- ────────────────────────────────────────────────────────────
game:BindToClose(function()
	for userId, d in pairs(sessions) do
		S.Save(userId, d)
	end
end)

-- ────────────────────────────────────────────────────────────
-- RF_GetState — initial full state request from client
-- ────────────────────────────────────────────────────────────
S.RF_GetState.OnServerInvoke = function(player)
	local d = sessions[player.UserId]
	if not d then return nil, nil end
	local cs = S.CalcCS(d)
	d.maxHp  = cs.maxHp
	return S.BuildPayload(d, cs), cs
end

-- ────────────────────────────────────────────────────────────
-- RF_GetLeaderboard — top players by prestige, then ELO
-- ────────────────────────────────────────────────────────────
S.RF_GetLeaderboard.OnServerInvoke = function(_player)
	local list = {}
	for userId, d in pairs(sessions) do
		table.insert(list, {
			userId   = userId,
			prestige = d.prestige or 0,
			level    = d.level    or 1,
			pvpElo   = d.pvpElo   or D.PVP_STARTING_ELO,
			title    = S.GetPrestigeTitle(d.prestige or 0),
		})
	end
	table.sort(list, function(a, b)
		if a.prestige ~= b.prestige then return a.prestige > b.prestige end
		return a.pvpElo > b.pvpElo
	end)
	-- Return top 20
	local top = {}
	for i = 1, math.min(20, #list) do top[i] = list[i] end
	return top
end

-- ────────────────────────────────────────────────────────────
-- STAT ALLOCATION
-- ────────────────────────────────────────────────────────────
-- Stats that cost 1 point, and stats that cost 2 points
local VALID_STATS_1PT = {str=true, def=true, spd=true, wil=true}
local VALID_STATS_2PT = {bladeMastery=true, titanAffinity=true, fortitude=true}

S.RE_AllocStat.OnServerEvent:Connect(function(player, stat)
	local d = sessions[player.UserId]
	if not d then return end
	local cost = VALID_STATS_2PT[stat] and 2 or (VALID_STATS_1PT[stat] and 1 or nil)
	if not cost then return end
	if (d.freeStatPoints or 0) < cost then
		S.Msg(player, "Not enough free stat points (need " .. cost .. ").", "warn")
		return
	end
	d.freeStatPoints = d.freeStatPoints - cost
	d[stat] = (d[stat] or 0) + 1
	S.Push(player, d)
end)

S.RE_AllocMany.OnServerEvent:Connect(function(player, allocTable)
	-- allocTable = {str=N, def=N, bladeMastery=N, ...}
	local d = sessions[player.UserId]
	if not d or type(allocTable) ~= "table" then return end
	local totalCost = 0
	for stat, amt in pairs(allocTable) do
		if type(amt) == "number" and amt > 0 then
			local cost = VALID_STATS_2PT[stat] and 2 or (VALID_STATS_1PT[stat] and 1 or nil)
			if cost then totalCost = totalCost + cost * amt end
		end
	end
	if totalCost > (d.freeStatPoints or 0) then return end
	for stat, amt in pairs(allocTable) do
		if type(amt) == "number" and amt > 0 then
			local cost = VALID_STATS_2PT[stat] and 2 or (VALID_STATS_1PT[stat] and 1 or nil)
			if cost then
				d[stat]          = (d[stat] or 0) + amt
				d.freeStatPoints = d.freeStatPoints - cost * amt
			end
		end
	end
	S.Push(player, d)
end)

S.RE_Train.OnServerEvent:Connect(function(player, stat)
	local d = sessions[player.UserId]
	if not d then return end
	local cost = VALID_STATS_2PT[stat] and 2 or (VALID_STATS_1PT[stat] and 1 or nil)
	if not cost then return end
	local xpCost = D.TRAINING_XP_PER_POINT * cost
	if (d.trainingXP or 0) < xpCost then
		S.Msg(player, "Not enough Training XP. (Need " .. xpCost .. ")", "warn")
		return
	end
	d.trainingXP = d.trainingXP - xpCost
	d[stat]      = (d[stat] or 0) + 1
	S.Msg(player, "Training complete! +" .. stat .. " 1", "system")
	S.Push(player, d)
end)

print("[AOT_Server_Core] Loaded.")
