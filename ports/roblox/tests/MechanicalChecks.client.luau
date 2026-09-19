if not game:GetService("RunService"):IsStudio() then return end
local shared=game.ReplicatedStorage.CutTheRope.Shared
local Physics=require(shared.DxPhysics)
local Runtime=require(shared.LevelRuntime)
local Levels=require(shared.LevelData)
local Conveyor=require(shared.ConveyorMechanics)
local Layers=require(shared.GameplayLayers)
local root=Instance.new("ScreenGui")
root.Name,root.Enabled,root.ZIndexBehavior,root.Parent="DxMechanicalChecks",false,Enum.ZIndexBehavior.Sibling,game.Players.LocalPlayer.PlayerGui
local results={}
local function check(name,fn)
	local ok,message=pcall(fn)
	results[name]=ok and "PASS" or tostring(message)
	if not ok then warn("DX MECHANICAL CHECK",name,message) end
	task.wait()
end
local function belt(point,length,angle,manual)
	return {point=point or Vector2.new(100,100),length=length or 300,width=60,angle=angle or 0,manual=manual~=false,velocity=60}
end
local function definition()
	return {id="beltcheck",pack=17,candyStart=Vector2.new(900,500),target=Vector2.new(1600,1200),stars={},bubbles={},ropes={},conveyors={belt()}}
end
local function runtime(d)
	local layer=Instance.new("Frame",root) layer.Size=UDim2.fromOffset(1280,720)
	return Runtime.new(layer,d),layer
