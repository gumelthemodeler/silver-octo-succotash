-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- Place in: StarterPlayerScripts > AOT_Client > UI_HUD

local RS = game:GetService("ReplicatedStorage")
local Remotes = RS:WaitForChild("AOT"):WaitForChild("Remotes")
local Theme = require(script.Parent:WaitForChild("UI_Theme"))

local HUD = {}

-- Load our sub-modules
local Tabs = {
	MISSIONS = require(script.Parent:WaitForChild("UI_Tab_Missions")),
	COMBAT   = require(script.Parent:WaitForChild("UI_Tab_Combat")),
	TRAIN    = require(script.Parent:WaitForChild("UI_Tab_Train")),
	ARMORY   = require(script.Parent:WaitForChild("UI_Tab_Armory")),
	INHERIT  = require(script.Parent:WaitForChild("UI_Tab_Inherit")),
	SHOP     = require(script.Parent:WaitForChild("UI_Tab_Shop")),
}

function HUD.Build(parentGui)
	local Container = Theme.Make("Frame", {Name = "HUDView", Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Theme.C.Bg, ZIndex = 10}, parentGui)

	-- TOP NAVIGATION BAR
	local TopBar = Theme.Make("Frame", {Size = UDim2.new(1, 0, 0, 50), BackgroundColor3 = Theme.C.Panel}, Container)
	Theme.AddStroke(TopBar)
	Theme.MakeHeader(" OPERATION: RETAKE", TopBar, UDim2.new(0, 300, 1, 0), UDim2.new(0, 20, 0, 0))

	local NavContainer = Theme.Make("Frame", {Size = UDim2.new(1, -320, 1, 0), Position = UDim2.new(0, 320, 0, 0), BackgroundTransparency = 1}, TopBar)
	Theme.Make("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10)}, NavContainer)
	Theme.Make("UIPadding", {PaddingRight = UDim.new(0, 20)}, NavContainer)

	-- LEFT SIDEBAR (Player Stats)
	local LeftBar = Theme.Make("Frame", {Size = UDim2.new(0, 240, 1, -50), Position = UDim2.new(0, 0, 0, 50), BackgroundColor3 = Theme.C.Panel}, Container)
	Theme.AddStroke(LeftBar)

	Theme.Make("TextLabel", {Size = UDim2.new(1, -20, 0, 30), Position = UDim2.new(0, 10, 0, 10), BackgroundTransparency = 1, Text = game.Players.LocalPlayer.DisplayName, Font = Theme.F.Header, TextColor3 = Theme.C.TextWhite, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left}, LeftBar)
	local TitleText = Theme.Make("TextLabel", {Size = UDim2.new(1, -20, 0, 20), Position = UDim2.new(0, 10, 0, 40), BackgroundTransparency = 1, Text = "Recruit // Prestige 0", Font = Theme.F.Body, TextColor3 = Theme.C.Gold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left}, LeftBar)

	-- HP Bar (Hard Edged)
	local HPBg = Theme.Make("Frame", {Size = UDim2.new(0.9, 0, 0, 22), Position = UDim2.new(0.5, 0, 0, 70), AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = Theme.C.HealthBg}, LeftBar)
	Theme.AddStroke(HPBg, Color3.new(0,0,0), 2)
	local HPFill = Theme.Make("Frame", {Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Theme.C.HealthFill, BorderSizePixel = 0}, HPBg)
	local HPText = Theme.Make("TextLabel", {Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "100 / 100", TextColor3 = Theme.C.TextWhite, Font = Theme.F.Button, TextSize = 14, ZIndex = 3}, HPBg)
	Theme.AddStroke(HPText, Color3.new(0,0,0), 1)

	local StatsFrame = Theme.Make("Frame", {Size = UDim2.new(1, -20, 0, 200), Position = UDim2.new(0, 10, 0, 110), BackgroundTransparency = 1}, LeftBar)
	Theme.Make("UIListLayout", {Padding = UDim.new(0, 8)}, StatsFrame)

	local statLabels = {}
	for _, stat in ipairs({"STR", "DEF", "SPD", "WIL", "TRN XP", "FUNDS"}) do
		local row = Theme.Make("Frame", {Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1}, StatsFrame)
		Theme.Make("TextLabel", {Size = UDim2.new(0.5, 0, 1, 0), BackgroundTransparency = 1, Text = stat, Font = Theme.F.Button, TextColor3 = Theme.C.TextGrey, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left}, row)
		statLabels[stat] = Theme.Make("TextLabel", {Size = UDim2.new(0.5, 0, 1, 0), Position = UDim2.new(0.5, 0, 0, 0), BackgroundTransparency = 1, Text = "0", Font = Theme.F.Body, TextColor3 = Theme.C.TextWhite, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Right}, row)
	end

	-- MAIN CONTENT AREA
	local MainContent = Theme.Make("Frame", {Size = UDim2.new(1, -240, 1, -50), Position = UDim2.new(0, 240, 0, 50), BackgroundColor3 = Theme.C.Bg}, Container)

	-- Initialize Tabs
	for _, tab in pairs(Tabs) do tab.Build(MainContent) end

	-- TAB NAVIGATION LOGIC
	local tabOrder = {"MISSIONS", "COMBAT", "TRAIN", "ARMORY", "INHERIT", "SHOP"}
	local tabBtns = {}

	local function SwitchTab(tabName)
		for name, tab in pairs(Tabs) do tab.Frame.Visible = (name == tabName) end
		for name, btn in pairs(tabBtns) do
			if name == tabName then
				btn.BackgroundColor3 = Theme.C.Accent
				btn.TextColor3 = Theme.C.TextWhite
			else
				btn.BackgroundColor3 = Theme.C.Bg
				btn.TextColor3 = Theme.C.TextGrey
			end
		end
	end

	for _, name in ipairs(tabOrder) do
		local btn = Theme.Make("TextButton", {Size = UDim2.new(0, 100, 0, 35), BackgroundColor3 = Theme.C.Bg, Text = name, Font = Theme.F.Button, TextColor3 = Theme.C.TextGrey, TextSize = 14}, NavContainer)
		Theme.AddStroke(btn)
		btn.Activated:Connect(function() SwitchTab(name) end)
		tabBtns[name] = btn
	end

	SwitchTab("MISSIONS")

	-- DATA ROUTING (Sends payload to everything)
	Remotes:WaitForChild("Push").OnClientEvent:Connect(function(payload, cs)
		TitleText.Text = payload.prestigeTitle .. " // Prestige " .. payload.prestige
		HPText.Text = math.floor(payload.hp) .. " / " .. payload.maxHp
		game:GetService("TweenService"):Create(HPFill, TweenInfo.new(0.2), {Size = UDim2.new(math.clamp(payload.hp / math.max(1, payload.maxHp), 0, 1), 0, 1, 0)}):Play()

		statLabels["STR"].Text = tostring(payload.csStr)
		statLabels["DEF"].Text = tostring(payload.csDef)
		statLabels["SPD"].Text = tostring(payload.csSpd)
		statLabels["WIL"].Text = tostring(payload.csWil)
		statLabels["TRN XP"].Text = tostring(payload.trainingXP)
		statLabels["FUNDS"].Text = tostring(payload.funds) .. " MF"

		-- Route to active tabs
		for _, tab in pairs(Tabs) do tab.Update(payload) end

		-- Auto-switch to Combat if in fight
		if payload.inCombat and not Tabs.COMBAT.Frame.Visible then SwitchTab("COMBAT") end
	end)

	task.spawn(function()
		local getState = Remotes:WaitForChild("GetState", 5)
		if getState then
			local state = getState:InvokeServer()
			if state then Remotes.Push:Fire(state) end
		end
	end)
end

return HUD