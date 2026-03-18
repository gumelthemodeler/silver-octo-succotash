-- @ScriptType: Script
-- AOT_Server_Titans  (Script)
-- Place in: ServerScriptService > AOT_Server_Titans
-- Handles: serum rolls, titan slot management, equipping, discarding,
--          titan XP feeding, and titan fusion.
-- v1.0.0

local Players = game:GetService("Players")
local SS      = game:GetService("ServerScriptService")
local S       = require(SS:WaitForChild("AOT_Sessions"))
local D       = require(game:GetService("ReplicatedStorage"):WaitForChild("AOT"):WaitForChild("AOT_Data"))
local sessions = S.sessions

-- ────────────────────────────────────────────────────────────
-- CONSTANTS
-- ────────────────────────────────────────────────────────────
local BASE_TITAN_SLOTS    = 4
local VAULT_TITAN_SLOTS   = 8

local function MaxSlots(d)
	return d.hasVault and VAULT_TITAN_SLOTS or BASE_TITAN_SLOTS
end

-- Build a fresh titan slot entry from a pool entry
local function NewTitanSlot(poolEntry)
	return {
		id         = poolEntry.id,
		name       = poolEntry.name,
		rarity     = poolEntry.rarity,
		bonus      = poolEntry.bonus,
		titanLevel = 0,
		titanXP    = 0,
	}
end

