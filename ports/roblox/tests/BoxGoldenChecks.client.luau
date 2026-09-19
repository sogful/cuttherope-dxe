local shared=game.ReplicatedStorage.CutTheRope.Shared
local Physics=require(shared.DxPhysics)
local Levels=require(shared.LevelData)
local traces=require(shared.BoxGoldenData)
local results={}
for _,trace in ipairs(traces) do
	local level=Levels.get(trace.level,trace.pack)
	local physics=Physics.new(level)
	local sampleIndex,maxError,maxTick,firstBad=1,0,0,nil
	local quadErrors=0
	for tick=1,trace.samples[#trace.samples][1] do
		if trace.action=="pump" and (tick==61 or tick==121) then physics.mechanics:press(physics.mechanics.pumps[1].point) end
		if trace.action=="rail" and tick>=61 and tick<=120 then
			local rope=physics.ropes[1]
			physics.mechanics:press(rope.anchor)
			physics.mechanics:drag(rope.definition.anchor+Vector2.new((tick-60)*10,0))
		end
		if trace.action=="hat" and tick==61 then physics:sever(physics.ropes[1],1) end
		physics:tick()
		local sample=trace.samples[sampleIndex]
		if sample and tick==sample[1] then
			if not sample[4] then
				local error=(physics.candy.pos-Vector2.new(sample[2],sample[3])).Magnitude
				if error>maxError then maxError,maxTick=error,tick end
				if error>.5 and not firstBad then firstBad=tick end
			end
			local n=0
			for index=1,#physics.ropes do
				local spider=physics.mechanics.spiders[index]
				if spider then n+=1 if sample[5][n]~=spider.quad then quadErrors+=1 end end
			end
			sampleIndex+=1
		end
	end
	results[#results+1]={id=level.id,action=trace.action,maxError=maxError,tick=maxTick,firstBad=firstBad,quadErrors=quadErrors}
	task.wait()
end
local gui=game.Players.LocalPlayer.PlayerGui.CutTheRopeGui
gui:SetAttribute("DxBoxGoldenResults",game.HttpService:JSONEncode(results))
for _,result in ipairs(results) do assert(result.maxError<1 and result.quadErrors==0,"C# differential regression: "..result.id.." "..result.action) end
gui:SetAttribute("DxBoxGoldenPassed",true)
print("DX BOX GOLDEN",game.HttpService:JSONEncode(results))
