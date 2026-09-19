if not game:GetService("RunService"):IsStudio() then return end
local shared=game.ReplicatedStorage.CutTheRope.Shared
local Physics=require(shared.DxPhysics)
local Runtime=require(shared.LevelRuntime)
local Levels=require(shared.LevelData)
local Frames=require(shared.LanternFrames)
local Visuals=require(shared.LanternVisuals)
local results={}
local function check(name,callback)
	local ok,message=pcall(callback)
	results[name]=ok and "PASS" or tostring(message)
	if not ok then warn("DX LANTERN CHECK",name,message) end
end
local function level(captured,moving)
	return {id="lantern-test",pack=14,candyStart=Vector2.new(1000,800),target=Vector2.new(1400,1200),
		mapSize=Vector2.new(960,1440),canvasSize=Vector2.new(2560,1440),ropes={},stars={},bubbles={},spikes={},
		lanterns={{point=Vector2.new(1000,800),captured=captured},
			{point=Vector2.new(1500,700),captured=captured,movement=moving and {offsets={Vector2.new(300,0)},speed=150}}}}
end
check("CaptureDelayAndSharedAuthoredOrder",function()
	local p=Physics.new(level(false))
	p:tick()
	assert(p.lanterns.inLantern and not p.lanterns.shared and p.candy.disableGravity)
	for _=1,3 do p:tick() end
	assert(not p.lanterns.shared)
	p:tick()
	assert(p.lanterns.shared==p.candy and p.candy.pos==p.lanterns.objects[2].point)
end)
check("TouchBoundsReleaseRevealAndCooldown",function()
	local p=Physics.new(level(true))
	local object=p.lanterns.objects[1]
	assert(not p.lanterns:press(object.point+Vector2.new(85,0)))
	assert(p.mechanics:press(object.point+Vector2.new(84.9,0)))
	assert(p.lanterns.shared and p.lanterns.inLantern)
	p:tick()
	assert(not p.lanterns.shared and p.lanterns.inLantern and not p.candy.disableGravity)
	assert(p.candy.pos==object.point)
	for _=1,5 do p:tick() end
	assert(p.lanterns.inLantern)
	p:tick()
	assert(not p.lanterns.inLantern and object.state==1)
	for _=1,25 do p:tick() end
	assert(object.state==0)
end)
check("MovingReleasePreservesSourceInertia",function()
	local p=Physics.new(level(true,true))
	local object=p.lanterns.objects[2]
	p:tick()
	assert(p.lanterns:touch(object,object.point))
	local before=object.point
	p:tick()
	assert(p.candy.previous==before and p.candy.pos==object.point and p.candy.pos.X>before.X)
	local displacement=p.candy.pos-p.candy.previous
	p:tick()
	assert(math.abs(p.candy.pos.X-object.point.X)<.001 and displacement.X>0)
end)
check("CaptureDetachesRopesAndBubble",function()
	local l=level(false)
	l.ropes={{anchor=Vector2.new(1000,500),length=200,radius=-1}}
	local p=Physics.new(l)
	p.bubble=true
	p.lanterns:beginCapture(p.lanterns.objects[1])
	assert(not p.bubble and #p.candy.constraints==1 and p.ropes[1].cut)
	for _=1,3 do p:tick() end
	assert(#p.candy.constraints==0 and not p.ropes[1].pendingCut)
end)
check("PreCapturedSkipsFixedRopesAndRemovalCancelsCallbacks",function()
	local l=level(true)
	l.ropes={{anchor=Vector2.new(1000,500),length=200,radius=-1}}
	local p=Physics.new(l)
	assert(not p.ropes[1].active)
	p.lanterns:press(p.lanterns.objects[1].point)
	p:retireCandy()
	for _=1,40 do p:tick() end
	assert(not p.lanterns.shared and not p.lanterns.pending and #p.lanterns.reveals==0)
	for _,object in ipairs(p.lanterns.objects) do assert(object.state==0 and object.phase=="idle") end
end)
check("OccupiedCandyDoesNotEnterHatOrHitSpike",function()
	local l=level(true)
	l.socks={{point=Vector2.new(1500,700),angle=0,group=0},{point=Vector2.new(1000,1200),angle=0,group=0}}
	l.spikes={{point=Vector2.new(1500,700),angle=0,size=1}}
	local p=Physics.new(l)
	for _=1,30 do p:tick() end
	assert(p.lanterns.shared and not p.transport and not p.hazard)
end)
check("RestartIsolationAndAuthoredMaps",function()
	for i=1,25 do
		local l=Levels.get(i,14)
		assert(l and #l.lanterns>0)
		local a,b=Physics.new(l),Physics.new(l)
		local start=b.candy.pos
		for _=1,180 do a:tick() end
		assert(b.candy.pos==start and b.lanterns.objects[1].point==l.lanterns[1].point)
	end
end)
check("AllCandySkinsHaveDedicatedLanternFrames",function()
	local root=Instance.new("Frame")
	for skin=0,51 do
		assert(#Frames["candy"..skin]==1)
		local p=Physics.new(level(true))
		local v=Visuals.new(root,p.lanterns,skin)
		assert(#v.objects==2)
		for _=1,10 do p:tick() v:update() end
		for _,object in ipairs(v.objects) do assert(object.candy.atlas.library==Frames) end
		root:ClearAllChildren()
	end
	root:Destroy()
end)
check("RuntimeHideRevealAndResize",function()
	local root=Instance.new("Frame") root.Size=UDim2.fromOffset(1280,720)
	root.Parent=game.Players.LocalPlayer.PlayerGui:WaitForChild("CutTheRopeGui")
	local l=level(true)
	local runtime=Runtime.new(root,l)
	runtime:draw()
	assert(not runtime.candy.Visible)
	local p=runtime.physics
	p.lanterns:press(p.lanterns.objects[1].point)
	for _=1,7 do runtime:update(1/60) end
	assert(runtime.candy.Visible and not p.lanterns.inLantern)
	local point=p.candy.pos
	root.Size=UDim2.fromOffset(390,844)
	runtime:draw()
	assert(p.candy.pos==point)
	runtime:press(p.candy.pos)
	assert(root:GetAttribute("LastPressWorldX")~=nil)
	local restarted=Runtime.new(root,l)
	assert(root:GetAttribute("LastPressWorldX")==nil and root:GetAttribute("LastLanternPressed")==nil)
	assert(restarted.physics.lanterns.inLantern and root:GetAttribute("LanternSharedPoint"))
	root:Destroy()
end)
check("OrderedChildPassesAndNoFrameChurn",function()
	local root=Instance.new("Frame")
	local p=Physics.new(level(true))
	local visual=Visuals.new(root,p.lanterns,0)
	local count=#root:GetDescendants()
	for i,v in ipairs(visual.objects) do
		assert(v.fire.frame.ZIndex<v.idle.frame.ZIndex and v.idle.frame.ZIndex<v.active.frame.ZIndex and v.active.frame.ZIndex<v.candy.frame.ZIndex)
		assert(v.fire.frame.Parent==v.candy.frame.Parent and v.candy.frame.Parent.ZIndex==i)
	end
	for tick=1,180 do
		if tick%40==1 then p.lanterns:touch(p.lanterns.objects[1],p.lanterns.objects[1].point) end
		if tick%40==0 then p.lanterns.inLantern=true p.lanterns:capture(p.lanterns.objects[2]) end
		p:tick() visual:update()
	end
	assert(#root:GetDescendants()==count)
	root:Destroy()
end)
local gui=game.Players.LocalPlayer.PlayerGui:WaitForChild("CutTheRopeGui")
gui:SetAttribute("DxLanternChecks",game.HttpService:JSONEncode(results))
print("DX LANTERN CHECKS",game.HttpService:JSONEncode(results))
