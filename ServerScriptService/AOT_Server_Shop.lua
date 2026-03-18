-- @ScriptType: Script
-- AOT_Server_Shop  (Script)
-- Place in: ServerScriptService > AOT_Server_Shop
-- Handles: daily rotating shop, developer product purchases,
--          gamepass callbacks, promo code redemption, shop rerolls.
-- v1.0.0

local Players            = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local SS                 = game:GetService("ServerScriptService")
local S                  = require(SS:WaitForChild("AOT_Sessions"))
local D                  = require(game:GetService("ReplicatedStorage"):WaitForChild("AOT"):WaitForChild("AOT_Data"))
local sessions           = S.sessions

-- ────────────────────────────────────────────────────────────
-- SHOP GENERATION
-- Daily shop uses shopSeed (= DayNumber()) as a deterministic seed
-- so all players see the same shop on the same UTC day.
-- ────────────────────────────────────────────────────────────
local function WeightedRoll(weights, seed, index)
	-- Deterministic RNG: seed + index
	math.randomseed(seed * 1000 + index)
	local total = 0
	for _, w in pairs(weights) do total = total + w end
	local roll  = math.random() * total
	local cum   = 0
	for rarity, w in pairs(weights) do
		cum = cum + w
		if roll < cum then return rarity end
	end
	return "Common"
end

