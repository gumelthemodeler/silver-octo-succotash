-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- Place in: StarterPlayerScripts > AOT_Client > UI_Tab_Inherit

local RS = game:GetService("ReplicatedStorage")
local Remotes = RS:WaitForChild("AOT"):WaitForChild("Remotes")
local Theme = require(script.Parent:WaitForChild("UI_Theme"))
local Tab = {}

function Tab.Build(parent)
	Tab.Frame = Theme.Make("Frame", {Size = UDim2.new(1,0,1,0), BackgroundTransparency = 1, Visible = false}, parent)
	Theme.MakeHeader(" // INHERITANCE", Tab.Frame, UDim2.new(1,-40,0,40), UDim2.new(0,30,0,10))

	-- LEFT PANEL: Clan / Bloodline
	local ClanPanel = Theme.Make("Frame", {Size = UDim2.new(0.4, 0, 1, -80), Position = UDim2.new(0, 30, 0, 60), BackgroundColor3 = Theme.C.Panel}, Tab.Frame)
	Theme.AddStroke(ClanPanel)
	Theme.MakeHeader(" BLOODLINE", ClanPanel, UDim2.new(1,-20,0,30), UDim2.new(0,10,0,10))

	Tab.ClanName = Theme.Make("TextLabel", {Size = UDim2.new(1,-20,0,30), Position = UDim2.new(0,10,0,40), BackgroundTransparency = 1, Text = "UNKNOWN", Font = Theme.F.Header, TextColor3 = Theme.C.TextWhite, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Left}, ClanPanel)
	Tab.ClanTier = Theme.Make("TextLabel", {Size = UDim2.new(1,-20,0,20), Position = UDim2.new(0,10,0,70), BackgroundTransparency = 1, Text = "Tier: 0", Font = Theme.F.Button, TextColor3 = Theme.C.Gold, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left}, ClanPanel)
	Tab.ClanBuffs = Theme.Make("TextLabel", {Size = UDim2.new(1,-20,0,100), Position = UDim2.new(0,10,0,95), BackgroundTransparency = 1, Text = "Traits:\nNone", Font = Theme.F.Body, TextColor3 = Theme.C.TextGrey, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true}, ClanPanel)

	Tab.VialText = Theme.Make("TextLabel", {Size = UDim2.new(1,-20,0,20), Position = UDim2.new(0,10,1,-80), BackgroundTransparency = 1, Text = "Blood Vials: 0", Font = Theme.F.Button, TextColor3 = Theme.C.Accent, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center}, ClanPanel)

	local btnRollClan = Theme.Make("TextButton", {Size = UDim2.new(1,-20,0,40), Position = UDim2.new(0,10,1,-50), BackgroundColor3 = Theme.C.Bg, Text = "AWAKEN BLOODLINE (1 VIAL)", Font = Theme.F.Button, TextColor3 = Theme.C.TextWhite, TextSize = 16}, ClanPanel)
	Theme.AddStroke(btnRollClan); btnRollClan.Activated:Connect(function() Remotes.RollClan:FireServer() end)

	-- RIGHT PANEL: Titan Vessels
	local TitanPanel = Theme.Make("Frame", {Size = UDim2.new(0.5, 0, 1, -80), Position = UDim2.new(0.45, 30, 0, 60), BackgroundTransparency = 1}, Tab.Frame)
	Theme.MakeHeader(" TITAN VESSELS", TitanPanel, UDim2.new(1,-20,0,30), UDim2.new(0,0,0,10))

	Tab.SerumText = Theme.Make("TextLabel", {Size = UDim2.new(1,0,0,20), Position = UDim2.new(0,0,0,45), BackgroundTransparency = 1, Text = "Titan Serums: 0", Font = Theme.F.Button, TextColor3 = Theme.C.Gold, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left}, TitanPanel)

	Tab.TitanScroll = Theme.Make("ScrollingFrame", {Size = UDim2.new(1, 0, 1, -130), Position = UDim2.new(0, 0, 0, 70), BackgroundTransparency = 1, ScrollBarThickness = 4, ScrollBarImageColor3 = Theme.C.Stroke}, TitanPanel)
	Theme.Make("UIListLayout", {Padding = UDim.new(0, 10)}, Tab.TitanScroll)

	-- Gacha Buttons
	local btnRoll1 = Theme.Make("TextButton", {Size = UDim2.new(0.48,0,0,40), Position = UDim2.new(0,0,1,-45), BackgroundColor3 = Theme.C.Bg, Text = "INJECT SERUM (1X)", Font = Theme.F.Button, TextColor3 = Theme.C.TextWhite, TextSize = 14}, TitanPanel)
	Theme.AddStroke(btnRoll1); btnRoll1.Activated:Connect(function() Remotes.RollTitan:FireServer(1) end)

	local btnRoll10 = Theme.Make("TextButton", {Size = UDim2.new(0.48,0,0,40), Position = UDim2.new(0.52,0,1,-45), BackgroundColor3 = Theme.C.Bg, Text = "MASS INJECTION (10X)", Font = Theme.F.Button, TextColor3 = Theme.C.Gold, TextSize = 14}, TitanPanel)
	Theme.AddStroke(btnRoll10); btnRoll10.Activated:Connect(function() Remotes.RollTitan:FireServer(10) end)
