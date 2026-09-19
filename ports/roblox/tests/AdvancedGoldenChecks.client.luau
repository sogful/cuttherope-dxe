if not game:GetService("RunService"):IsStudio() then return end
local shared=game.ReplicatedStorage.CutTheRope.Shared
local Physics=require(shared.DxPhysics)
local Levels=require(shared.LevelData)
local traces=require(shared.AdvancedGoldenData)
local results={}
for _,trace in ipairs(traces) do
	local physics=Physics.new(Levels.get(trace.level,trace.pack))
	local sampleIndex=1
	local result={id=trace.pack.."_"..trace.level,action=trace.action,maxError=0,anchorError=0,spikeError=0,topologyErrors=0,bubbleErrors=0}
	for tick=1,trace.samples[#trace.samples][1] do
		if trace.action=="rotate" then
			if tick==10 or tick==16 or tick==60 or tick==90 or tick==150 then physics.hazards:rotateGroup(1) end
			if tick==40 or tick==80 then physics.hazards:rotateGroup(2) end
		end
		physics:tick()
		local sample=trace.samples[sampleIndex]
		if sample and sample[1]==tick then
			local bodies=physics:activeBodies()
			if #sample[2]~=#bodies then result.topologyErrors+=1 end
			for i,b in ipairs(sample[2]) do
				if bodies[i] then
					local error=(bodies[i].pos-Vector2.new(b[1],b[2])).Magnitude
					if error>result.maxError then result.maxError,result.tick=error,tick end
					if (physics:hasBubble(bodies[i])==true)~=b[3] then result.bubbleErrors+=1 end
				end
			end
			for i,g in ipairs(sample[3]) do
				local rope=physics.ropes[i]
				result.anchorError=math.max(result.anchorError,(rope.anchor-Vector2.new(g[1],g[2])).Magnitude)
				if #sample[2]>0 and not rope.cut and #rope.bodies~=g[3] then result.topologyErrors+=1 end
			end
			for i,s in ipairs(sample[4]) do
				local spike=physics.hazards.objects[i]
				result.spikeError=math.max(result.spikeError,math.abs(spike.angle-s[3]),(spike.point-Vector2.new(s[1],s[2])).Magnitude)
			end
			sampleIndex+=1
		end
	end
	table.insert(results,result)
	task.wait()
end
local gui=game.Players.LocalPlayer.PlayerGui:WaitForChild("CutTheRopeGui")
gui:SetAttribute("DxAdvancedGoldenResults",game.HttpService:JSONEncode(results))
local passed=true
for _,r in ipairs(results) do
	if r.maxError>=1 or r.anchorError>.02 or r.spikeError>.02 or r.topologyErrors>0 or r.bubbleErrors>0 then
		passed=false warn("Advanced differential",r.id,r.action,r.maxError,r.anchorError,r.spikeError,r.topologyErrors,r.bubbleErrors)
	end
end
gui:SetAttribute("DxAdvancedGoldenPassed",passed)
print("DX ADVANCED GOLDEN",passed,#results)
