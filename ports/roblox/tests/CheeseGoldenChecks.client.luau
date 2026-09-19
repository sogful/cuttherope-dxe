if not game:GetService("RunService"):IsStudio() then return end
local shared=game.ReplicatedStorage.CutTheRope.Shared
local results=require(shared.CheeseGoldenRunner)(require(shared.CheeseGoldenData))
local passed=true
for _,r in ipairs(results) do
	if not r.passed then passed=false warn("DX CHEESE DIFFERENTIAL",game.HttpService:JSONEncode(r)) end
end
local gui=game.Players.LocalPlayer.PlayerGui:WaitForChild("CutTheRopeGui")
gui:SetAttribute("DxCheeseGoldenResults",game.HttpService:JSONEncode(results))
gui:SetAttribute("DxCheeseGoldenPassed",passed)
print("DX CHEESE GOLDEN",passed,#results)