function S.GetDailyShop(seed)
	-- Collect items by rarity
	local byRarity = {}
	for _, item in ipairs(D.ITEMS) do
		byRarity[item.rarity] = byRarity[item.rarity] or {}
		table.insert(byRarity[item.rarity], item)
	end

	local shop = {}
	local seen = {}
	for i = 1, D.SHOP_SLOTS do
		local rarity = WeightedRoll(D.SHOP_WEIGHTS, seed, i)
		local pool   = byRarity[rarity]
		if pool and #pool > 0 then
			-- Pick from rarity pool, avoiding duplicates
			math.randomseed(seed * 100 + i * 7)
			local attempts = 0
			local item = nil
			repeat
				item = pool[math.random(1, #pool)]
				attempts = attempts + 1
			until not seen[item.id] or attempts > 20
			seen[item.id] = true
			table.insert(shop, {
				id     = item.id,
				name   = item.name,
				rarity = item.rarity,
				type   = item.type,
				price  = D.SHOP_PRICES[item.rarity] or 600,
				bonus  = item.bonus,
			})
		end
	end
	return shop
end

-- ────────────────────────────────────────────────────────────
-- SHOP BUY
-- ────────────────────────────────────────────────────────────
S.RE_ShopBuy.OnServerEvent:Connect(function(player, itemId)
	local d = sessions[player.UserId]
	if not d then return end

	local today = D.DayNumber()
	if (d.shopSeed or 0) ~= today then
		d.shopSeed     = today
		d.shopRerolled = false
	end

	local shop = S.GetDailyShop(d.shopSeed)
	local entry = nil
	for _, e in ipairs(shop) do
		if e.id == itemId then entry = e break end
	end

	if not entry then
		S.Msg(player, "That item isn't in today's shop.", "warn")
		return
	end

	if (d.funds or 0) < entry.price then
		S.Msg(player, "Not enough funds! (Need " .. entry.price .. ")", "warn")
		return
	end

	d.funds = d.funds - entry.price
	table.insert(d.inventory, {id=entry.id, forgeLevel=0})
	S.Msg(player, "Purchased " .. entry.name .. " from the shop!", "system")
	S.Push(player, d)
end)

-- ────────────────────────────────────────────────────────────
-- SHOP REROLL
-- One reroll per day (costs funds). VIP gets one free reroll.
-- ────────────────────────────────────────────────────────────
S.RE_ShopReroll.OnServerEvent:Connect(function(player)
	local d = sessions[player.UserId]
	if not d then return end

	local today = D.DayNumber()
	if (d.shopSeed or 0) ~= today then
		d.shopSeed     = today
		d.shopRerolled = false
	end

	if d.shopRerolled then
		S.Msg(player, "You've already rerolled the shop today.", "warn")
		return
	end

	-- VIP gets free reroll; others pay
	if not d.hasVIP then
		if (d.funds or 0) < D.SHOP_REROLL_COST then
			S.Msg(player, "Reroll costs " .. D.SHOP_REROLL_COST .. " Funds.", "warn")
			return
		end
		d.funds = d.funds - D.SHOP_REROLL_COST
	end

	d.shopSeed    = today + 10000  -- offset seed so reroll gives different items
	d.shopRerolled = true
	S.Msg(player, "Shop rerolled!", "system")
	S.Push(player, d)
end)

-- ────────────────────────────────────────────────────────────
-- PROMO CODE REDEMPTION
-- ────────────────────────────────────────────────────────────
S.RE_RedeemCode.OnServerEvent:Connect(function(player, code)
	local d = sessions[player.UserId]
	if not d then return end

	code = tostring(code):upper():gsub("%s", "")
	local codeData = D.PROMO_CODES[code]

	if not codeData then
		S.Msg(player, "Invalid promo code.", "warn")
		return
	end
	if not codeData.active then
		S.Msg(player, "This promo code has expired.", "warn")
		return
	end

	-- Persisted per-player in d.redeemedCodes — survives server restarts
	d.redeemedCodes = d.redeemedCodes or {}
	if d.redeemedCodes[code] then
		S.Msg(player, "You've already redeemed this code.", "warn")
		return
	end
	d.redeemedCodes[code] = true

	-- Apply rewards
	d.funds        = (d.funds       or 0) + (codeData.funds  or 0)
	d.titanSerums  = (d.titanSerums or 0) + (codeData.serums or 0)
	d.clanVials    = (d.clanVials   or 0) + (codeData.vials  or 0)

	-- Award XP through the proper helper so level-ups are handled
	if (codeData.xp or 0) > 0 then
		S.AwardXP(player, d, codeData.xp, S.CalcCS(d))
	end

	local rewStr = ""
	if (codeData.funds  or 0) > 0 then rewStr = rewStr .. "+" .. codeData.funds  .. " Funds  " end
	if (codeData.serums or 0) > 0 then rewStr = rewStr .. "+" .. codeData.serums .. " Serums  " end
	if (codeData.vials  or 0) > 0 then rewStr = rewStr .. "+" .. codeData.vials  .. " Vials  " end
	if (codeData.xp     or 0) > 0 then rewStr = rewStr .. "+" .. codeData.xp     .. " XP" end

	S.Msg(player, "Code redeemed! " .. rewStr, "system")
	S.Pop(player, "CODE REDEEMED", rewStr, "amber")
	S.Save(player.UserId, d)
	S.Push(player, d)
end)

-- ────────────────────────────────────────────────────────────
-- DEVELOPER PRODUCT HANDLER
-- Called by Roblox when a player completes a DevProduct purchase.
-- ────────────────────────────────────────────────────────────
local PRODUCT_HANDLERS = {
	[D.DP_FUNDS_SM]    = function(d) d.funds       = (d.funds       or 0) + 5000  return "+5,000 Funds" end,
	[D.DP_FUNDS_MD]    = function(d) d.funds       = (d.funds       or 0) + 25000 return "+25,000 Funds" end,
	[D.DP_FUNDS_LG]    = function(d) d.funds       = (d.funds       or 0) + 100000 return "+100,000 Funds" end,
	[D.DP_SERUMS_1]    = function(d) d.titanSerums = (d.titanSerums or 0) + 1  return "+1 Titan Serum" end,
	[D.DP_SERUMS_5]    = function(d) d.titanSerums = (d.titanSerums or 0) + 5  return "+5 Titan Serums" end,
	[D.DP_VIALS_1]     = function(d) d.clanVials   = (d.clanVials   or 0) + 1  return "+1 Blood Vial" end,
	[D.DP_VIALS_5]     = function(d) d.clanVials   = (d.clanVials   or 0) + 5  return "+5 Blood Vials" end,
	[D.DP_SPEARS_10]   = function(d) d.thunderSpears=(d.thunderSpears or 0)+10 return "+10 Thunder Spears" end,
	[D.DP_BOOST_24H]   = function(d)
		local newExpiry = math.max(os.time(), d.boostExpiry or 0) + 86400
		d.boostExpiry  = newExpiry
		d.hasBoost     = true
		return "+24hr 2× Boost"
	end,
}

MarketplaceService.ProcessReceipt = function(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then return Enum.ProductPurchaseDecision.NotProcessedYet end

	local d = sessions[info.PlayerId]
	if not d then return Enum.ProductPurchaseDecision.NotProcessedYet end

	local handler = PRODUCT_HANDLERS[info.ProductId]
	if not handler then
		warn("[AOT_Server_Shop] Unhandled ProductId: " .. tostring(info.ProductId))
		return Enum.ProductPurchaseDecision.PurchaseGranted  -- grant anyway to avoid double-charge
	end

	local msg = handler(d)
	S.Msg(player, "Purchase successful! " .. (msg or ""), "system")
	S.Pop(player, "PURCHASE COMPLETE", msg or "", "amber")
	S.Push(player, d)
	S.Save(info.PlayerId, d)  -- save immediately after purchase

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- ────────────────────────────────────────────────────────────
-- GAMEPASS PURCHASE CALLBACK
-- Players can click "Buy Gamepass" in-game; this re-checks ownership.
-- ────────────────────────────────────────────────────────────
S.RE_BuyPass.OnServerEvent:Connect(function(player, passId)
	-- Prompt the purchase dialog
	MarketplaceService:PromptGamePassPurchase(player, passId)
end)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gpId, purchased)
	if not purchased then return end
	local d = sessions[player.UserId]
	if not d then return end

	local grantMap = {
		[D.GP_VIP]      = function() d.hasVIP       = true end,
		[D.GP_PATHS]    = function() d.hasPathsPass  = true end,
		[D.GP_AUTOTRAIN]= function() d.hasAutoTrain  = true end,
		[D.GP_VAULT]    = function() d.hasVault      = true end,
		[D.GP_ARSENAL]  = function() d.hasArsenal    = true end,
	}

	local grant = grantMap[gpId]
	if grant then
		grant()
		S.Msg(player, "Gamepass activated! Thank you for your support.", "system")
		S.Push(player, d)
		S.Save(player.UserId, d)
	end
end)

print("[AOT_Server_Shop] Loaded.")
