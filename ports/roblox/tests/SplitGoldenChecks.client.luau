local shared=game.ReplicatedStorage.CutTheRope.Shared
local Physics=require(shared.DxPhysics)
local Levels=require(shared.LevelData)
local traces=require(shared.SplitGoldenData)
local results={}
local detailed={}
for _,trace in ipairs(traces) do
	local level=Levels.get(trace.level,trace.pack)
	local physics=Physics.new(level)
	local sampleIndex,maxError,maxTick,firstBad=1,0,0,nil
	local topologyErrors,bubbleErrors=0,0
	local detail={}
	for tick=1,trace.samples[#trace.samples][1] do
		if trace.action=="merge" and tick==61 then physics:sever(physics.ropes[2],1) physics:sever(physics.ropes[3],1) end
		if trace.action=="merge" and tick==181 then physics:sever(physics.ropes[1],1) physics:sever(physics.ropes[4],1) end
		if trace.action=="bounce" and tick==61 then physics:sever(physics.ropes[1],1) end
		physics:tick()
		local sample=trace.samples[sampleIndex]
		if sample and tick==sample[1] then
			if #sample[4]>0 then
				local bodies=physics:activeBodies()
				if trace.action~="idle" then
					local values={tick=tick,bodies={},split=physics.split~=nil}
					for _,b in ipairs(bodies) do table.insert(values.bodies,{b.pos.X,b.pos.Y}) end
					table.insert(detail,values)
				end
				if (physics.split~=nil)~=sample[2] or #bodies~=#sample[4] then topologyErrors+=1 end
				for index,b in ipairs(sample[4]) do
					if bodies[index] then
						local error=(bodies[index].pos-Vector2.new(b[1],b[2])).Magnitude
						if error>maxError then maxError,maxTick=error,tick end
						if error>.5 and not firstBad then firstBad=tick end
						if (physics:hasBubble(bodies[index])==true)~=b[3] then bubbleErrors+=1 end
					end
				end
			end
			sampleIndex+=1
		end
	end
	results[#results+1]={id=level.id,action=trace.action,maxError=maxError,tick=maxTick,firstBad=firstBad,topologyErrors=topologyErrors,bubbleErrors=bubbleErrors}
	if #detail>0 then detailed[level.id..trace.action]=detail end
	task.wait()
end
local gui=game.Players.LocalPlayer.PlayerGui.CutTheRopeGui
gui:SetAttribute("DxSplitGoldenResults",game.HttpService:JSONEncode(results))
gui:SetAttribute("DxSplitGoldenDetails",game.HttpService:JSONEncode(detailed))
for _,result in ipairs(results) do assert(result.maxError<1 and result.topologyErrors==0 and result.bubbleErrors==0,"C# differential regression: "..result.id.." "..result.action) end
gui:SetAttribute("DxSplitGoldenPassed",true)
print("DX SPLIT GOLDEN PASS",#results)
