local shared=game.ReplicatedStorage.CutTheRope.Shared
local Mover,Levels,Physics=require(shared.PathMover),require(shared.LevelData),require(shared.DxPhysics)
local Runtime=require(shared.LevelRuntime)
local gui=Instance.new("ScreenGui")
gui.Name,gui.Enabled,gui.Parent="DxMoverChecks",false,game.Players.LocalPlayer.PlayerGui
local maximum=0
for _,run in ipairs(require(shared.DesktopMoverTraces)) do
	local level=Levels.get(run.level)
	local origin,definition
	if run.kind=="star" then origin,definition=level.stars[run.index],level.starMotion[run.index]
	else definition=level.spikes[run.index] origin=definition.point end
	local mover=Mover.new(origin,definition.movement,definition.angle)
	local index=1
	for tick=0,600 do
		if tick>0 then mover:update(.016) end
		local sample=run.samples[index]
		if sample and sample.tick==tick then
			local error=(mover.pos-Vector2.new(sample.x,sample.y)).Magnitude
			maximum=math.max(maximum,error)
			assert(error<.05,"Mover drift "..run.level..":"..tick.."="..error)
			assert(mover.target==sample.target and math.abs(mover.angle-sample.angle)<.001)
			index+=1
		end
	end
	assert(index==#run.samples+1)
end
gui:SetAttribute("GoldenMaxError",maximum)
local candyMaximum=0
for _,run in ipairs(require(shared.DesktopCardboardTraces)) do
	local sim=Physics.new(Levels.get(run.level))
	local index=1
	local mapMaximum=0
	for tick=1,120 do
		sim:update(1/60)
		local sample=run.samples[index]
		if sample and sample.tick==tick then
			local error=(sim.candy.pos-Vector2.new(sample.x,sample.y)).Magnitude
			candyMaximum=math.max(candyMaximum,error)
			mapMaximum=math.max(mapMaximum,error)
			assert(error<2,"New map candy drift "..run.level..":"..tick.."="..error)
			index+=1
		end
	end
	gui:SetAttribute("CandyMap"..run.level.."MaxError",mapMaximum)
end
gui:SetAttribute("CardboardCandyMaxError",candyMaximum)
local m=Mover.new(Vector2.zero,{offsets={Vector2.zero,Vector2.new(10,0)},speed=20,rotateSpeed=90},5)
m:update(1.25)
assert((m.pos-Vector2.new(5,0)).Magnitude<.0001 and m.angle==117.5)
m.paused=true m:update(10) assert(m.angle==117.5 and m.pos.X==5)
m.paused=false m.reverse=true m:update(.25) assert(m.pos==Vector2.new(10,0))
local stalled=Mover.new(Vector2.zero,{offsets={Vector2.zero},speed=20})
stalled:update(.016) assert(stalled.pos==Vector2.zero and stalled.overrun==.016)
gui:SetAttribute("TraversalEdges",true)
for _,number in ipairs({22,24}) do
	local a,b=Physics.new(Levels.get(number)),Physics.new(Levels.get(number))
	for _=1,600 do a:update(1/60) end
	for _=1,300 do b:update(1/30) end
	for index,position in ipairs(a.starPositions) do assert((position-b.starPositions[index]).Magnitude<.001) end
	for index,object in ipairs(a.hazards.objects) do assert((object.point-b.hazards.objects[index].point).Magnitude<.001) end
end
gui:SetAttribute("FrameRateIndependent",true)
local parent=Instance.new("Frame") parent.Size,parent.Parent=UDim2.fromOffset(1120,630),gui
local runtime=Runtime.new(parent,Levels.get(24))
for _=1,60 do runtime:update(1/60) end
local star=runtime.stars[1]
assert(star.point.Y>Levels.get(24).stars[1].Y+100,"Authored moving star stayed still")
assert(math.abs(star.container.Position.Y.Scale*1440-star.point.Y)<.001)
-- Isolate collection at the mover's current point, outside the original static box.
runtime.physics:retireCandy()
runtime.physics.candy.pos=star.point
runtime:update(1/60)
assert(star.collected,"Moving star collision used authored point instead of current position")
parent:Destroy()
parent=Instance.new("Frame") parent.Size,parent.Parent=UDim2.fromOffset(1120,630),gui
runtime=Runtime.new(parent,Levels.get(22))
for _=1,60 do runtime:update(1/60) end
for index,spike in ipairs(runtime.spikes) do
	local object=runtime.physics.hazards.objects[index]
	assert((object.point-Levels.get(22).spikes[index].point).Magnitude>90)
	assert(math.abs(spike.Position.X.Scale*2560-object.point.X)<.001)
	local bar=runtime.physics.hazards.bars[index]
	assert(((bar[1]+bar[4])*.5-object.point).Magnitude<.001)
end
parent:Destroy()
gui:SetAttribute("LiveGeometryAndCollection",true)
gui:SetAttribute("Passed",true)
print("DX MOVER CHECKS PASS: original C# paths, turns, pause/reverse, 30/60Hz, spike geometry, moving-star collection")
