-- @ScriptType: LocalScript
-- @ScriptType: LocalScript
-- Place in: StarterPlayerScripts > AOT_Client > Client_Core

local Players = game:GetService("Players")
local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

if PlayerGui:FindFirstChild("AOT_MainHUD") then PlayerGui.AOT_MainHUD:Destroy() end

local MainHUD = Instance.new("ScreenGui")
MainHUD.Name = "AOT_MainHUD"
MainHUD.ResetOnSpawn = false
MainHUD.IgnoreGuiInset = true
MainHUD.ZIndexBehavior = Enum.ZIndexBehavior.Sibling -- [FIX] Forces children to render on top of backgrounds!
MainHUD.Parent = PlayerGui

print("[Client_Core] Loading modules...")
local Theme = require(script.Parent:WaitForChild("UI_Theme"))
local MainMenu = require(script.Parent:WaitForChild("UI_MainMenu"))
local HUD = require(script.Parent:WaitForChild("UI_HUD"))

print("[Client_Core] Building Main Menu...")
local MenuScreen = MainMenu.Build(MainHUD, function()
	print("[Client_Core] Deploy clicked! Building HUD...")
	HUD.Build(MainHUD)
end)

print("[AOT_Client] Core initialized successfully.")