if not game:GetService("RunService"):IsStudio() then return end
local shared=game.ReplicatedStorage.CutTheRope.Shared
local results=require(shared.LanternGoldenRunner)(require(shared.LanternGoldenData))
local passed=true
for _,r in ipairs(results) do
	if not r.passed then passed=false warn("DX LANTERN DIFFERENTIAL",game.HttpService:JSONEncode(r)) end
end
local gui=game.Players.LocalPlayer.PlayerGui:WaitForChild("CutTheRopeGui")
gui:SetAttribute("DxLanternGoldenResults",game.HttpService:JSONEncode(results))
gui:SetAttribute("DxLanternGoldenPassed",passed)
print("DX LANTERN GOLDEN",passed,#results)
