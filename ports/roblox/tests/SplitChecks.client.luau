local shared=game.ReplicatedStorage.CutTheRope.Shared
local Physics=require(shared.DxPhysics)
local Runtime=require(shared.LevelRuntime)
local Levels=require(shared.LevelData)
local Frames=require(shared.SplitFrames)
local Bouncers=require(shared.BouncerMechanics)
local results={}
local function check(name,callback)
	local ok,message=pcall(callback)
	results[name]=ok and "PASS" or tostring(message)
	if not ok then warn("DX SPLIT CHECK",name,message) end
end
local function fixture(left,right)
	return {id="split-test",pack=5,candyStart=left,halves={left,right},target=Vector2.new(1800,1200),
		ropes={},stars={},bubbles={},spikes={},pumps={},socks={},bouncers={}}
end
local root=Instance.new("ScreenGui")
root.Name,root.Enabled,root.Parent="DxSplitChecks",false,game.Players.LocalPlayer.PlayerGui
local function runtime(level)
	local layer=Instance.new("Frame")
	layer.Size,layer.Parent=UDim2.fromOffset(1120,630),root
	return Runtime.new(layer,level),layer
end
check("All52AuthoredCandyHalves",function()
	for skin=0,51 do
		local quads=Frames["half"..skin]
		assert(#quads==2)
		for _,q in ipairs(quads) do assert(Frames.pages[q[1]] and q[4]>0 and q[5]>0 and q[8]>=q[4] and q[9]>=q[5]) end
	end
end)
check("IndependentBubbleCaptureAndPop",function()
	local level=fixture(Vector2.new(800,400),Vector2.new(1500,400))
	level.bubbles={level.halves[1],level.halves[2]}
	local r,layer=runtime(level)
	r:update(1/60)
	assert(r.physics.split[1].bubble and not r.physics.split[2].bubble)
	r:update(1/60)
	assert(r.physics.split[2].bubble)
	for i=1,2 do
		local p=r.physics.split[i].pos
		assert((r.bubbles[i].visual.Position.X.Scale-p.X/2560)^2<1e-10)
	end
	assert(r:pop(r.physics.split[1].pos))
	assert(not r.physics.split[1].bubble and r.physics.split[2].bubble)
	assert(r:pop(r.physics.split[2].pos))
	assert(not r:pop(r.physics.split[2].pos))
	layer:Destroy()
end)
check("BubbleTransferOnMerge",function()
	local level=fixture(Vector2.new(1000,400),Vector2.new(1060,400))
	level.bubbles={Vector2.new(1000,400)}
	local r,layer=runtime(level)
	for _=1,30 do r:update(1/60) end
	assert(not r.physics.split and r.physics.merged and r.physics.bubble)
	assert(r.bubbles[1].body==r.physics.candy and r.attached==r.bubbles[1])
	assert(r.candy.Visible and not r.halves[1].frame.Visible and not r.halves[2].frame.Visible)
	assert(r:pop(r.physics.candy.pos) and not r.physics.bubble)
	layer:Destroy()
end)
check("MergeRoutePreservesRopesAndWins",function()
	local r,layer=runtime(Levels.get(1,5))
	for tick=1,280 do
		if tick==61 then r.physics:sever(r.physics.ropes[2],1) r.physics:sever(r.physics.ropes[3],1) end
		if tick==170 then
			assert(r.physics.merged and not r.physics.split)
			assert(r.physics.ropes[1].tail==r.physics.candy and r.physics.ropes[4].tail==r.physics.candy)
		end
		if tick==181 then r.physics:sever(r.physics.ropes[1],1) r.physics:sever(r.physics.ropes[4],1) end
		r:update(1/60)
	end
	assert(r.state=="won" and r.count==3,r.state.." stars="..r.count)
	layer:Destroy()
end)
check("HazardRetiresOnlyHitHalf",function()
	local level=fixture(Vector2.new(800,400),Vector2.new(1500,400))
	level.spikes={{point=level.halves[1],size=1,angle=0}}
	local r,layer=runtime(level)
	for _=1,25 do r:update(1/60) end
	assert(r.state=="failed" and r.physics.split[1].removed and not r.physics.split[2].removed)
	assert(not r.halves[1].frame.Visible and r.halves[2].frame.Visible and not r.candy.Visible)
	assert(r.physics.split[2].pos.Y>400)
	layer:Destroy()
end)
check("ToyBounceRouteWins",function()
	local r,layer=runtime(Levels.get(1,6))
	for tick=1,220 do
		if tick==61 then r.physics:sever(r.physics.ropes[1],1) end
		r:update(1/60)
	end
	assert(r.physics.bouncers.objects[1].hits>0)
	assert(r.state=="won" and r.count==3,r.state.." stars="..r.count)
	layer:Destroy()
end)
check("BouncerBothFacesAndRepeat",function()
	local b=Bouncers.new({{point=Vector2.zero,size=1,angle=0}})
	local top={pos=Vector2.new(0,-39),previous=Vector2.new(0,-39)}
	local bottom={pos=Vector2.new(0,39),previous=Vector2.new(0,39)}
	b:update(.016,{top,bottom})
	assert(math.abs(top.pos.Y+52.44)<.001 and math.abs(bottom.pos.Y-52.44)<.001)
	assert(b.objects[1].hits==2)
end)
check("HalvesCannotEnterMagicHats",function()
	local level=fixture(Vector2.new(1000,400),Vector2.new(1500,400))
	level.socks={{point=Vector2.new(1000,400),angle=90,group=0},{point=Vector2.new(1500,400),angle=90,group=0}}
	local p=Physics.new(level)
	for _=1,30 do p:tick() assert(not p.transport and not p.teleports) end
end)
root:Destroy()
local gui=game.Players.LocalPlayer.PlayerGui:WaitForChild("CutTheRopeGui")
gui:SetAttribute("DxSplitChecks",game.HttpService:JSONEncode(results))
print("DX SPLIT CHECKS",game.HttpService:JSONEncode(results))
