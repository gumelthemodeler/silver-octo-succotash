-- @ScriptType: Script
-- @ScriptType: Script
-- AOT_Server_Titans (Optimized)
-- Place in: ServerScriptService > AOT_Server_Titans

local Players = game:GetService("Players")
local SS      = game:GetService("ServerScriptService")
local S       = require(SS:WaitForChild("AOT_Sessions"))
local D       = require(game:GetService("ReplicatedStorage"):WaitForChild("AOT"):WaitForChild("AOT_Data"))
local sessions = S.sessions

local function MaxSlots(d) return d.hasVault and 8 or 4 end
local function NewTitanSlot(poolEntry)
	return { id = poolEntry.id, name = poolEntry.name, rarity = poolEntry.rarity, bonus = poolEntry.bonus, titanLevel = 0, titanXP = 0 }
end

S.RE_RollTitan.OnServerEvent:Connect(function(player, quantity)
	local d = sessions[player.UserId]
	if not d then return end

	quantity = (quantity == 10) and 10 or 1
	if (d.titanSerums or 0) < quantity then S.Msg(player, "Not enough titan serums!", "warn") return end

	local maxSlots = MaxSlots(d)

	for i = 1, quantity do
		d.titanSerums = d.titanSerums - 1
		d.titanPity = (d.titanPity or 0) + 1

		local entry = D.RollClan(d.titanPity) -- Utilizing identical pity/roll math structured in data
		local rollData = nil
		for _, t in ipairs(D.TITAN_POOL) do if t.id == entry.id then rollData = t break end end
		if not rollData then rollData = D.TITAN_POOL[math.random(#D.TITAN_POOL)] end

		local newSlot = NewTitanSlot(rollData)

		if rollData.rarity == "Legendary" or rollData.rarity == "Mythical" then d.titanPity = 0 end

		if #d.titanSlots < maxSlots then
			table.insert(d.titanSlots, newSlot)
			S.Msg(player, "TITAN OBTAINED: " .. rollData.name .. " [" .. rollData.rarity .. "]!", "titan")
		else
			S.Msg(player, "TITAN ROLLED: " .. rollData.name .. " [" .. rollData.rarity .. "] — SLOTS FULL!", "warn")
			d.pendingTitan = newSlot
		end
	end
	S.Push(player, d)
end)

S.RE_EquipTitan.OnServerEvent:Connect(function(player, slotIndex)
	local d = sessions[player.UserId]
	if not d then return end

	slotIndex = tonumber(slotIndex)
	if not slotIndex or slotIndex < 1 or slotIndex > #d.titanSlots then return end
	if d.clan == "ackerman" then S.Msg(player, "Ackerman bloodline cannot use titan form.", "warn") return end

	d.equippedTitan = slotIndex
	S.Msg(player, d.titanSlots[slotIndex].name .. " equipped.", "system")
	S.Push(player, d)
end)

S.RE_DiscardTitan.OnServerEvent:Connect(function(player, slotIndex)
	local d = sessions[player.UserId]
	if not d then return end

	slotIndex = tonumber(slotIndex)
	if not slotIndex or slotIndex < 1 or slotIndex > #d.titanSlots then return end

	local slot = d.titanSlots[slotIndex]
	table.remove(d.titanSlots, slotIndex)

	if d.equippedTitan then
		if d.equippedTitan == slotIndex then d.equippedTitan = #d.titanSlots > 0 and 1 or nil
		elseif d.equippedTitan > slotIndex then d.equippedTitan = d.equippedTitan - 1 end
	end

	if d.pendingTitan and #d.titanSlots < MaxSlots(d) then
		table.insert(d.titanSlots, d.pendingTitan)
		S.Msg(player, "Pending titan added: " .. d.pendingTitan.name .. "!", "titan")
		d.pendingTitan = nil
	end

	S.Msg(player, slot.name .. " discarded.", "system")
	S.Push(player, d)
end)

S.RE_FeedTitan.OnServerEvent:Connect(function(player, slotIndex, quantity)
	local d = sessions[player.UserId]
	if not d then return end

	slotIndex, quantity = tonumber(slotIndex), math.max(1, math.min(tonumber(quantity) or 1, 10))
	if not slotIndex or slotIndex < 1 or slotIndex > #d.titanSlots then return end

	local slot = d.titanSlots[slotIndex]
	local raritySc = D.TITAN_RARITY_XP_SCALE[slot.rarity] or 1.0
	local xpPerFeed = math.floor(D.TITAN_XP_PER_LEVEL / raritySc)
	local totalCost = 200 * quantity

	if (d.funds or 0) < totalCost then S.Msg(player, "Need " .. totalCost .. " funds.", "warn") return end

	d.funds = d.funds - totalCost
	slot.titanXP = (slot.titanXP or 0) + (xpPerFeed * quantity)

	local xpNeeded = math.floor(D.TITAN_XP_PER_LEVEL * raritySc)
	local leveled = false

	while (slot.titanLevel or 0) < D.TITAN_LEVEL_MAX and (slot.titanXP or 0) >= xpNeeded do
		slot.titanXP = slot.titanXP - xpNeeded
		slot.titanLevel = (slot.titanLevel or 0) + 1
		leveled = true
		slot.bonus = slot.bonus or {}
		for stat, gain in pairs(D.TITAN_STAT_PER_LEVEL) do slot.bonus[stat] = (slot.bonus[stat] or 0) + gain end
	end

	S.Msg(player, leveled and (slot.name .. " leveled up to Titan Level " .. slot.titanLevel .. "!") or ("Fed " .. slot.name .. "."), "titan")
	S.Push(player, d)
end)

S.RE_FuseTitans.OnServerEvent:Connect(function(player, slotA, slotB)
	local d = sessions[player.UserId]
	if not d then return end

	slotA, slotB = tonumber(slotA), tonumber(slotB)
	if not slotA or not slotB or slotA == slotB or slotA < 1 or slotA > #d.titanSlots or slotB < 1 or slotB > #d.titanSlots then return end

	local a, b = d.titanSlots[slotA], d.titanSlots[slotB]
	if a.rarity ~= b.rarity then S.Msg(player, "Titans must be same rarity.", "warn") return end

	local FUSION_MAP = { Rare = "Legendary", Legendary = "Mythical", Mythical = "Mythical" }
	local targetRarity = FUSION_MAP[a.rarity]
	if not targetRarity then return end

	local targetPool = {}
	for _, entry in ipairs(D.TITAN_POOL) do if entry.rarity == targetRarity then table.insert(targetPool, entry) end end
	if #targetPool == 0 then return end

	local resultSlot = NewTitanSlot(targetPool[math.random(1, #targetPool)])

	if a.rarity == "Mythical" and targetRarity == "Mythical" then
		for k in pairs(resultSlot.bonus) do resultSlot.bonus[k] = (resultSlot.bonus[k] or 0) + 10 end
		S.Msg(player, "MYTHICAL FUSION! Enhanced stats!", "titan")
	end

	local hi, lo = math.max(slotA, slotB), math.min(slotA, slotB)
	table.remove(d.titanSlots, hi); table.remove(d.titanSlots, lo)
	table.insert(d.titanSlots, resultSlot)

	if d.equippedTitan then
		if d.equippedTitan == slotA or d.equippedTitan == slotB then d.equippedTitan = #d.titanSlots
		else
			local rem = 0
			if d.equippedTitan > hi then rem = rem + 1 end
			if d.equippedTitan > lo then rem = rem + 1 end
			d.equippedTitan = math.max(1, d.equippedTitan - rem)
		end
	end

	d.titanFusions = (d.titanFusions or 0) + 1
	S.Msg(player, "FUSION: " .. a.name .. " + " .. b.name .. " → " .. resultSlot.name .. "!", "titan")
	S.CheckAchievements(player, d)
	S.Push(player, d)
end)

print("[AOT_Server_Titans] Optimized Module Loaded.")