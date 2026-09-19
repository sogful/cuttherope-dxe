if not game:GetService("RunService"):IsStudio() then return end
local shared=game.ReplicatedStorage.CutTheRope.Shared
local Physics=require(shared.DxPhysics)
local Runtime=require(shared.LevelRuntime)
local Levels=require(shared.LevelData)
local Frames=require(shared.PillowFrames)
local root=Instance.new("ScreenGui")
root.Name,root.Enabled,root.Parent="DxPillowChecks",false,game.Players.LocalPlayer.PlayerGui
local results={}
local function check(name,fn)
	local ok,message=pcall(fn)
	results[name]=ok and "PASS" or tostring(message)
	if not ok then warn("DX PILLOW CHECK",name,message) end
	task.wait()
end
local function definition()
	return {id="nightcheck",pack=16,night=true,candyStart=Vector2.new(700,300),target=Vector2.new(1000,900),ropes={},stars={Vector2.new(1000,700)},bubbles={},bulbs={{point=Vector2.new(1000,700),radius=180,number="first"}}}
end
local function runtime(d)
	local layer=Instance.new("Frame",root)
	layer.Size=UDim2.fromOffset(1280,720)
	return Runtime.new(layer,d),layer
end
check("All25AuthoredMapsAndRopeBindings",function()
	local count=0
	for i=1,25 do
		local d=Levels.get(i,16)
		local p=Physics.new(d)
		assert(#p.bulbs==1 and p.night.enabled)
		count+=#p.bulbs
		for j,r in ipairs(p.ropes) do if d.ropes[j].bulb and r.active then assert(r.tail==p.bulbs[1],d.id) end end
		local r,layer=runtime(d)
		for _=1,30 do r:update(1/60) end
		assert(layer:FindFirstChild("LightBulb1") and layer:FindFirstChild("BulbGlow1"))
		layer:Destroy()
		task.wait()
	end
	assert(count==25)
end)
check("StrictLightRadiusAndNoBulbStarCollection",function()
	local p=Physics.new(definition())
	local b=p.bulbs[1]
	assert(p.night:illuminated(b.pos+Vector2.new(179.9,0)))
	assert(not p.night:illuminated(b.pos+Vector2.new(180,0)))
	b.transport={} assert(not p.night:illuminated(b.pos)) b.transport=nil
	local r,layer=runtime(definition())
	r:advance(1/60)
	assert(r.count==0,"bulb collected a star")
	assert(r.physics.night.lit[1])
	layer:Destroy()
end)
check("DarkStarsCannotBeCollected",function()
	local d=definition() d.candyStart=d.stars[1] d.bulbs[1].point=Vector2.new(1500,300)
	local r,layer=runtime(d)
	r:advance(1/60) assert(r.count==0)
	r.physics.bulbs[1].pos,r.physics.bulbs[1].previous=Vector2.new(1100,700),Vector2.new(1100,700)
	r:advance(1/60) assert(r.count==1)
	layer:Destroy()
end)
check("BulbBubbleOwnershipAndSingleCapturePerTick",function()
	local d=definition() d.bubbles={d.bulbs[1].point,d.candyStart}
	local p=Physics.new(d) p:tick()
	assert(p:hasBubble(p.bulbs[1]) and not p:hasBubble(p.candy))
	p:tick() assert(p:hasBubble(p.candy))
	p:popBubble(p.bulbs[1]) assert(not p:hasBubble(p.bulbs[1]) and p:hasBubble(p.candy))
end)
check("HatsTransportBulbWithoutHidingCandy",function()
	local d=definition()
	d.socks={{point=d.bulbs[1].point,angle=0,group=0},{point=Vector2.new(1500,500),angle=0,group=0}}
	local p=Physics.new(d)
	p:tick() assert(p.bulbs[1].transport and not p.transport and #p:activeBodies()==1)
	for _=1,9 do p:tick() end
	assert(not p.bulbs[1].transport and p.bulbs[1].pos.X==1500 and not p.retired)
end)
check("SleepWakeAndLightsOutLoss",function()
	local r,layer=runtime(definition())
	r:advance(1/60) assert(r.animator.state=="sleeping" and not r.animator.mouth)
	local b=r.physics.bulbs[1]
	b.pos,b.previous=r.physics.target,r.physics.target
	r:advance(1/60) assert(r.physics.night.awake and r.animator.state=="excited")
	b.pos,b.previous=Vector2.new(900,1900),Vector2.new(900,1900)
	r:advance(1/60) assert(r.state=="failed" and b.removed)
	layer:Destroy()
end)
check("CaptureSquishEndsAndMouseSpinStops",function()
	local d=definition() d.night=false d.bulbs={} d.bubbles={d.candyStart}
	local r,layer=runtime(d)
	for _=1,75 do r:update(1/60) end
	local sprite=r.bubbles[1].sprite
	assert((sprite.pending and sprite.pending.index or sprite.index)==7)
	for _=1,30 do r:update(1/60) end
	assert((sprite.pending and sprite.pending.index or sprite.index)==7)
	layer:Destroy()
	d.bubbles={}
	d.ghosts={{point=d.candyStart,forms=3,radius=0,angle=0}}
	local ghostRuntime,ghostLayer=runtime(d)
	local ghost=ghostRuntime.physics.ghosts.objects[1]
	ghostRuntime.physics.ghosts:reset(ghost,2)
	for _=1,75 do ghostRuntime:update(1/60) end
	local visible=0
	for _,item in pairs(ghostRuntime.ghosts.items) do
		if item.root.Visible then
			visible+=1
			assert((item.atlas.pending and item.atlas.pending.index or item.atlas.index)==7)
		end
	end
	assert(visible==1 and ghostRuntime.physics:hasBubble(ghostRuntime.physics.candy))
	ghostLayer:Destroy()
	local p=Physics.new(Levels.get(1,15))
	p.candy.rotation,p.candy.residual=47,5
	p.mice:grab(p.mice.active,p.candy)
	for _=1,25 do p:tick() end
	assert(p.candy.rotation==47 and p.candy.residual==0)
end)
check("OriginalRegistrationAndNoRenderAllocation",function()
	assert(#Frames.lighter==43 and #Frames.nightstar==31 and #Frames.sleeping==7)
	local r,layer=runtime(Levels.get(1,16))
	r:update(1/60)
	local count=#layer:GetDescendants()
	for _=1,60 do r:present() end
	assert(#layer:GetDescendants()==count)
	assert(layer.LightBulb1.ZIndex>layer.Candy.ZIndex and layer.BulbGlow1.ZIndex<layer.Star1.ZIndex)
	local star=layer.Star1.UnlitStar
	assert(math.abs(star.Size.X.Scale-300/552)<1e-6)
	layer:Destroy()
end)
root:SetAttribute("Results",game.HttpService:JSONEncode(results))
root:SetAttribute("Complete",true)
print("DX PILLOW CHECKS",root:GetAttribute("Results"))
