-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- Place in: StarterPlayerScripts > AOT_Client > UI_Tab_Train

local RS = game:GetService("ReplicatedStorage")
local Remotes = RS:WaitForChild("AOT"):WaitForChild("Remotes")
local Theme = require(script.Parent:WaitForChild("UI_Theme"))
local D = require(RS:WaitForChild("AOT"):WaitForChild("AOT_Data"))
local Tab = {}

function Tab.Build(parent)
	Tab.Frame = Theme.Make("Frame", {Size = UDim2.new(1,0,1,0), BackgroundTransparency = 1, Visible = false}, parent)
	Theme.MakeHeader(" // TRAINING GROUNDS", Tab.Frame, UDim2.new(1,-40,0,50), UDim2.new(0,30,0,10))

	Tab.TrainInfo = Theme.Make("TextLabel", {Size = UDim2.new(1,-60,0,20), Position = UDim2.new(0,30,0,55), BackgroundTransparency = 1, Text = "Training XP: 0", TextColor3 = Theme.C.Gold, Font = Theme.F.Button, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left}, Tab.Frame)

	-- The Giant "Click to Train" Button
	local ClickerBtn = Theme.Make("TextButton", {Size = UDim2.new(1, -60, 0, 60), Position = UDim2.new(0, 30, 0, 85), BackgroundColor3 = Theme.C.Accent, Text = "PRACTICE FORMS (+XP)", Font = Theme.F.Header, TextColor3 = Theme.C.TextWhite, TextSize = 24}, Tab.Frame)
	Theme.AddStroke(ClickerBtn, Color3.new(0,0,0), 2)

	-- Client-side prediction for visual satisfaction without server lag
	ClickerBtn.MouseButton1Down:Connect(function()
		ClickerBtn.BackgroundColor3 = Color3.fromRGB(80, 10, 10)
		-- Fire the server remote to log the click
		local clickRemote = Remotes:FindFirstChild("ClickTrain")
		if clickRemote then clickRemote:FireServer() end
	end)
	ClickerBtn.MouseButton1Up:Connect(function() ClickerBtn.BackgroundColor3 = Theme.C.Accent end)
	ClickerBtn.MouseLeave:Connect(function() ClickerBtn.BackgroundColor3 = Theme.C.Accent end)

	-- Stats Scrolling List
	local Scroll = Theme.Make("ScrollingFrame", {Size = UDim2.new(1,-60,1,-170), Position = UDim2.new(0,30,0,160), BackgroundTransparency = 1, ScrollBarThickness = 4, ScrollBarImageColor3 = Theme.C.Stroke}, Tab.Frame)
	Theme.Make("UIListLayout", {Padding = UDim.new(0, 10)}, Scroll)

	Tab.Updaters = {}
	for _, statKey in ipairs(D.STAT_ORDER) do
		local statDef = D.STATS[statKey]
		local row = Theme.Make("Frame", {Size = UDim2.new(1,0,0,50), BackgroundColor3 = Theme.C.Panel}, Scroll)
		Theme.AddStroke(row)

		Theme.Make("TextLabel", {Size = UDim2.new(0, 150, 1, 0), Position = UDim2.new(0, 15, 0, 0), BackgroundTransparency = 1, Text = statDef.name:upper(), TextColor3 = Theme.C.TextWhite, Font = Theme.F.Button, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left}, row)
		local valLbl = Theme.Make("TextLabel", {Size = UDim2.new(0, 60, 1, 0), Position = UDim2.new(0, 160, 0, 0), BackgroundTransparency = 1, Text = "0", TextColor3 = Theme.C.Gold, Font = Theme.F.Header, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left}, row)

		local cost = statDef.pointCost
		local xpCostOne = D.TRAINING_XP_PER_POINT * cost

		-- Bulk Buy Buttons
		local btnGroup = Theme.Make("Frame", {Size = UDim2.new(0, 240, 1, -10), Position = UDim2.new(1, -250, 0, 5), BackgroundTransparency = 1}, row)
		Theme.Make("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 5), HorizontalAlignment = Enum.HorizontalAlignment.Right}, btnGroup)

		local function makeBtn(txt)
			local b = Theme.Make("TextButton", {Size = UDim2.new(0, 75, 1, 0), BackgroundColor3 = Theme.C.Bg, Text = txt, Font = Theme.F.Button, TextColor3 = Theme.C.TextWhite, TextSize = 14}, btnGroup)
			Theme.AddStroke(b)
			return b
		end

		local btn1 = makeBtn("+1")
		local btn10 = makeBtn("+10")
		local btnMax = makeBtn("MAX")

		btn1.Activated:Connect(function() Remotes.DoTraining:FireServer(statKey, 1) end)
		btn10.Activated:Connect(function() Remotes.DoTraining:FireServer(statKey, 10) end)
		btnMax.Activated:Connect(function()
			-- Max calculation handled on client to fire specific amount
			local currentXp = Tab.CurrentXP or 0
			local maxAmount = math.floor(currentXp / xpCostOne)
			if maxAmount > 0 then Remotes.DoTraining:FireServer(statKey, maxAmount) end
		end)

		Tab.Updaters[statKey] = { valLbl = valLbl, btn1 = btn1, btn10 = btn10, btnMax = btnMax, xpCostOne = xpCostOne }
	end
end

function Tab.Update(payload)
	Tab.CurrentXP = payload.trainingXP or 0
	Tab.TrainInfo.Text = "Available Stat Points: " .. (payload.freeStatPoints or 0) .. "   //   Training XP: " .. Tab.CurrentXP

	for statKey, updater in pairs(Tab.Updaters) do
		updater.valLbl.Text = tostring(payload[statKey] or 0)

		local function setBtnState(btn, reqXp)
			if Tab.CurrentXP >= reqXp then
				btn.BackgroundColor3 = Theme.C.Bg
				btn.TextColor3 = Theme.C.TextWhite
			else
				btn.BackgroundColor3 = Theme.C.Bg
				btn.TextColor3 = Theme.C.Stroke
			end
		end

		setBtnState(updater.btn1, updater.xpCostOne)
		setBtnState(updater.btn10, updater.xpCostOne * 10)
		setBtnState(updater.btnMax, updater.xpCostOne) -- Max is available if they can afford at least 1
	end
end

return Tab