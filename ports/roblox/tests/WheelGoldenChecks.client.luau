if not game:GetService("RunService"):IsStudio() then return end
local shared=game.ReplicatedStorage.CutTheRope.Shared
local Physics=require(shared.DxPhysics)
local Levels=require(shared.LevelData)
local traces=require(shared.WheelGoldenData)
local results={}
for _,trace in ipairs(traces) do
	local level=Levels.get(trace.level,trace.pack)
	local physics=Physics.new(level)
	local wheel
	for _,rope in ipairs(physics.ropes) do if rope.wheel then wheel=rope.wheel break end end
	if trace.action=="wheel" and wheel then wheel:begin(wheel.rope.anchor+Vector2.new(90,0)) end
	local sampleIndex,actionIndex,maxError,maxTick,topologyErrors,bubbleErrors,restErrors=1,1,0,0,0,0,0
	local firstBad
	for tick=1,trace.samples[#trace.samples][1] do
		local action=trace.actions[actionIndex]
		if action and tick==action[1] then wheel:drag(Vector2.new(action[2],action[3])) actionIndex+=1 end
		if trace.action=="gravity" and (tick==31 or tick==85 or tick==120 or tick==125) then physics:toggleGravity() end
		physics:tick()
		local sample=trace.samples[sampleIndex]
		if sample and tick==sample[1] then
			if #sample[2]>0 then
				local bodies=physics:activeBodies()
				if #bodies~=#sample[2] then topologyErrors+=1 end
				for index,b in ipairs(sample[2]) do
					if bodies[index] then
						local error=(bodies[index].pos-Vector2.new(b[1],b[2])).Magnitude
						if error>maxError then maxError,maxTick=error,tick end
						if error>1 and not firstBad then firstBad=tick end
						if (physics:hasBubble(bodies[index])==true)~=b[3] then bubbleErrors+=1 end
					end
				end
				for index,reference in ipairs(sample[3]) do
					local rope=physics.ropes[index]
					if reference and not rope.cut then
						if #rope.bodies~=reference[1] then topologyErrors+=1 end
						if rope.tail then
							for _,link in ipairs(rope.tail.constraints) do
								if link.other==rope.bodies[#rope.bodies-1] and math.abs(link.length-reference[3])>.001 then restErrors+=1 end
							end
						end
					end
				end
			end
			sampleIndex+=1
		end
	end
	results[#results+1]={id=level.id,action=trace.action,maxError=maxError,tick=maxTick,firstBad=firstBad,topologyErrors=topologyErrors,bubbleErrors=bubbleErrors,restErrors=restErrors}
	task.wait()
end
local gui=game.Players.LocalPlayer.PlayerGui:WaitForChild("CutTheRopeGui")
gui:SetAttribute("DxWheelGoldenResults",game.HttpService:JSONEncode(results))
local passed=true
for _,r in ipairs(results) do if r.maxError>=1 or r.topologyErrors>0 or r.bubbleErrors>0 or r.restErrors>0 then passed=false warn("Wheel differential",r.id,r.action,r.maxError,r.topologyErrors,r.bubbleErrors,r.restErrors) end end
gui:SetAttribute("DxWheelGoldenPassed",passed)
print("DX WHEEL GOLDEN",passed,#results)
