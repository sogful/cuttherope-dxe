if not game:GetService("RunService"):IsStudio() then return end
local shared=game.ReplicatedStorage.CutTheRope.Shared
local Physics=require(shared.DxPhysics)
local Levels=require(shared.LevelData)
local results={}
for _,trace in ipairs(require(shared.DiscGoldenData)) do
	local physics=Physics.new(Levels.get(trace.level,11))
	local sampleIndex,actionIndex=1,1
	local r={id="11_"..trace.level,action=trace.action,candy=0,anchors=0,discs=0,bubbles=0,pumps=0,topology=0,ownership=0}
	for tick=1,trace.samples[#trace.samples][1] do
		local action=trace.actions[actionIndex]
		if action and action[1]==tick then
			physics.mechanics[action[2]](physics.mechanics,Vector2.new(action[3],action[4]))
			actionIndex+=1
		end
		physics:tick()
		local sample=trace.samples[sampleIndex]
		if sample and sample[1]==tick then
			local bodies=physics:activeBodies()
			if #bodies~=#sample[2] then r.topology+=1 end
			for i,b in ipairs(sample[2]) do if bodies[i] then
				local error=(bodies[i].pos-Vector2.new(b[1],b[2])).Magnitude
				if error>r.candy then r.candy,r.tick=error,tick end
				if (physics:hasBubble(bodies[i])==true)~=b[3] then r.ownership+=1 end
			end end
			for i,g in ipairs(sample[3]) do
				local rope=physics.ropes[i]
				r.anchors=math.max(r.anchors,(rope.anchor-Vector2.new(g[1],g[2])).Magnitude)
				if #sample[2]>0 and not rope.cut and #rope.bodies~=g[3] then r.topology+=1 end
			end
			for i,d in ipairs(sample[4]) do
				local actual=physics.mechanics.discs.objects[i]
				r.discs=math.max(r.discs,math.abs(actual.angle-d[1]),(actual.left-Vector2.new(d[2],d[3])).Magnitude,(actual.right-Vector2.new(d[4],d[5])).Magnitude)
			end
			for i,b in ipairs(sample[5]) do
				if not physics.usedBubbles[i] then r.bubbles=math.max(r.bubbles,(physics.bubbles[i]-Vector2.new(b[1],b[2])).Magnitude) end
			end
			for i,p in ipairs(sample[6]) do
				local actual=physics.mechanics.pumps[i]
				r.pumps=math.max(r.pumps,(actual.point-Vector2.new(p[1],p[2])).Magnitude,math.abs(actual.angle-p[3]))
			end
			sampleIndex+=1
		end
	end
	r.passed=r.candy<1 and r.anchors<.02 and r.discs<.02 and r.bubbles<.02 and r.pumps<.02 and r.topology==0 and r.ownership==0
	if not r.passed then warn("DX DISC DIFFERENTIAL",game.HttpService:JSONEncode(r)) end
	table.insert(results,r)
	task.wait()
end
local gui=game.Players.LocalPlayer.PlayerGui:WaitForChild("CutTheRopeGui")
gui:SetAttribute("DxDiscGoldenResults",game.HttpService:JSONEncode(results))
local passed=true
for _,r in ipairs(results) do if not r.passed then passed=false end end
gui:SetAttribute("DxDiscGoldenPassed",passed)
print("DX DISC GOLDEN",passed,#results)
