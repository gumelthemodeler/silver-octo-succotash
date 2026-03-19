-- @ScriptType: ModuleScript
-- Paste this into UI_Tab_Missions, UI_Tab_Combat, UI_Tab_Armory, and UI_Tab_Shop
local Theme = require(script.Parent:WaitForChild("UI_Theme"))
local Tab = {}

function Tab.Build(parent)
	Tab.Frame = Theme.Make("Frame", {Size = UDim2.new(1,0,1,0), BackgroundTransparency = 1, Visible = false}, parent)
	Theme.MakeHeader(" // " .. script.Name, Tab.Frame, UDim2.new(1,-40,0,60), UDim2.new(0,30,0,20))
end

function Tab.Update(payload)
	-- Update logic will go here
end

return Tab