-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- Place in: StarterPlayerScripts > AOT_Client > UI_Theme

local Theme = {}

-- GRITTY MEDIEVAL PALETTE
Theme.C = {
	Bg         = Color3.fromRGB(8, 8, 10),       -- Pitch black/charcoal
	Panel      = Color3.fromRGB(18, 18, 20),     -- Wrought iron
	PanelLight = Color3.fromRGB(28, 28, 32),     -- Scuffed iron
	Stroke     = Color3.fromRGB(50, 50, 55),     -- Tarnished steel
	Accent     = Color3.fromRGB(130, 15, 15),    -- Dried blood
	Gold       = Color3.fromRGB(150, 110, 35),   -- Old brass/tarnished gold
	TextWhite  = Color3.fromRGB(210, 210, 210),  -- Pale silver text
	TextGrey   = Color3.fromRGB(110, 110, 115),  -- Ash grey
}

-- RUSTIC FONTS
Theme.F = {
	Header = Enum.Font.Antique,   -- Chiseled, old-world medieval headers
	Body   = Enum.Font.Garamond,  -- Classic, parchment-style readable text
	Button = Enum.Font.Bodoni,    -- Sharp, steel-like serif for UI elements
}

function Theme.Make(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props) do inst[k] = v end
	if parent then inst.Parent = parent end
	return inst
end

-- Replaced AddCorner: Everything is sharp now.
function Theme.AddStroke(parent, color, thickness)
	Theme.Make("UIStroke", {
		Color = color or Theme.C.Stroke, 
		Thickness = thickness or 1, 
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	}, parent)
end

function Theme.MakeHeader(text, parent, size, pos)
	return Theme.Make("TextLabel", {
		Size = size or UDim2.new(1, 0, 0, 40),
		Position = pos or UDim2.new(0, 0, 0, 0),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = Theme.C.TextWhite,
		Font = Theme.F.Header,
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Left
	}, parent)
end

return Theme