-- Sequential runner: do not saturate the Studio client with concurrent suites.
if not game:GetService("RunService"):IsStudio() then return end
local p=game.Players.LocalPlayer
local gui=p.PlayerGui:WaitForChild("CutTheRopeGui")
local results={}
local jobs={
	{"DxBoxChecks","CutTheRopeGui","DxBoxChecks"},
	{"ViewportChecks","DxViewportChecks","Complete"},
	{"SimulationChecks","DxSimulationChecks","Complete"},
	{"DxPhysicsChecks","DxPhysicsChecks","Finished"},
	{"DxPresentationChecks","DxPresentationChecks","AllPassed"},
	{"DxBoxGoldenChecks","CutTheRopeGui","DxBoxGoldenPassed"},
	{"DxBoxMoverChecks","CutTheRopeGui","DxBoxMoversPassed"},
	{"DxSplitGoldenChecks","CutTheRopeGui","DxSplitGoldenPassed"},
	{"DxWheelGoldenChecks","CutTheRopeGui","DxWheelGoldenPassed"},
	{"DxAdvancedGoldenChecks","CutTheRopeGui","DxAdvancedGoldenPassed"},
	{"DiscGoldenChecks","CutTheRopeGui","DxDiscGoldenPassed"},
	{"GhostGoldenChecks","CutTheRopeGui","DxGhostGoldenPassed"},
	{"SteamGoldenChecks","CutTheRopeGui","DxSteamGoldenPassed"},
	{"LanternGoldenChecks","CutTheRopeGui","DxLanternGoldenPassed"},
	{"CheeseGoldenChecks","CutTheRopeGui","DxCheeseGoldenPassed"},
	{"PillowGoldenChecks","CutTheRopeGui","DxPillowGoldenPassed"},
}
for index,j in ipairs(jobs) do
	if index<(script:GetAttribute("StartAt") or 1) then continue end
	gui:SetAttribute("RegressionJob",j[1])
	local runner=assert(p.PlayerScripts:WaitForChild(j[1],10),"Missing regression script "..j[1])
	runner.Enabled=true
	local start=os.clock()
	local value
	repeat
		task.wait(.1)
		local target=p.PlayerGui:FindFirstChild(j[2])
		value=target and target:GetAttribute(j[3])
	until value~=nil or os.clock()-start>180
	results[j[1]]=value==nil and "TIMEOUT" or value
	runner.Enabled=false
	gui:SetAttribute("RegressionProgress",game.HttpService:JSONEncode(results))
	task.wait(.1)
end
gui:SetAttribute("RegressionJob","Finished")
gui:SetAttribute("RegressionFinished",true)
print("DX CLASSIC REGRESSION FINISHED",game.HttpService:JSONEncode(results))
