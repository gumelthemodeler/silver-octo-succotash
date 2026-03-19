-- @ScriptType: Script
-- @ScriptType: Script
-- AOT_Server_Core (Optimized with Click-to-Train & Bulk Upgrades)
-- Place in: ServerScriptService > AOT_Server_Core

local Players            = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService         = game:GetService("RunService")
local SS                 = game:GetService("ServerScriptService")

local S        = require(SS:WaitForChild("AOT_Sessions"))
local D        = require(game:GetService("ReplicatedStorage"):WaitForChild("AOT"):WaitForChild("AOT_Data"))
local sessions = S.sessions

-- Register the new ClickTrain remote
local RE_ClickTrain = AOT:WaitForChild("Remotes"):FindFirstChild("ClickTrain") or Instance.new("RemoteEvent", AOT.Remotes)
RE_ClickTrain.Name = "ClickTrain"

local function CheckPasses(player, d)
	if RunService:IsStudio() and #Players:GetPlayers() <= 1 then
		d.hasVIP, d.hasPathsPass, d.hasAutoTrain, d.hasVault, d.hasArsenal = true, true, true, true, true
		return
	end
	local function Has(gpId)
		if gpId == 0 then return false end
		local ok, result = pcall(function() return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gpId) end)
		return ok and result or false
	end
	d.hasVIP       = Has(D.GP_VIP)
	d.hasPathsPass = Has(D.GP_PATHS)
	d.hasAutoTrain = Has(D.GP_AUTOTRAIN)
	d.hasVault     = Has(D.GP_VAULT)
	d.hasArsenal   = Has(D.GP_ARSENAL)
end

local function HandleLoginStreak(player, d)
	local today = D.DayNumber()
	if d.lastLoginDay == today then return end

	if d.lastLoginDay == today - 1 then d.loginStreak = (d.loginStreak or 0) + 1 else d.loginStreak = 1 end
	d.lastLoginDay = today
	d.loginStreakBest = math.max(d.loginStreakBest or 0, d.loginStreak)

	local reward = D.LOGIN_STREAK_REWARDS[math.min(d.loginStreak, 7)]
	if not reward then return end

	local cs = S.CalcCS(d)
	d.funds = (d.funds or 0) + reward.funds
	d.titanSerums = (d.titanSerums or 0) + reward.serums
	d.clanVials = (d.clanVials or 0) + reward.vials
	if (reward.xp or 0) > 0 then S.AwardXP(player, d, reward.xp, cs) end

	if d.hasVIP then
		local vb = D.LOGIN_STREAK_VIP_BONUS
		d.funds, d.titanSerums, d.clanVials = d.funds + vb.funds, d.titanSerums + vb.serums, d.clanVials + vb.vials
		if (vb.xp or 0) > 0 then S.AwardXP(player, d, vb.xp, cs) end
	end

	S.Pop(player, "DAILY LOGIN — DAY " .. d.loginStreak, reward.label, "amber")
end

Players.PlayerAdded:Connect(function(player)
	local d = S.Load(player.UserId)
	CheckPasses(player, d)
	S.ResetVolatile(d)

	local cs = S.CalcCS(d)
	d.maxHp, d.hp = cs.maxHp, cs.maxHp
	sessions[player.UserId] = d

	HandleLoginStreak(player, d)

	local today = D.DayNumber()
	if (d.shopSeed or 0) ~= today then d.shopSeed, d.shopRerolled = today, false end

	task.delay(0.6, function()
		if not player.Parent then return end
		S.Msg(player, "== ATTACK ON TITAN: INCREMENTAL — " .. S.GetPrestigeTitle(d.prestige) .. " ==", "system")
		S.Push(player, d)
	end)

	task.spawn(function()
		while task.wait(60) do
			if not player.Parent then break end
			local dd = sessions[player.UserId]
			if dd then S.Save(player.UserId, dd) end
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	local d = sessions[player.UserId]
	if d then S.Save(player.UserId, d) sessions[player.UserId] = nil end
end)

game:BindToClose(function()
	for userId, d in pairs(sessions) do S.Save(userId, d) end
end)

S.RF_GetState.OnServerInvoke = function(player)
	local d = sessions[player.UserId]
	if not d then return nil, nil end
	local cs = S.CalcCS(d)
	return S.BuildPayload(d, cs), cs
end

-- ============================================================================
-- TRAINING & CLICKER LOGIC
-- ============================================================================
-- 1. Click to Train (Gain XP)
-- Note: A debounce is added here to prevent malicious auto-clicker server crashing
local lastClicks = {}
RE_ClickTrain.OnServerEvent:Connect(function(player)
	local now = os.clock()
	if (lastClicks[player.UserId] or 0) > now then return end
	lastClicks[player.UserId] = now + 0.05 -- Max 20 clicks per second registered

	local d = sessions[player.UserId]
	if not d then return end

	local cs = S.CalcCS(d)
	-- Base click gives 5 XP + 2 per level, multiplied by prestige/VIP modifiers
	local gain = math.floor((5 + (d.level or 1) * 2) * cs.xpMult)
	d.trainingXP = (d.trainingXP or 0) + gain

	-- We only push periodically so we don't lag the server on every single click
	if math.random() < 0.1 then S.Push(player, d) end
end)

-- 2. Spend Training XP (Bulk Allowed)
S.RE_Train.OnServerEvent:Connect(function(player, stat, amount)
	local d = sessions[player.UserId]
	if not d or not D.STATS[stat] then return end

	amount = math.max(1, math.floor(tonumber(amount) or 1))

	local cost = D.STATS[stat].pointCost
	local xpCost = D.TRAINING_XP_PER_POINT * cost * amount

	if (d.trainingXP or 0) < xpCost then return end

	d.trainingXP = d.trainingXP - xpCost
	d[stat] = (d[stat] or 0) + amount

	S.Push(player, d)
end)

S.RE_AllocStat.OnServerEvent:Connect(function(player, stat)
	local d = sessions[player.UserId]
	if not d or not D.STATS[stat] then return end
	local cost = D.STATS[stat].pointCost
	if (d.freeStatPoints or 0) < cost then return end
	d.freeStatPoints = d.freeStatPoints - cost
	d[stat] = (d[stat] or 0) + 1
	S.Push(player, d)
end)

print("[AOT_Server_Core] Optimized Module Loaded.")