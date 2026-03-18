-- @ScriptType: Script
-- AOT_Server_Clans  (Script)
-- Place in: ServerScriptService > AOT_Server_Clans
-- Handles: blood vial rolls, clan tier upgrades, VIP daily reroll.
-- v1.1.0

local SS       = game:GetService("ServerScriptService")
local S        = require(SS:WaitForChild("AOT_Sessions"))
local D        = require(game:GetService("ReplicatedStorage"):WaitForChild("AOT"):WaitForChild("AOT_Data"))
local sessions = S.sessions

-- ────────────────────────────────────────────────────────────
-- SHARED: perform a single clan roll and apply result to d
-- Returns the result table, or nil if validation failed.
-- ────────────────────────────────────────────────────────────
local function DoRoll(player, d, isFree)
	if not isFree then
		if (d.clanVials or 0) < 1 then
			S.Msg(player, "No blood vials! Earn them from missions or the shop.", "warn")
			return nil
		end
		d.clanVials = d.clanVials - 1
	end

	d.clanPity = (d.clanPity or 0) + 1
	local result = D.RollClan(d.clanPity)

	-- Pity resets on Rare+
	if result.rarity ~= "Common" then d.clanPity = 0 end

	if d.clan == result.id then
		local tier = math.min(d.clanTier or 0, 3)
		if tier < 3 then
			S.Msg(player, "Duplicate roll! " .. result.name .. " bond deepens. Counts toward Tier upgrade.", "system")
		else
			-- Max tier — refund the vial cost
			if not isFree then d.clanVials = (d.clanVials or 0) + 1 end
			S.Msg(player, result.name .. " is already max tier. Vial refunded.", "system")
		end
	else
		d.clan     = result.id
		d.clanTier = 0
		S.Msg(player, "CLAN: You are now " .. result.name .. " [" .. result.rarity .. "]!", "system")
		S.Pop(player, "CLAN ACQUIRED", result.name .. " — " .. result.desc, "amber")
	end

	return result
end

-- ────────────────────────────────────────────────────────────
-- ROLL CLAN
-- ────────────────────────────────────────────────────────────
S.RE_RollClan.OnServerEvent:Connect(function(player)
	local d = sessions[player.UserId]
	if not d then return end

	local result = DoRoll(player, d, false)
	if not result then return end

	S.CheckAchievements(player, d)
	S.Push(player, d)
end)

-- ────────────────────────────────────────────────────────────
-- VIP FREE DAILY REROLL
-- One free roll per day; resets at midnight UTC.
-- ────────────────────────────────────────────────────────────
S.RE_VIPClanReroll.OnServerEvent:Connect(function(player)
	local d = sessions[player.UserId]
	if not d then return end

	if not d.hasVIP then
		S.Msg(player, "VIP gamepass required for free daily clan reroll.", "warn")
		return
	end

	local today    = D.DayNumber()
	local lastDay  = math.floor((d.vipLastClanReroll or 0) / 86400)
	if lastDay >= today then
		S.Msg(player, "Free VIP reroll already used today. Resets at midnight UTC.", "warn")
		return
	end

	d.vipLastClanReroll = os.time()
	local result = DoRoll(player, d, true)  -- isFree = true
	if not result then return end

	S.Msg(player, "VIP free reroll used! Next available tomorrow.", "system")
	S.CheckAchievements(player, d)
	S.Push(player, d)
end)

