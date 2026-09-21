local shared=game.ReplicatedStorage:WaitForChild("CutTheRope"):WaitForChild("Shared")
local Physics=require(shared.DxPhysics)
local Levels=require(shared.LevelData)
local Hazards=require(shared.SpikeHazards)
local Mover=require(shared.PathMover)
local Runtime=require(shared.LevelRuntime)
local RunService=game:GetService("RunService")
local results={}
local function check(name,callback)
	local ok,error=pcall(callback)
	results[name]=ok and "PASS" or tostring(error)
	if not ok then warn("DX box check",name,error) end
end
local function empty(point)
	return {candyStart=point or Vector2.zero,ropes={},stars={},bubbles={},spikes={}}
end
check("Authored425Maps",function()
	for pack=1,17 do
		assert(#Levels.packs[pack]==25)
		for index=1,25 do
			local level=Levels.get(index,pack)
			assert(level.id==pack.."_"..index and Levels.supported(pack,index))
			local physics=Physics.new(level)
			for tick=1,180 do
				physics:tick()
				local point=physics.candy.pos
				assert(point.X==point.X and point.Y==point.Y and math.abs(point.X)<1e7 and math.abs(point.Y)<1e7,level.id)
			end
			if index%5==0 then task.wait() end
		end
	end
	assert(not Levels.supported(18,1))
end)
check("PumpImpulseAndGesture",function()
	local level=empty(Vector2.new(0,-100))
	level.pumps={{point=Vector2.zero,angle=0}}
	local physics=Physics.new(level)
	local objects=physics.mechanics
	assert(objects:press(Vector2.zero))
	for _=1,3 do objects:tick(.016) end
	assert(objects.pumps[1].shots==0)
	objects:tick(.016)
	assert(objects.pumps[1].shots==1)
	assert(math.abs(physics.candy.pos.Y-(-100-2*524*.016))<.001)
	objects:press(Vector2.zero)
	objects:drag(Vector2.new(11,0))
	objects:tick(.1)
	assert(objects.pumps[1].shots==1)
	physics.candy.pos=Vector2.new(200,-100)
	objects:fire(objects.pumps[1])
	assert(physics.candy.pos==Vector2.new(200,-100))
	physics.candy.pos=Vector2.new(0,100)
	objects:fire(objects.pumps[1])
	assert(physics.candy.pos==Vector2.new(0,100))
end)
check("RailClampAndPinnedAnchor",function()
	local level=Levels.get(1,3)
	local physics=Physics.new(level)
	local rope=physics.ropes[1]
	local original=rope.definition.anchor
	assert(physics.mechanics:press(rope.anchor))
	physics.mechanics:drag(original+Vector2.new(5000,5000))
	assert(rope.anchor==original+Vector2.new(600,0))
	physics:tick()
	assert(rope.bodies[1].pin==rope.anchor and rope.bodies[1].pos==rope.anchor)
	physics.mechanics:drag(original-Vector2.new(5000,5000))
	assert(rope.anchor==original and rope.definition.anchor==original)
	physics.mechanics:release()
	assert(not physics.mechanics.heldRail)
end)
check("ElectrodeCyclesAndCollision",function()
	local hazards=Hazards.new({{point=Vector2.zero,size=5,angle=0,electric={delay=.5,off=1,on=.3}}})
	assert(not hazards:hit(Vector2.zero,Vector2.zero))
	hazards:update(1.49)
	assert(not hazards.objects[1].on)
	hazards:update(.02)
	assert(hazards.objects[1].on and hazards:hit(Vector2.zero,Vector2.zero)==1)
	hazards:update(.3)
	assert(not hazards.objects[1].on and not hazards:hit(Vector2.zero,Vector2.zero))
end)
check("CircularMoverSourcePolygon",function()
	local definition={radius=150,clockwise=true,speed=99,rotateSpeed=20}
	local mover=Mover.new(Vector2.new(200,300),definition,90)
	assert(#mover.path==75 and mover.pos==Vector2.new(350,300))
	local first=mover.pos
	mover:update(.016)
	assert(math.abs((mover.pos-first).Magnitude-99*.016)<.001 and mover.pos.Y>300)
	assert(math.abs(mover.angle-90.32)<.001)
end)
check("HatEntryReleaseAndExit",function()
	local level=empty(Vector2.new(0,-5))
	level.ropes={{anchor=Vector2.new(0,-300),length=200,radius=-1}}
	level.socks={{point=Vector2.zero,angle=0,group=1},{point=Vector2.new(500,0),angle=180,group=1}}
	local physics=Physics.new(level)
	physics.candy.previous,physics.candy.velocity=Vector2.new(0,-20),Vector2.new(0,300)
	physics.bubble=true
	physics.mechanics:tick(.016)
	assert(physics.transport and physics.bubble and #physics.candy.constraints==0 and physics.ropes[1].cut)
	for _=1,7 do physics.mechanics:advanceTransport(.016) physics.mechanics:tick(.016) end
	assert(not physics.transport and physics.teleports==1 and physics.bubble)
	assert((physics.candy.pos-Vector2.new(500,16)).Magnitude<.001)
	assert(math.abs(physics.candy.velocity.Y-378)<.001)
	assert(math.abs(physics.candy.previous.Y-9.7)<.001)
	assert(physics.mechanics.hats[2].state=="throwing")
end)
check("SpiderStartupAndBust",function()
	local level=empty(Vector2.new(0,400))
	level.ropes={{anchor=Vector2.zero,length=300,radius=-1,spider=true}}
	local physics=Physics.new(level)
	local spider=physics.mechanics.spiders[1]
	for _=1,30 do physics:tick() end
	assert(spider.state=="walking" and spider.distance==0)
	for _=1,60 do physics:tick() end
	assert(spider.distance>0 and spider.quad>=7)
	physics:sever(physics.ropes[1],2)
	assert(spider.state=="busted" and spider.quad==11)
	for _=1,90 do physics:tick() end
	assert(spider.hidden and not physics.stolen)
end)
local cache=game.Players.LocalPlayer.PlayerGui:WaitForChild("DxTextureCache")
local deadline=os.clock()+30
repeat task.wait(.1) until cache:GetAttribute("LoadedTextures")==cache:GetAttribute("ResidentTextures") or os.clock()>deadline
check("SpiderStealAndTimedStarLifecycles",function()
	local root=Instance.new("ScreenGui")
	root.Name,root.Enabled,root.Parent="DxBoxLifecycleChecks",false,game.Players.LocalPlayer.PlayerGui
	local layer=Instance.new("Frame",root)
	layer.Size=UDim2.fromOffset(1120,630)
	local definition=table.clone(Levels.get(1,1))
	definition.ropes={{anchor=Vector2.new(1280,200),length=150,radius=-1,spider=true}}
	definition.candyStart=Vector2.new(1280,450)
	definition.stars={Vector2.new(800,800)}
	definition.starTimeouts={.16}
	definition.starMotion={}
	local runtime=Runtime.new(layer,definition)
	for _=1,50 do runtime:update(1/60) end
	assert(runtime.stars[1].expired and not runtime.stars[1].container.Visible)
	assert(runtime.count==0 and runtime.stars[1].ring.empty.ImageTransparency==1)
	for _=1,600 do runtime:update(1/60) end
	assert(runtime.state=="failed" and runtime.lossDelay==2)
	assert(runtime.physics.stolen==1 and runtime.physics.retired and runtime.physics.ropes[1].cut)
	assert(runtime.physics.mechanics.spiders[1].hidden and not runtime.candy.Visible)
	root:Destroy()
end)
check("HatColorsAndBubbleRetirement",function()
	local root=Instance.new("ScreenGui")
	root.Enabled,root.Parent=false,game.Players.LocalPlayer.PlayerGui
	local layer=Instance.new("Frame",root)
	local definition=table.clone(Levels.get(1,4))
	definition.bubbles={definition.candyStart}
	definition.socks={{point=definition.candyStart,angle=0,group=1},{point=Vector2.new(1500,300),angle=180,group=1}}
	local runtime=Runtime.new(layer,definition)
	runtime:update(1/60)
	assert(runtime.physics.transport and not runtime.physics.bubble and not runtime.attached)
	local art=runtime.objects.hats[1].visual.atlas
	assert(art.pending and art.pending.index==1 or art.index==1)
	root:Destroy()
end)
check("AllNewMapRenderers",function()
	local root=Instance.new("ScreenGui")
	root.Name,root.Enabled,root.Parent="DxBoxRenderChecks",false,game.Players.LocalPlayer.PlayerGui
	for pack=1,17 do for number=1,25 do
		local layer=Instance.new("Frame")
		layer.Size,layer.Parent=UDim2.fromOffset(1120,630),root
		local level=Levels.get(number,pack)
		local runtime=Runtime.new(layer,level)
		for _=1,3 do runtime:update(1/60) end
		assert(layer:GetAttribute("Level")==level.id)
		assert(#runtime.objects.pumps==#level.pumps and #runtime.objects.hats==#level.socks)
		assert(#runtime.steam.objects==#(level.steamTubes or {}))
		assert(#runtime.lanterns.objects==#(level.lanterns or {}))
		assert(#runtime.mice.holes==#(level.mice or {}))
		assert(#runtime.conveyors.objects==#(level.conveyors or {}))
		layer:Destroy()
		task.wait()
	end end
	root:Destroy()
end)
game.Players.LocalPlayer.PlayerGui.CutTheRopeGui:SetAttribute("DxBoxChecks",game.HttpService:JSONEncode(results))
print("DX BOX CHECKS",game.HttpService:JSONEncode(results))