end

function Tab.Update(payload)
	-- Update Clan Info
	Tab.ClanName.Text = (payload.clan and string.upper(payload.clan) or "UNKNOWN BLOODLINE")
	Tab.ClanTier.Text = "Tier: " .. (payload.clanTier or 0)

	local traitStr = "Traits:\n"
	if payload.clanTraits and #payload.clanTraits > 0 then
		for _, t in ipairs(payload.clanTraits) do traitStr = traitStr .. "- " .. t .. "\n" end
	else
		traitStr = traitStr .. "None"
	end
	Tab.ClanBuffs.Text = traitStr
	Tab.VialText.Text = "Blood Vials: " .. (payload.clanVials or 0)
	Tab.SerumText.Text = "Titan Serums: " .. (payload.titanSerums or 0)

	-- Rebuild Titan Scroll list
	for _, child in ipairs(Tab.TitanScroll:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end

	for index, slot in ipairs(payload.titanSlots or {}) do
		local card = Theme.Make("Frame", {Size = UDim2.new(1,-15,0,80), BackgroundColor3 = Theme.C.Panel}, Tab.TitanScroll)
		Theme.AddStroke(card)

		-- Color code rarity
		local rColor = Theme.C.TextWhite
		if slot.rarity == "Legendary" then rColor = Theme.C.Accent elseif slot.rarity == "Mythical" then rColor = Theme.C.Gold end

		Theme.Make("TextLabel", {Size = UDim2.new(0,200,0,25), Position = UDim2.new(0,10,0,5), BackgroundTransparency = 1, Text = slot.name:upper(), Font = Theme.F.Header, TextColor3 = rColor, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left}, card)
		Theme.Make("TextLabel", {Size = UDim2.new(0,200,0,15), Position = UDim2.new(0,10,0,30), BackgroundTransparency = 1, Text = "Level " .. (slot.titanLevel or 0) .. " [" .. slot.rarity .. "]", Font = Theme.F.Body, TextColor3 = Theme.C.TextGrey, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left}, card)

		-- Parse Buffs
		local buffStr = ""
		if slot.bonus then
			for k, v in pairs(slot.bonus) do buffStr = buffStr .. string.upper(k) .. " +" .. v .. "   " end
		end
		Theme.Make("TextLabel", {Size = UDim2.new(0,250,0,20), Position = UDim2.new(0,10,0,50), BackgroundTransparency = 1, Text = buffStr, Font = Theme.F.Button, TextColor3 = Theme.C.TextWhite, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left}, card)

		-- Equip Button
		local isEquipped = (payload.equippedTitan == index)
		local btnText = isEquipped and "EQUIPPED" or "EQUIP"
		local btnColor = isEquipped and Theme.C.Bg or Theme.C.PanelLight
		local eqBtn = Theme.Make("TextButton", {Size = UDim2.new(0,90,0,30), Position = UDim2.new(1,-100,0.5,-15), BackgroundColor3 = btnColor, Text = btnText, Font = Theme.F.Button, TextColor3 = Theme.C.TextWhite, TextSize = 14}, card)
		Theme.AddStroke(eqBtn)

		if not isEquipped then
			eqBtn.Activated:Connect(function() Remotes.EquipTitan:FireServer(index) end)
		end
	end
end

return Tab