end
check("SingleAndMultiWrapSourceCases",function()
	for _,v in ipairs({{30,500,58,2},{270,-500,242,-2},{30,20,274,1},{270,-20,26,-1}}) do
		local p,_,_,crossings=Conveyor.move(v[1],v[2],300)
		assert(p==v[3] and crossings==v[4])
	end
	assert(Conveyor.move(18,0,300)==18 and Conveyor.move(282,0,300)==282)
end)
check("RotatedCenterlineAndPointerInertia",function()
	local d=definition() d.conveyors={belt(Vector2.new(700,700),600,25)}
	local p=Physics.new(d) local m=p.conveyors local b=m.objects[1]
	local a,z=Conveyor.worldpoint(b,200,0),Conveyor.worldpoint(b,300,0)
	assert(m:press(a)) assert(not m:press(a))
	m:drag(z) assert(math.abs(b.delta+100)<.001)
	m:release(Conveyor.worldpoint(b,320,0))
	assert(math.abs(b.delta+20)<.001)
	m:update(.016) assert(math.abs(b.delta+15)<.001 and not m.held)
	local xy=Conveyor.localpoint(b,Conveyor.worldpoint(b,450,20))
	assert((xy-Vector2.new(450,20)).Magnitude<.001)
	m:cancel() assert(b.delta==0 and not b.active)
end)
check("ManualHandoffAndAutomaticOwnership",function()
	local d=definition() d.stars={Vector2.new(250,100)}
	d.conveyors={belt(),belt(Vector2.new(150,100))}
	local p=Physics.new(d) local m=p.conveyors local item=m.byKind.star[1]
	assert(item.belt==m.objects[1])
	m.objects[2].activation=2 m:movebelt(m.objects[2],0)
	assert(item.belt==m.objects[2] and m.handoffs==1)
	m.objects[1].activation=1 m:movebelt(m.objects[1],0) assert(item.belt==m.objects[2])
	m.objects[1].activation=3 m:movebelt(m.objects[1],0) assert(item.belt==m.objects[1])
	m.objects[2].manual=false m:movebelt(m.objects[2],0) assert(item.belt==m.objects[2])
	m.objects[1].activation=9 m:movebelt(m.objects[1],0) assert(item.belt==m.objects[2])
end)
check("WrapCutsOnlySameCandySiblingRopes",function()
	local d=definition() d.halves={Vector2.new(180,260),Vector2.new(700,260)}
	d.candyStart=d.halves[1]
	d.ropes={{anchor=Vector2.new(130,100),length=160,radius=-1,part=1},{anchor=Vector2.new(500,100),length=400,radius=-1,part=1},{anchor=Vector2.new(700,100),length=160,radius=-1,part=2}}
	local p=Physics.new(d) local m=p.conveyors
	local before,previous=p.split[1].pos,p.split[1].previous
	local other=p.split[2].pos
	m:movebelt(m.objects[1],500)
	assert(not p.ropes[1].cut and p.ropes[2].cut and not p.ropes[3].cut)
	assert(p.ropes[2].cutIndex==#p.ropes[2].bodies-2)
	local offset=p.ropes[1].anchor-d.ropes[1].anchor
	assert(p.split[1].pos==before+offset and p.split[1].previous==previous+offset and p.split[2].pos==other)
	assert(p.ropes[1].bodies[1].pin==p.ropes[1].anchor)
end)
check("AutoHookWrapPreservesSiblingAndPin",function()
	local d=definition() d.candyStart=Vector2.new(130,160)
	d.ropes={{anchor=Vector2.new(130,100),length=60,radius=150},{anchor=Vector2.new(600,100),length=470,radius=-1}}
	local p=Physics.new(d) p:attach(p.ropes[1],60)
	local m=p.conveyors local before=p.candy.pos
	m:movebelt(m.objects[1],500)
	assert(not p.ropes[2].cut and p.candy.pos~=before and not p.ropes[1].cut)
	p:tick() assert(p.ropes[1].bodies[1].pin==p.ropes[1].anchor)
end)
check("CollectedStarsAndCapturedBubblesLeaveBelt",function()
	local d=definition() d.candyStart=Vector2.new(250,100)
	d.stars={d.candyStart} d.bubbles={d.candyStart}
	local r,layer=runtime(d)
	r:advance(1/60)
	assert(r.count==1 and r.physics:hasBubble(r.physics.candy))
	assert(not r.physics.conveyors.byKind.star[1].belt and not r.physics.conveyors.byKind.bubble[1].belt)
	local star=r.physics.starPositions[1] local bubble=r.physics.bubbles[1]
	r.physics.conveyors:movebelt(r.physics.conveyors.objects[1],150)
	assert(r.physics.starPositions[1]==star and r.physics.bubbles[1]==bubble)
	for _=1,60 do r:update(1/60) end
	assert(r.bubbles[1].visual.Size==UDim2.fromScale(250/2560,250/1440))
	layer:Destroy()
end)
check("All25MapsAndPooledDrawPasses",function()
	local count=0
	for n=1,25 do
		local r,layer=runtime(Levels.get(n,17))
		count+=#r.physics.conveyors.objects
		assert(layer.Conveyors.ZIndex>Layers.Disc and layer.Conveyors.ZIndex<Layers.Bubble)
		local descendants=#layer.Conveyors:GetDescendants()
		for _=1,25 do r:update(1/60) end
		assert(#layer.Conveyors:GetDescendants()==descendants,"belt renderer allocated mid-animation")
		for _,v in ipairs(r.conveyors.objects) do
			local sum=0
			for _,tile in ipairs(v.tiles) do if tile.Visible then sum+=tile.Size.Y.Scale end end
			assert(math.abs(sum-1)<.00001,"belt tile gap/overflow")
		end
		layer:Destroy() task.wait()
	end
	assert(count==48)
end)
check("RestartDoesNotMutateAuthoredMaps",function()
	local d=Levels.get(16,17)
	local a=Physics.new(d)
	for _=1,180 do a:tick() end
	local b=Physics.new(d)
	for i,position in ipairs(d.stars) do assert(position==b.starPositions[i]) end
	for i,position in ipairs(d.bubbles) do assert(position==b.bubbles[i]) end
	for _,v in ipairs(b.conveyors.objects) do assert(v.offset==0) end
end)
check("LossCancelsHeldBeltWithoutStoppingAutomaticBelts",function()
	local d=definition() d.conveyors[2]=belt(Vector2.new(1000,100),300,0,false)
	local r,layer=runtime(d)
	assert(r:press(Vector2.new(200,100))) r:drag(Vector2.new(240,100))
	r.physics.candy.pos,r.physics.candy.previous=Vector2.new(900,2500),Vector2.new(900,2500)
	r:advance(1/60)
	assert(r.state=="failed" and not r.physics.conveyors.held and r.physics.conveyors.objects[1].delta==0)
	local offset=r.physics.conveyors.objects[2].offset r:advance(1/60)
	assert(r.physics.conveyors.objects[2].offset~=offset)
	layer:Destroy()
end)
root:SetAttribute("Results",game.HttpService:JSONEncode(results))
root:SetAttribute("Complete",true)
print("DX MECHANICAL CHECKS",game.HttpService:JSONEncode(results))