-- ────────────────────────────────────────────────────────────
-- ROLL TITAN
-- Pity system: at PITY_LEGENDARY guaranteed Legendary+,
--              at PITY_MYTHICAL guaranteed Mythical.
-- ────────────────────────────────────────────────────────────
local function RollFromPool(pity)
	pity = pity or 0
	local forceMythical  = pity >= D.TITAN_PITY_MYTHICAL
	local forceLegendary = pity >= D.TITAN_PITY_LEGENDARY

	local pool   = {}
	local totalW = 0
	for _, entry in ipairs(D.TITAN_POOL) do
		if forceMythical  and entry.rarity ~= "Mythical"  then continue end
		if forceLegendary and entry.rarity == "Rare"       then continue end
		table.insert(pool, entry)
		totalW = totalW + entry.weight
	end

	local roll = math.random() * totalW
	local cum  = 0
	for _, entry in ipairs(pool) do
		cum = cum + entry.weight
		if roll < cum then return entry end
	end
	return pool[#pool]
end

S.RE_RollTitan.OnServerEvent:Connect(function(player, quantity)
	local d = sessions[player.UserId]
	if not d then return end

	quantity = (quantity == 10) and 10 or 1   -- only 1 or 10-roll
	if (d.titanSerums or 0) < quantity then
		S.Msg(player, "Not enough titan serums! (Have " .. (d.titanSerums or 0) .. ", need " .. quantity .. ")", "warn")
		return
	end

	local maxSlots = MaxSlots(d)
	local results  = {}

	for i = 1, quantity do
		d.titanSerums = d.titanSerums - 1
		d.titanPity   = (d.titanPity or 0) + 1

		local entry    = RollFromPool(d.titanPity)
		local newSlot  = NewTitanSlot(entry)
		table.insert(results, newSlot)

		-- Pity reset
		if entry.rarity == "Legendary" or entry.rarity == "Mythical" then
			d.titanPity = 0
		end
		if entry.rarity == "Mythical" then
			d.titanPity = 0  -- hard reset on mythical
		end

		-- Add to slots if space
		if #d.titanSlots < maxSlots then
			table.insert(d.titanSlots, newSlot)
			S.Msg(player, "TITAN OBTAINED: " .. entry.name .. " [" .. entry.rarity .. "]!", "titan")
		else
			-- Slots full — notify but still show what was rolled (player must discard first)
			S.Msg(player, "TITAN ROLLED: " .. entry.name .. " [" .. entry.rarity .. "] — SLOTS FULL! Discard one first.", "warn")
			-- Store in a pending list so the client can choose what to do
			d.pendingTitan = newSlot
		end
	end

	S.Push(player, d)
end)

-- ────────────────────────────────────────────────────────────
-- EQUIP TITAN
-- slotIndex = integer index into d.titanSlots
-- ────────────────────────────────────────────────────────────
S.RE_EquipTitan.OnServerEvent:Connect(function(player, slotIndex)
	local d = sessions[player.UserId]
	if not d then return end

	slotIndex = tonumber(slotIndex)
	if not slotIndex or slotIndex < 1 or slotIndex > #d.titanSlots then
		S.Msg(player, "Invalid titan slot.", "warn")
		return
	end
	-- Ackerman clan cannot equip titans
	if d.clan == "ackerman" then
		S.Msg(player, "Ackerman bloodline cannot use titan form.", "warn")
		return
	end

	d.equippedTitan = slotIndex
	local slot = d.titanSlots[slotIndex]
	S.Msg(player, slot.name .. " equipped as active titan.", "system")
	S.Push(player, d)
end)

-- ────────────────────────────────────────────────────────────
-- DISCARD TITAN
-- ────────────────────────────────────────────────────────────
S.RE_DiscardTitan.OnServerEvent:Connect(function(player, slotIndex)
	local d = sessions[player.UserId]
	if not d then return end

	slotIndex = tonumber(slotIndex)
	if not slotIndex or slotIndex < 1 or slotIndex > #d.titanSlots then
		S.Msg(player, "Invalid titan slot.", "warn")
		return
	end

	local slot = d.titanSlots[slotIndex]
	table.remove(d.titanSlots, slotIndex)

	-- Adjust equippedTitan index
	if d.equippedTitan then
		if d.equippedTitan == slotIndex then
			d.equippedTitan = #d.titanSlots > 0 and 1 or nil
		elseif d.equippedTitan > slotIndex then
			d.equippedTitan = d.equippedTitan - 1
		end
	end

	-- If there was a pending titan (slots were full), auto-add it now
	if d.pendingTitan then
		table.insert(d.titanSlots, d.pendingTitan)
		S.Msg(player, "Pending titan added: " .. d.pendingTitan.name .. "!", "titan")
		d.pendingTitan = nil
	end

	S.Msg(player, slot.name .. " discarded.", "system")
	S.Push(player, d)
end)

-- ────────────────────────────────────────────────────────────
-- FEED TITAN XP
-- Spend funds to give a titan slot XP, leveling it up.
-- ────────────────────────────────────────────────────────────
local TITAN_FEED_COST = 200   -- funds per feed action

S.RE_FeedTitan.OnServerEvent:Connect(function(player, slotIndex, quantity)
	local d = sessions[player.UserId]
	if not d then return end

	slotIndex = tonumber(slotIndex)
	quantity  = math.max(1, math.min(tonumber(quantity) or 1, 10))

	if not slotIndex or slotIndex < 1 or slotIndex > #d.titanSlots then
		S.Msg(player, "Invalid titan slot.", "warn")
		return
	end

	local slot      = d.titanSlots[slotIndex]
	local raritySc  = D.TITAN_RARITY_XP_SCALE[slot.rarity] or 1.0
	local xpPerFeed = math.floor(D.TITAN_XP_PER_LEVEL / raritySc)
	local totalCost = TITAN_FEED_COST * quantity

	if (d.funds or 0) < totalCost then
		S.Msg(player, "Not enough funds! (Need " .. totalCost .. ")", "warn")
		return
	end

	d.funds      = d.funds - totalCost
	slot.titanXP = (slot.titanXP or 0) + xpPerFeed * quantity

	-- Level up — threshold scales by rarity (same as xpPerFeed calculation)
	local xpNeeded = math.floor(D.TITAN_XP_PER_LEVEL * raritySc)
	local leveled  = false
	while (slot.titanLevel or 0) < D.TITAN_LEVEL_MAX do
		if (slot.titanXP or 0) >= xpNeeded then
			slot.titanXP    = slot.titanXP - xpNeeded
			slot.titanLevel = (slot.titanLevel or 0) + 1
			leveled         = true
			-- Apply stat gains (same as CombatVictory titan XP path)
			slot.bonus = slot.bonus or {}
			for stat, gain in pairs(D.TITAN_STAT_PER_LEVEL) do
				slot.bonus[stat] = (slot.bonus[stat] or 0) + gain
			end
		else
			break
		end
	end

	if leveled then
		S.Msg(player, slot.name .. " leveled up to Titan Level " .. slot.titanLevel
			.. "! Bonuses increased.", "titan")
	else
		local xpLeft = xpNeeded - (slot.titanXP or 0)
		S.Msg(player, "Fed " .. slot.name .. ". " .. xpLeft .. " XP to next level.", "system")
	end
	S.Push(player, d)
end)

-- ────────────────────────────────────────────────────────────
-- TITAN FUSION
-- Fuse two titans to create a higher-rarity version.
-- Rules:
--   2× Rare → 1× Legendary (random from Legendary pool)
--   2× Legendary → 1× Mythical (random from Mythical pool)
--   2× Mythical → 1× Mythical with bonus stats (+10 to all)
-- ────────────────────────────────────────────────────────────
local FUSION_RARITY_MAP = {
	Rare      = "Legendary",
	Legendary = "Mythical",
	Mythical  = "Mythical",  -- bonus stats instead of rarity upgrade
}

S.RE_FuseTitans.OnServerEvent:Connect(function(player, slotA, slotB)
	local d = sessions[player.UserId]
	if not d then return end

	slotA = tonumber(slotA)
	slotB = tonumber(slotB)
	if not slotA or not slotB or slotA == slotB then
		S.Msg(player, "Select two different titan slots to fuse.", "warn")
		return
	end
	if slotA < 1 or slotA > #d.titanSlots or slotB < 1 or slotB > #d.titanSlots then
		S.Msg(player, "Invalid titan slot selection.", "warn")
		return
	end

	local a = d.titanSlots[slotA]
	local b = d.titanSlots[slotB]

	if a.rarity ~= b.rarity then
		S.Msg(player, "Both titans must be the same rarity to fuse.", "warn")
		return
	end

	local targetRarity = FUSION_RARITY_MAP[a.rarity]
	if not targetRarity then
		S.Msg(player, "These titans cannot be fused.", "warn")
		return
	end

	-- Build target pool
	local targetPool = {}
	for _, entry in ipairs(D.TITAN_POOL) do
		if entry.rarity == targetRarity then
			table.insert(targetPool, entry)
		end
	end
	if #targetPool == 0 then return end

	local resultEntry = targetPool[math.random(1, #targetPool)]
	local resultSlot  = NewTitanSlot(resultEntry)

	-- Bonus stat boost for same-rarity mythical fusion
	if a.rarity == "Mythical" and targetRarity == "Mythical" then
		for k in pairs(resultSlot.bonus) do
			resultSlot.bonus[k] = (resultSlot.bonus[k] or 0) + 10
		end
		S.Msg(player, "MYTHICAL FUSION! " .. resultSlot.name .. " gains enhanced stats!", "titan")
	end

	-- Remove consumed slots (higher index first to avoid shifting issues)
	local hi = math.max(slotA, slotB)
	local lo = math.min(slotA, slotB)
	table.remove(d.titanSlots, hi)
	table.remove(d.titanSlots, lo)

	-- Add result
	table.insert(d.titanSlots, resultSlot)

	-- Fix equippedTitan
	if d.equippedTitan then
		if d.equippedTitan == slotA or d.equippedTitan == slotB then
			d.equippedTitan = #d.titanSlots
		else
			-- Adjust for removed indices
			local removed = 0
			if d.equippedTitan > hi then removed = removed + 1 end
			if d.equippedTitan > lo then removed = removed + 1 end
			d.equippedTitan = d.equippedTitan - removed
			if d.equippedTitan < 1 then d.equippedTitan = 1 end
		end
	end

	d.titanFusions = (d.titanFusions or 0) + 1

	S.Msg(player, "FUSION: " .. a.name .. " + " .. b.name .. " → " .. resultSlot.name .. " [" .. resultSlot.rarity .. "]!", "titan")
	S.CheckAchievements(player, d)
	S.Push(player, d)
end)

print("[AOT_Server_Titans] Loaded.")
