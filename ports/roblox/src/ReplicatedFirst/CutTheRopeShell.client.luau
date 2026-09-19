local players = game:GetService("Players")
local starter = game:GetService("StarterGui")
local player = players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name, gui.IgnoreGuiInset, gui.ResetOnSpawn = "CutTheRopeBlackBacking", true, false
gui.DisplayOrder, gui.ZIndexBehavior = -100, Enum.ZIndexBehavior.Sibling
gui.ClipToDeviceSafeArea = false
local black = Instance.new("Frame")
black.Name, black.Size = "Black", UDim2.fromScale(1,1)
black.BackgroundColor3, black.BorderSizePixel = Color3.new(0,0,0), 0
black.Parent = gui
gui.Parent = player:WaitForChild("PlayerGui")

local function camera()
	local current = workspace.CurrentCamera
	if current then
		current.CameraType = Enum.CameraType.Scriptable
		current.CameraSubject = nil
		current.CFrame = CFrame.new(0,1000,0)
	end
end
camera()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(camera)

task.spawn(function()
	local scripts = player:WaitForChild("PlayerScripts")
	local module = scripts:WaitForChild("PlayerModule")
	local controls = require(module):GetControls()
	controls:Disable()
	gui:SetAttribute("CharacterControlsDisabled",true)
end)
task.spawn(function()
	-- SetCore is only available once Roblox's own GUI scripts have registered it.
	for _=1,30 do
		if pcall(function() starter:SetCore("ResetButtonCallback",false) end) then
			gui:SetAttribute("AvatarResetDisabled",true)
			return
		end
		task.wait(.25)
	end
end)
