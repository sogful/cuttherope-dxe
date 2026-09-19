local shared = game:GetService("ReplicatedStorage").CutTheRope.Shared
local Physics, Levels = require(shared.DxPhysics), require(shared.LevelData)
local result = Instance.new("Folder")
result.Name, result.Parent = "DxRadiusRouteProbe", game.Players.LocalPlayer.PlayerGui
local trials = 0
local solution
for firstDelay = 24, 100, 4 do
	for secondDelay = 12, 100, 4 do
		local simulation = Physics.new(Levels.get(10))
		for _ = 1, 60 do simulation:update(1 / 60) end
		simulation:sever(simulation.ropes[4], 1)
		local firstAt, secondAt
		for tick = 1, 420 do
			simulation:update(1 / 60)
			if simulation.ropes[1].captured and not firstAt then firstAt = tick end
			if simulation.ropes[3].captured and not secondAt then secondAt = tick end
			if firstAt and tick - firstAt >= firstDelay then simulation:sever(simulation.ropes[1], 1) end
			if secondAt and tick - secondAt >= secondDelay then simulation:sever(simulation.ropes[3], 1) end
			if simulation.ropes[2].captured then
				solution = {firstDelay = firstDelay / 60, secondDelay = secondDelay / 60, tick = tick}
				break
			end
			if simulation.candy.pos.Y > 1600 then break end
		end
		trials += 1
		if solution then break end
		if trials % 4 == 0 then task.wait() end
	end
	if solution then break end
end
result:SetAttribute("Trials", trials)
result:SetAttribute("CaughtAllThree", solution ~= nil)
if solution then
	result:SetAttribute("FirstCutDelay", solution.firstDelay)
	result:SetAttribute("SecondCutDelay", solution.secondDelay)
end
result:SetAttribute("Finished", true)
print("DX radius route search", trials, solution and game:GetService("HttpService"):JSONEncode(solution) or "No route found in sampled timings")
