if not game:GetService("RunService"):IsStudio() then return end
local shared=game.ReplicatedStorage.CutTheRope.Shared
local results=require(shared.PillowGoldenRunner)(require(shared.PillowGoldenData))
local passed=true
for _,r in ipairs(results) do if not r.passed then passed=false warn("DX PILLOW DIFFERENTIAL",game.HttpService:JSONEncode(r)) end end
local gui=game.Players.LocalPlayer.PlayerGui:WaitForChild("CutTheRopeGui")
gui:SetAttribute("DxPillowGoldenResults",game.HttpService:JSONEncode(results))
gui:SetAttribute("DxPillowGoldenPassed",passed)
print("DX PILLOW GOLDEN",passed,#results)