-- ────────────────────────────────────────────────────────────
-- UPGRADE CLAN TIER
-- ────────────────────────────────────────────────────────────
S.RE_UpgradeClan.OnServerEvent:Connect(function(player)
	local d = sessions[player.UserId]
	if not d then return end

	if not d.clan then
		S.Msg(player, "You don't have a clan yet.", "warn")
		return
	end

	local currentTier = d.clanTier or 0
	if currentTier >= 3 then
		S.Msg(player, "Your clan is already at maximum tier (3).", "warn")
		return
	end

	local nextTier = currentTier + 1
	local cost     = D.CLAN_TIER_COSTS[nextTier]
	if (d.clanVials or 0) < cost then
		S.Msg(player, "Not enough blood vials! (Need " .. cost
			.. ", have " .. (d.clanVials or 0) .. ")", "warn")
		return
	end

	d.clanVials = d.clanVials - cost
	d.clanTier  = nextTier

	local clanName = d.clan
	for _, cl in ipairs(D.CLAN_POOL) do
		if cl.id == d.clan then clanName = cl.name break end
	end

	local tier = D.CLAN_POOL[1] and D.CLAN_POOL[1].tiers  -- for trait lookup
	local newTraits = {}
	for _, cl in ipairs(D.CLAN_POOL) do
		if cl.id == d.clan and cl.tiers[nextTier] then
			newTraits = cl.tiers[nextTier].traits or {}
			break
		end
	end

	S.Msg(player, "== " .. clanName .. " upgraded to TIER " .. nextTier
		.. "! New traits: " .. table.concat(newTraits, ", ") .. " ==", "system")
	S.Pop(player, "CLAN TIER UP", clanName .. " — Tier " .. nextTier, "amber")
	S.Push(player, d)
end)

print("[AOT_Server_Clans] Loaded.")

-- ────────────────────────────────────────────────────────────
-- ROLL CLAN
-- ────────────────────────────────────────────────────────────
S.RE_RollClan.OnServerEvent:Connect(function(player)
	local d = sessions[player.UserId]
	if not d then return end

	if (d.clanVials or 0) < 1 then
		S.Msg(player, "No blood vials! Earn them from missions or the shop.", "warn")
		return
	end

	d.clanVials = d.clanVials - 1
	d.clanPity  = (d.clanPity or 0) + 1

	local result = D.RollClan(d.clanPity)

	-- Pity reset on Rare+ result
	if result.rarity ~= "Common" then
		d.clanPity = 0
	end

	if d.clan == result.id then
		-- Same clan: convert into tier upgrade vials
		-- Give a partial refund — counts as upgrade progress
		local tier = math.min(d.clanTier or 0, 3)
		if tier < 3 then
			-- Credit equivalent toward upgrade cost
			S.Msg(player, "Duplicate clan roll! Your " .. result.name .. " bond deepens. Counts toward Tier upgrade.", "system")
		else
			-- Already max tier — refund vial
			d.clanVials = d.clanVials + 1
			S.Msg(player, result.name .. " clan is already at max tier. Vial refunded.", "system")
		end
	else
		d.clan     = result.id
		d.clanTier = 0
		S.Msg(player, "CLAN: You are now " .. result.name .. " [" .. result.rarity .. "]!", "system")
		S.Pop(player, "CLAN ACQUIRED", result.name .. " — " .. result.desc, "amber")
	end

	S.CheckAchievements(player, d)
	S.Push(player, d)
end)

-- ────────────────────────────────────────────────────────────
-- UPGRADE CLAN TIER
-- Cost is cumulative vials (D.CLAN_TIER_COSTS)
-- ────────────────────────────────────────────────────────────
S.RE_UpgradeClan.OnServerEvent:Connect(function(player)
	local d = sessions[player.UserId]
	if not d then return end

	if not d.clan then
		S.Msg(player, "You don't have a clan yet.", "warn")
		return
	end

	local currentTier = d.clanTier or 0
	if currentTier >= 3 then
		S.Msg(player, "Your clan is already at maximum tier (3).", "warn")
		return
	end

	local nextTier = currentTier + 1
	local cost     = D.CLAN_TIER_COSTS[nextTier]
	if (d.clanVials or 0) < cost then
		S.Msg(player, "Not enough blood vials! (Need " .. cost .. ", have " .. (d.clanVials or 0) .. ")", "warn")
		return
	end

	d.clanVials = d.clanVials - cost
	d.clanTier  = nextTier

	-- Find clan name for messaging
	local clanName = d.clan
	for _, cl in ipairs(D.CLAN_POOL) do
		if cl.id == d.clan then clanName = cl.name break end
	end

	S.Msg(player, "== " .. clanName .. " clan upgraded to TIER " .. nextTier .. "! New traits unlocked! ==", "system")
	S.Pop(player, "CLAN TIER UP", clanName .. " — Tier " .. nextTier, "amber")
	S.Push(player, d)
end)

print("[AOT_Server_Clans] Loaded.")
