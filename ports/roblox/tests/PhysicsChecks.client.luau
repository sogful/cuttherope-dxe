local RunService = game:GetService("RunService")
if not RunService:IsStudio() then return end
local shared = game:GetService("ReplicatedStorage").CutTheRope.Shared
local Physics, Levels = require(shared.DxPhysics), require(shared.LevelData)
local results = Instance.new("Folder")
results.Name, results.Parent = "DxPhysicsChecks", game.Players.LocalPlayer.PlayerGui
local function check(name, callback)
	local ok, message = pcall(callback)
	results:SetAttribute(name, ok and "passed" or tostring(message))
	if not ok then warn("DX check failed:", name, message) end
	task.wait()
end
local function finite(point)
	return point.X == point.X and point.Y == point.Y and math.abs(point.X) < 1e6 and math.abs(point.Y) < 1e6
end
check("AllTwentyFiveMaps", function()
	assert(#Levels.list == 25)
	for _, level in ipairs(Levels.list) do
		task.wait()
		local simulation = Physics.new(level)
		for _ = 1, 180 do simulation:update(1 / 60) end
		assert(finite(simulation.candy.pos), level.id)
		for index, rope in ipairs(simulation.ropes) do
			if rope.active and not simulation.retired then
				assert(rope.bodies[#rope.bodies] == simulation.candy, "Endpoint is not shared")
				assert((rope.bodies[1].pos - level.ropes[index].anchor).Magnitude < .001, "Anchor drift")
			elseif not rope.active then assert(#rope.bodies == 0 and not rope.captured) end
		end
	end
end)
check("RadiusCatchBoundary", function()
	local definition = { anchor = Vector2.new(1000, 500), length = 999, radius = 135 }
	local simulation = Physics.new({ candyStart = Vector2.new(1177.01, 500), ropes = {definition} })
	local rope = simulation.ropes[1]
	assert(not rope.active and #simulation.candy.constraints == 0)
	simulation:tick()
	assert(not rope.active, "Caught outside radius+42")
	simulation.candy.pos, simulation.candy.previous = Vector2.new(1177, 500), Vector2.new(1177, 500)
	simulation:update(1 / 60)
	assert(rope.active and rope.captured, "Did not catch on boundary")
	assert(rope.length == 177, "Used authored rope length instead of radius+padding")
	assert(rope.bodies[#rope.bodies] == simulation.candy)
	local rest = 0
	for _, body in ipairs(rope.bodies) do for _, constraint in ipairs(body.constraints) do rest += constraint.length end end
	assert(rest == 282, "Missing initial source 105-unit constraint")
	assert(simulation:sever(rope, 1))
	for _ = 1, 90 do
		simulation.candy.pos, simulation.candy.previous = definition.anchor, definition.anchor
		simulation:update(1 / 60)
	end
	assert(rope.cut and #simulation.ropes == 1, "Hook caught again after cutting")
	assert(rope.radiusAlpha == 0, "Radius did not fade at1.5/sec")
end)
check("RadiusRetirement", function()
	local simulation = Physics.new(Levels.get(10))
	assert(not simulation.ropes[1].active and simulation.ropes[4].active)
	simulation:retireCandy()
	simulation.candy.pos = simulation.ropes[1].definition.anchor
	for _ = 1, 120 do simulation:update(1 / 60) end
	assert(not simulation.ropes[1].captured, "Retired candy was caught")
	assert(simulation.ropes[4].cut)
end)
check("RadiusFrameRateIndependent", function()
	local a, b = Physics.new(Levels.get(10)), Physics.new(Levels.get(10))
	a:sever(a.ropes[4], 1)
	b:sever(b.ropes[4], 1)
	for _ = 1, 180 do a:update(1 / 60) end
	for _ = 1, 90 do b:update(1 / 30) end
	assert(a.ropes[1].captured and b.ropes[1].captured, "First authored auto-hook never caught")
	assert((a.candy.pos - b.candy.pos).Magnitude < .001)
end)
check("AuthoredThreeHookRoute", function()
	local simulation = Physics.new(Levels.get(10))
	for _ = 1, 60 do simulation:update(1 / 60) end
	simulation:sever(simulation.ropes[4], 1)
	local firstAt, secondAt
	for tick = 1, 240 do
		simulation:update(1 / 60)
		if simulation.ropes[1].captured and not firstAt then firstAt = tick end
		if simulation.ropes[3].captured and not secondAt then secondAt = tick end
		if firstAt and tick - firstAt >= 51 then simulation:sever(simulation.ropes[1], 1) end
		if secondAt and tick - secondAt >= 30 then simulation:sever(simulation.ropes[3], 1) end
	end
	assert(simulation.ropes[1].captured and simulation.ropes[3].captured and simulation.ropes[2].captured)
end)
check("FrameRateIndependent", function()
	local a, b = Physics.new(Levels.get(2)), Physics.new(Levels.get(2))
	for _ = 1, 180 do a:update(1 / 60) end
	for _ = 1, 90 do b:update(1 / 30) end
	assert((a.candy.pos - b.candy.pos).Magnitude < .001)
end)
check("LevelOneSettles", function()
	local simulation = Physics.new(Levels.get(1))
	for _ = 1, 240 do simulation:update(1 / 60) end
	assert(math.abs(simulation.candy.pos.Y - 510) < 8, tostring(simulation.candy.pos))
end)
check("IndependentCuts", function()
	local simulation = Physics.new(Levels.get(2))
	assert(simulation:sever(simulation.ropes[1], 1))
	assert(not simulation.ropes[2].cut and not simulation.ropes[3].cut)
	assert(not simulation:sever(simulation.ropes[1], 1))
	for _ = 1, 120 do simulation:update(1 / 60) end
	assert(finite(simulation.candy.pos))
end)
check("BubbleLiftAndPop", function()
	local simulation = Physics.new({ candyStart = Vector2.new(1280, 900), ropes = {} })
	simulation.bubble = true
	for _ = 1, 90 do simulation:update(1 / 60) end
	local raised = simulation.candy.pos.Y
	assert(raised < 800, "Bubble did not raise candy")
	simulation.bubble = false
	for _ = 1, 180 do simulation:update(1 / 60) end
	assert(simulation.candy.pos.Y > raised, "Candy did not fall after pop")
end)
check("LevelSevenThreeStars", function()
	local simulation = Physics.new(Levels.get(7))
	local collected, count = {}, 0
	for tick = 1, 360 do
		if tick == 61 then for _, index in ipairs({1, 3, 4}) do simulation:sever(simulation.ropes[index], 1) end end
		if tick == 96 then for _, index in ipairs({2, 6}) do simulation:sever(simulation.ropes[index], 1) end end
		simulation:update(1/60)
		for index, star in ipairs(Levels.get(7).stars) do
			local d = simulation.candy.pos - star
			if not collected[index] and math.abs(d.X) < 97 and math.abs(d.Y) < 93 then collected[index], count = true, count + 1 end
		end
	end
	assert(count == 3, "Six-rope route could not reach all three stars")
end)
check("LevelFifteenBubbleRoute", function()
	local level = Levels.get(15)
	local simulation = Physics.new(level)
	local cuts = {[61]=1, [661]=2, [1261]=3, [1861]=5, [2461]=4}
	local collected, count, reachedMouth = {}, 0, false
	for tick = 1, 2820 do
		if cuts[tick] then assert(simulation:sever(simulation.ropes[cuts[tick]], 1)) end
		simulation:update(1/60)
		for index, star in ipairs(level.stars) do
			local d = simulation.candy.pos - star
			if not collected[index] and math.abs(d.X) < 97 and math.abs(d.Y) < 93 then collected[index], count = true, count + 1 end
		end
		local d = simulation.candy.pos - level.target
		if count == 3 and d.X > -113.5 and d.X < 106.5 and d.Y > -22 and d.Y < 84 then reachedMouth = true break end
	end
	assert(simulation.bubble, "Authored bubble was not captured")
	for _, rope in ipairs(simulation.ropes) do assert(rope.captured, "Missed an authored auto-hook") end
	assert(count == 3 and reachedMouth, "Tall-map route did not reach all three stars and the mouth")
end)
check("DesktopGoldenTrajectories", function()
	local maxError = 0
	for level, samples in pairs(require(shared.DesktopTrajectories)) do
		local sim = Physics.new(Levels.get(level))
		local index = 1
		for tick = 1, 120 do
			if tick == 61 and level == 6 then sim:sever(sim.ropes[1], 1) end
			sim:update(1/60)
			local sample = samples[index]
			if sample and tick == sample[1] then
				local error = (sim.candy.pos - Vector2.new(sample[2], sample[3])).Magnitude
				maxError = math.max(maxError, error)
				results:SetAttribute("Golden" .. level .. "Tick" .. tick, error)
				index += 1
			end
		end
	end
	results:SetAttribute("GoldenMaxError", maxError)
	assert(maxError < 2, "DX trajectory drift: " .. maxError)
end)
results:SetAttribute("Finished", true)
print("DX physics checks finished")
