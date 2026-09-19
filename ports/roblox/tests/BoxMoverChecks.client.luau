local shared=game.ReplicatedStorage.CutTheRope.Shared
local Physics,Levels=require(shared.DxPhysics),require(shared.LevelData)
local traces=require(shared.BoxMoverGoldenData)
local results={}
for _,trace in ipairs(traces) do
	local physics=Physics.new(Levels.get(trace.level,trace.pack))
	local mover=trace.kind=="star" and physics.starMovers[trace.index]
		or trace.kind=="spike" and physics.hazards.objects[trace.index].mover
		or trace.kind=="sock" and physics.mechanics.hats[trace.index].mover
	assert(mover,"Missing authored mover")
	local sampleIndex,maxPosition,maxAngle,targetErrors=1,0,0,0
	for tick=1,600 do
		mover:update(.016)
		local sample=trace.samples[sampleIndex]
		if sample and sample[1]==tick then
			maxPosition=math.max(maxPosition,(mover.pos-Vector2.new(sample[2],sample[3])).Magnitude)
			maxAngle=math.max(maxAngle,math.abs(mover.angle-sample[4]))
			if mover.target~=sample[5] then targetErrors+=1 end
			sampleIndex+=1
		end
	end
	results[#results+1]={id=trace.pack.."_"..trace.level,kind=trace.kind,index=trace.index,maxPosition=maxPosition,maxAngle=maxAngle,targetErrors=targetErrors}
	task.wait()
end
game.Players.LocalPlayer.PlayerGui.CutTheRopeGui:SetAttribute("DxBoxMoverResults",game.HttpService:JSONEncode(results))
for _,result in ipairs(results) do assert(result.maxPosition<.01 and result.maxAngle<.01 and result.targetErrors==0,"C# mover regression: "..result.id) end
game.Players.LocalPlayer.PlayerGui.CutTheRopeGui:SetAttribute("DxBoxMoversPassed",true)
print("DX BOX MOVERS",game.HttpService:JSONEncode(results))
