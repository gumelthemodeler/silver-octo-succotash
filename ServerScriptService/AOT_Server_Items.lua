-- @ScriptType: Script
-- @ScriptType: Script
-- AOT_Server_Items (Optimized)
-- Place in: ServerScriptService > AOT_Server_Items

local SS       = game:GetService("ServerScriptService")
local S        = require(SS:WaitForChild("AOT_Sessions"))
local D        = require(game:GetService("ReplicatedStorage"):WaitForChild("AOT"):WaitForChild("AOT_Data"))
local sessions = S.sessions

local SELL_VALUE = {Common=150, Uncommon=400, Rare=900, Legendary=2500, Mythical=8000}

S.RE_EquipItem.OnServerEvent:Connect(function(player, invIndex)
	local d = sessions[player.UserId]
	if not d then return end

	invIndex = tonumber(invIndex)
	if not invIndex or invIndex < 1 or invIndex > #d.inventory then return end

	local entry = d.inventory[invIndex]
	local item = D.ITEM_MAP[entry.id]
	if not item then return end

	local slotKey = "equipped" .. item.type:sub(1,1):upper() .. item.type:sub(2)
	if slotKey ~= "equippedWeapon" and slotKey ~= "equippedArmor" and slotKey ~= "equippedAccessory" then return end

	d[slotKey] = entry.id
	d.itemLevels = d.itemLevels or {}
	d.itemLevels[entry.id .. "_forge"] = entry.forgeLevel or 0

	S.Msg(player, item.name .. " equipped in " .. item.type .. " slot.", "system")
	S.Push(player, d)
end)

S.RE_SellItem.OnServerEvent:Connect(function(player, invIndex)
	local d = sessions[player.UserId]
	if not d then return end

	invIndex = tonumber(invIndex)
	if not invIndex or invIndex < 1 or invIndex > #d.inventory then return end

	local entry = d.inventory[invIndex]
	local item = D.ITEM_MAP[entry.id]

	if not item then
		table.remove(d.inventory, invIndex)
		S.Push(player, d)
		return
	end

	if d.equippedWeapon == entry.id or d.equippedArmor == entry.id or d.equippedAccessory == entry.id then
		S.Msg(player, "Unequip the item before selling it.", "warn")
		return
	end

	local value = (SELL_VALUE[item.rarity] or 150) + ((entry.forgeLevel or 0) * 200)
	d.funds = (d.funds or 0) + value
	table.remove(d.inventory, invIndex)

	S.Msg(player, "Sold " .. item.name .. " for " .. value .. " Funds.", "system")
	S.Push(player, d)
end)

S.RE_ForgeItem.OnServerEvent:Connect(function(player, slot)
	local d = sessions[player.UserId]
	if not d then return end

	local slotMap = {weapon="equippedWeapon", armor="equippedArmor", accessory="equippedAccessory"}
	local slotKey = slotMap[slot]
	local itemId = d[slotKey]

	if not slotKey or not itemId then S.Msg(player, "No item equipped in that slot.", "warn") return end

	local item = D.ITEM_MAP[itemId]
	if not item then return end

	d.itemLevels = d.itemLevels or {}
	local forgeKey = itemId .. "_forge"
	local currentLv = d.itemLevels[forgeKey] or 0

	if currentLv >= D.FORGE_MAX_LEVEL then
		S.Msg(player, item.name .. " is at max forge level.", "warn") return
	end

	local isFreeForge = false
	if d.hasBoost and currentLv == 0 then
		d.boostFreeForgeUsed = d.boostFreeForgeUsed or {}
		if not d.boostFreeForgeUsed[itemId] then
			isFreeForge = true
			d.boostFreeForgeUsed[itemId] = true
		end
	end

	local cost = D.ForgeCost(currentLv, d.hasBoost)
	if not isFreeForge then
		if (d.funds or 0) < cost then S.Msg(player, "Need " .. cost .. " funds to forge.", "warn") return end
		d.funds = d.funds - cost
	end

	d.itemLevels[forgeKey] = currentLv + 1
	for _, entry in ipairs(d.inventory) do
		if entry.id == itemId then entry.forgeLevel = d.itemLevels[forgeKey] break end
	end

	S.Msg(player, item.name .. " forged to level " .. d.itemLevels[forgeKey] .. "!" .. (isFreeForge and " (FREE)" or ""), "system")
	S.Push(player, d)
end)

S.RE_UpgradeODM.OnServerEvent:Connect(function(player)
	local d = sessions[player.UserId]
	if not d then return end

	local nextTier = (d.odmGearLevel or 0) + 1
	local upgrade = nil
	for _, up in ipairs(D.ODM_UPGRADES) do if up.tier == nextTier then upgrade = up break end end

	if not upgrade then S.Msg(player, "ODM Gear is at maximum level.", "warn") return end
	if (d.funds or 0) < upgrade.cost then S.Msg(player, "Need " .. upgrade.cost .. " funds.", "warn") return end

	d.funds = d.funds - upgrade.cost
	d.odmGearLevel = nextTier
	S.Msg(player, "ODM Gear upgraded to Tier " .. nextTier .. ": " .. upgrade.name .. "!", "system")
	S.Push(player, d)
end)

S.RE_CraftSpears.OnServerEvent:Connect(function(player, recipeId)
	local d = sessions[player.UserId]
	if not d then return end

	local recipe = nil
	for _, r in ipairs(D.SPEAR_RECIPES) do if r.id == recipeId then recipe = r break end end
	if not recipe then return end

	local costMult = (d.path == "marleyan") and D.PATHS.marleyan.passives.spearCostMult or (d.hasArsenal and 0.50 or 1.0)
	local finalCost = math.floor(recipe.cost * costMult)

	if (d.funds or 0) < finalCost then S.Msg(player, "Need " .. finalCost .. " funds.", "warn") return end

	d.consumables = d.consumables or {}
	for _, mat in ipairs(recipe.materials) do
		if (d.consumables[mat.id] or 0) < mat.qty then S.Msg(player, "Missing material: " .. mat.id, "warn") return end
	end

	d.funds = d.funds - finalCost
	for _, mat in ipairs(recipe.materials) do d.consumables[mat.id] = d.consumables[mat.id] - mat.qty end

	d.thunderSpears = (d.thunderSpears or 0) + recipe.yields
	S.Msg(player, "Crafted " .. recipe.yields .. " Thunder Spears! (Total: " .. d.thunderSpears .. ")", "system")
	S.Push(player, d)
end)

print("[AOT_Server_Items] Optimized Module Loaded.")