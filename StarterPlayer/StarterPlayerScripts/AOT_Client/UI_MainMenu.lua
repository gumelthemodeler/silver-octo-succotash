-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- Place in: StarterPlayerScripts > AOT_Client > UI_MainMenu

local RS = game:GetService("ReplicatedStorage")
local AOT = RS:WaitForChild("AOT")
local Remotes = AOT:WaitForChild("Remotes")
local D = require(AOT:WaitForChild("AOT_Data"))
local Theme = require(script.Parent:WaitForChild("UI_Theme"))

local MainMenu = {}

function MainMenu.Build(parentGui, onDeployCallback)
	local Container = Theme.Make("Frame", {
		Name = "MainMenuView", Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Theme.C.Bg, ZIndex = 50
	}, parentGui)

	-- LEFT SIDE: Title & Changelog
	local LeftPanel = Theme.Make("Frame", { Size = UDim2.new(0.45, 0, 1, -80), Position = UDim2.new(0, 40, 0, 40), BackgroundTransparency = 1 }, Container)

	Theme.Make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 80), BackgroundTransparency = 1, Text = "ATTACK ON TITAN\nINCREMENTAL",
		TextColor3 = Theme.C.TextWhite, Font = Theme.F.Header, TextSize = 48,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top
	}, LeftPanel)

	local ChangePanel = Theme.Make("Frame", { Size = UDim2.new(1, 0, 0.6, 0), Position = UDim2.new(0, 0, 0, 120), BackgroundColor3 = Theme.C.Panel }, LeftPanel)
	Theme.AddStroke(ChangePanel)
	Theme.MakeHeader(" UPDATE LOG", ChangePanel, UDim2.new(1, -20, 0, 40), UDim2.new(0, 10, 0, 10))

	local LogScroll = Theme.Make("ScrollingFrame", { Size = UDim2.new(1, -20, 1, -60), Position = UDim2.new(0, 10, 0, 50), BackgroundTransparency = 1, ScrollBarThickness = 2, ScrollBarImageColor3 = Theme.C.Stroke }, ChangePanel)
	Theme.Make("UIListLayout", {Padding = UDim.new(0, 8)}, LogScroll)

	if D.UPDATE_LOG and D.UPDATE_LOG[1] then
		local latest = D.UPDATE_LOG[1]
		Theme.Make("TextLabel", {Size = UDim2.new(1,0,0,25), BackgroundTransparency = 1, Text = "Version " .. latest.version, TextColor3 = Theme.C.Accent, Font = Theme.F.Button, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left}, LogScroll)
		for _, entry in ipairs(latest.entries or {}) do
			Theme.Make("TextLabel", {Size = UDim2.new(1,0,0,20), BackgroundTransparency = 1, Text = "- " .. entry, TextColor3 = Theme.C.TextGrey, Font = Theme.F.Body, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left}, LogScroll)
		end
	end

	-- DEPLOY BUTTON
	local DeployBtn = Theme.Make("TextButton", { Size = UDim2.new(1, 0, 0, 80), Position = UDim2.new(0, 0, 1, -80), BackgroundColor3 = Theme.C.Accent, Text = "DEPLOY", Font = Theme.F.Header, TextColor3 = Theme.C.TextWhite, TextSize = 32 }, LeftPanel)
	Theme.AddStroke(DeployBtn, Color3.new(0,0,0), 2)

	DeployBtn.Activated:Connect(function()
		Container.Visible = false
		if onDeployCallback then onDeployCallback() end
	end)

	-- RIGHT SIDE: Leaderboard
	local RightPanel = Theme.Make("Frame", { Size = UDim2.new(0.45, 0, 1, -80), Position = UDim2.new(1, -40, 0, 40), AnchorPoint = Vector2.new(1, 0), BackgroundColor3 = Theme.C.Panel }, Container)
	Theme.AddStroke(RightPanel)
	Theme.MakeHeader(" TOP SOLDIERS (ELO)", RightPanel, UDim2.new(1, -20, 0, 50), UDim2.new(0, 10, 0, 10))

	local LBScroll = Theme.Make("ScrollingFrame", { Size = UDim2.new(1, -20, 1, -70), Position = UDim2.new(0, 10, 0, 60), BackgroundTransparency = 1, ScrollBarThickness = 2, ScrollBarImageColor3 = Theme.C.Stroke }, RightPanel)
	Theme.Make("UIListLayout", {Padding = UDim.new(0, 5)}, LBScroll)

	task.spawn(function()
		local getLB = Remotes:WaitForChild("GetLeaderboard", 5)
		if getLB then
			local lbData = getLB:InvokeServer("elo")
			if lbData and lbData.board then
				for _, row in ipairs(lbData.board) do
					local rowFrame = Theme.Make("Frame", {Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = Theme.C.Bg}, LBScroll)
					Theme.AddStroke(rowFrame, Theme.C.Stroke, 1)
					Theme.Make("TextLabel", {Size = UDim2.new(0, 40, 1, 0), BackgroundTransparency = 1, Text = "#"..row.rank, TextColor3 = Theme.C.Accent, Font = Theme.F.Button, TextSize = 16}, rowFrame)
					Theme.Make("TextLabel", {Size = UDim2.new(0.5, 0, 1, 0), Position = UDim2.new(0, 50, 0, 0), BackgroundTransparency = 1, Text = row.name, TextColor3 = Theme.C.TextWhite, Font = Theme.F.Body, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left}, rowFrame)
					Theme.Make("TextLabel", {Size = UDim2.new(0.3, 0, 1, 0), Position = UDim2.new(0.7, 0, 0, 0), BackgroundTransparency = 1, Text = row.elo .. " ELO", TextColor3 = Theme.C.Gold, Font = Theme.F.Button, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Right}, rowFrame)
				end
			end
		end
	end)

	return Container
end

return MainMenu