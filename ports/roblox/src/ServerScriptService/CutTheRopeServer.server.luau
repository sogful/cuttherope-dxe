local players = game:GetService("Players")

-- This experience runs in ScreenGuis; no 3D avatar is part of its game state.
players.CharacterAutoLoads = false
local function removeCharacter(character)
	character:Destroy()
end
local function joined(player)
	player.DevComputerMovementMode = Enum.DevComputerMovementMode.Scriptable
	player.DevTouchMovementMode = Enum.DevTouchMovementMode.Scriptable
	player.CharacterAdded:Connect(removeCharacter)
	if player.Character then removeCharacter(player.Character) end
end
players.PlayerAdded:Connect(joined)
for _, player in ipairs(players:GetPlayers()) do joined(player) end
