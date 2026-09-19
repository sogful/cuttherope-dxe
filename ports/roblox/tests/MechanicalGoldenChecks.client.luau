if not game:GetService("RunService"):IsStudio() then return end
local shared=game.ReplicatedStorage.CutTheRope.Shared
local results=require(shared.MechanicalGoldenRunner)(require(shared.MechanicalGoldenData))
local passed=true
for _,r in ipairs(results) do if not r.passed then passed=false warn("DX MECHANICAL DIFFERENTIAL",game.HttpService:JSONEncode(r)) end end
local gui=game.Players.LocalPlayer.PlayerGui:WaitForChild("CutTheRopeGui")
gui:SetAttribute("DxMechanicalGoldenResults",game.HttpService:JSONEncode(results))
gui:SetAttribute("DxMechanicalGoldenPassed",passed)
print("DX MECHANICAL GOLDEN",passed,#results)
