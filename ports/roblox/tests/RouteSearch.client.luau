local shared = game.ReplicatedStorage.CutTheRope.Shared
local Physics, Levels = require(shared.DxPhysics), require(shared.LevelData)
local result = Instance.new("Folder")
result.Name, result.Parent = "DxRouteSearch", game.Players.LocalPlayer.PlayerGui
local found
for delay = 1, 120 do
	local sim = Physics.new(Levels.get(7))
	local stars, count = {}, 0
	for tick = 1, 360 do
		if tick == 61 then for _, i in ipairs({1,3,4}) do sim:sever(sim.ropes[i], 1) end end
		if tick == 61 + delay then for _, i in ipairs({2,6}) do sim:sever(sim.ropes[i], 1) end end
		sim:update(1/60)
		for index, star in ipairs(Levels.get(7).stars) do
			local d = sim.candy.pos - star
			if not stars[index] and math.abs(d.X) < 97 and math.abs(d.Y) < 93 then stars[index], count = true, count+1 end
		end
		if count == 3 then found = delay break end
	end
	if found then break end
	if delay % 5 == 0 then task.wait() end
end
result:SetAttribute("Level7CutDelay", found or -1)
local route
for delay1 = 30, 75, 3 do
	for delay2 = 8, 42, 2 do
		local sim = Physics.new(Levels.get(10))
		for _ = 1,60 do sim:update(1/60) end
		sim:sever(sim.ropes[4],1)
		local first, second
		for tick=1,240 do
			sim:update(1/60)
			if sim.ropes[1].captured and not first then first=tick end
			if sim.ropes[3].captured and not second then second=tick end
			if first and tick-first>=delay1 then sim:sever(sim.ropes[1],1) end
			if second and tick-second>=delay2 then sim:sever(sim.ropes[3],1) end
		end
		if sim.ropes[2].captured and sim.ropes[3].captured then route={delay1,delay2} break end
	end
	if route then break end
	task.wait()
end
result:SetAttribute("Level10First", route and route[1] or -1)
result:SetAttribute("Level10Second", route and route[2] or -1)
result:SetAttribute("Finished", true)
