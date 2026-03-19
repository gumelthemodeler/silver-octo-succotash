-- @ScriptType: Script
-- @ScriptType: Script
-- AOT_Server_Clans (Optimized)
-- Place in: ServerScriptService > AOT_Server_Clans

local SS       = game:GetService("ServerScriptService")
local S        = require(SS:WaitForChild("AOT_Sessions"))
local D        = require(game:GetService("ReplicatedStorage"):WaitForChild("AOT"):WaitForChild("AOT_Data"))
local sessions = S.sessions

local function DoRoll(player, d, isFree)
	if not isFree then
		if (d.clanVials or 0) < 1 then S.Msg(player, "No blood vials!", "warn") return nil end
		d.clanVials = d.clanVials - 1
	end

	d.clanPity = (d.clanPity or 0) + 1
	local result = D.RollClan(d.clanPity)
	if result.rarity ~= "Common" then d.clanPity = 0 end

	if d.clan == result.id then
		local tier = math.min(d.clanTier or 0, 3)
		if tier < 3 then
			S.Msg(player, "Duplicate roll! " .. result.name .. " bond deepens.", "system")
		else
			if not isFree then d.clanVials = (d.clanVials or 0) + 1 end
			S.Msg(player, result.name .. " is already max tier. Vial refunded.", "system")
		end
	else
		d.clan = result.id
		d.clanTier = 0
		S.Msg(player, "CLAN: You are now " .. result.name .. " [" .. result.rarity .. "]!", "system")
		S.Pop(player, "CLAN ACQUIRED", result.name .. " — " .. result.desc, "amber")
	end

	return result
end

S.RE_RollClan.OnServerEvent:Connect(function(player)
	local d = sessions[player.UserId]
	if d and DoRoll(player, d, false) then
		S.CheckAchievements(player, d)
		S.Push(player, d)
	end
end)

S.RE_VIPClanReroll.OnServerEvent:Connect(function(player)
	local d = sessions[player.UserId]
	if not d then return end

	if not d.hasVIP then S.Msg(player, "VIP required for free daily reroll.", "warn") return end

	local today = D.DayNumber()
	local lastDay = math.floor((d.vipLastClanReroll or 0) / 86400)
	if lastDay >= today then S.Msg(player, "Free reroll already used today.", "warn") return end

	d.vipLastClanReroll = os.time()
	if DoRoll(player, d, true) then
		S.Msg(player, "VIP free reroll used!", "system")
		S.CheckAchievements(player, d)
		S.Push(player, d)
	end
end)

S.RE_UpgradeClan.OnServerEvent:Connect(function(player)
	local d = sessions[player.UserId]
	if not d then return end
	if not d.clan then S.Msg(player, "No clan to upgrade.", "warn") return end

	local currentTier = d.clanTier or 0
	if currentTier >= 3 then S.Msg(player, "Clan is at max tier.", "warn") return end

	local nextTier = currentTier + 1
	local cost = D.CLAN_TIER_COSTS[nextTier]
	if (d.clanVials or 0) < cost then S.Msg(player, "Need " .. cost .. " blood vials.", "warn") return end

	d.clanVials = d.clanVials - cost
	d.clanTier = nextTier

	local clanName = d.clan
	local newTraits = {}
	for _, cl in ipairs(D.CLAN_POOL) do
		if cl.id == d.clan then 
			clanName = cl.name 
			if cl.tiers[nextTier] then newTraits = cl.tiers[nextTier].traits or {} end
			break 
		end
	end

	S.Msg(player, "== " .. clanName .. " upgraded to TIER " .. nextTier .. "! New traits: " .. table.concat(newTraits, ", ") .. " ==", "system")
	S.Pop(player, "CLAN TIER UP", clanName .. " — Tier " .. nextTier, "amber")
	S.Push(player, d)
end)

print("[AOT_Server_Clans] Optimized Module Loaded.")