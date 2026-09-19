if not game:GetService("RunService"):IsStudio() then return end
local shared=game.ReplicatedStorage.CutTheRope.Shared
local Physics=require(shared.DxPhysics)
local Steam=require(shared.SteamMechanics)
local Runtime=require(shared.LevelRuntime)
local Levels=require(shared.LevelData)
local Math=require(shared.DxMath)
local Layers=require(shared.GameplayLayers)
local results={}
local function check(name,callback)
	local ok,message=pcall(callback)
	results[name]=ok and "PASS" or tostring(message)
	if not ok then warn("DX STEAM CHECK",name,message) end
end
local function level(angle)
	return {id="steam-test",pack=13,candyStart=Vector2.new(1000,800),target=Vector2.new(1400,1200),
		mapSize=Vector2.new(960,1440),canvasSize=Vector2.new(2560,1440),ropes={},stars={},bubbles={},spikes={},
		steamTubes={{point=Vector2.new(1000,1000),angle=angle or 0,scale=3}}}
end
check("AuthoredSteamMaps",function()
	local count=0
	for i=1,25 do local l=Levels.get(i,13) assert(l) count+=#l.steamTubes end
	assert(count==69,"Tube count "..count)
end)
check("ScaledRotatedValveTouchAndCycle",function()
	for _,angle in ipairs({0,90,180,270,37}) do
		local p=Physics.new(level(angle))
		local t=p.steam.objects[1]
		local center=Steam.valvePoint(t)
		assert(not p.steam:press(center+Vector2.new(120.1,0)))
		for state=1,3 do assert(p.mechanics:press(center+Vector2.new(100,0))) assert(t.state==state%3) end
		assert(t.phase==0 and t.revision==3)
	end
end)
check("ValveDoesNotRestartItsActiveTurn",function()
	local p=Physics.new(level())
	local t=p.steam.objects[1]
	p.steam:press(Steam.valvePoint(t))
	for _=1,10 do p.steam:update(Math.float(.016)) end
	local age=t.valveAge
	p.steam:press(Steam.valvePoint(t))
	assert(t.valveAge==age and t.state==2 and t.phase==0)
	for _=1,40 do p.steam:update(Math.float(.016)) end
	p.steam:press(Steam.valvePoint(t))
	p.steam:update(Math.float(.016))
	assert(t.valveRotation<0 and t.state==0)
end)
check("ForceBoundsCenteringAndGravityAlignment",function()
	local p=Physics.new(level())
	local t,b=p.steam.objects[1],p.candy
	t.state=1
	b.velocity=Vector2.new(40,200)
	b.pos=Vector2.new(1020,850)
	assert(p.steam:operate(t,b,Math.float(.016)))
	assert(b.pos.X<1020 and b.pos.Y<850)
	b.pos=Vector2.new(1068,850)
	assert(not p.steam:operate(t,b,Math.float(.016)))
	b.pos=Vector2.new(1000,980)
	assert(not p.steam:operate(t,b,Math.float(.016)))
	for _,angle in ipairs({0,90,180,270}) do
		t.angle=angle
		b.velocity=Vector2.zero
		b.pos=t.point+Math.rotate(Vector2.new(0,-150),Math.radians(angle))
		local initial=b.pos
		assert(p.steam:operate(t,b,Math.float(.016)))
		local localforce=Math.rotate(b.pos-initial,-Math.radians(angle))
		assert(localforce.Y<0)
	end
	t.angle=180
	p.gravityInverted=true
	b.pos,b.velocity=Vector2.new(1000,1150),Vector2.zero
	p.steam:operate(t,b,Math.float(.016))
	assert(b.pos.Y>1150.8)
end)
check("BothHalvesAndRemovedBodies",function()
	local l=level()
	l.halves={Vector2.new(980,850),Vector2.new(1020,850)}
	local p=Physics.new(l)
	p.steam.objects[1].state=1
	p.steam:update(Math.float(.016))
	assert(p.split[1].pos.Y<850 and p.split[2].pos.Y<850)
	p:retireCandy(p.split[1])
	local stopped=p.split[1].pos
	p.steam:update(Math.float(.016))
	assert(p.split[1].pos==stopped)
	p.transport={}
	stopped=p.split[2].pos
	p.steam:update(Math.float(.016))
	assert(p.split[2].pos==stopped)
end)
check("RestartDoesNotMutateAuthoredTubes",function()
	local l=Levels.get(16,13)
	local p=Physics.new(l)
	p.steam:press(Steam.valvePoint(p.steam.objects[1]))
	p:tick()
	local fresh=Physics.new(l)
	assert(fresh.steam.objects[1].state==0 and fresh.steam.objects[1].phase==0)
	assert(l.steamTubes[1].state==nil)
end)
check("PuffLayeringPoolRetirementAndResize",function()
	local layer=Instance.new("Frame")
	layer.Size=UDim2.fromOffset(1280,720)
	local r=Runtime.new(layer,level())
	local t=r.physics.steam.objects[1]
	local v=r.steam.objects[1]
	assert(#v.puffs==7 and v.body.frame.ZIndex==Layers.SteamBack)
	for cycle=1,60 do
		r.physics.steam:press(Steam.valvePoint(t))
		r.physics.steam:update(Math.float(.016))
		r.steam:update()
		assert(#v.puffs<=42)
	end
	for _=1,80 do r.physics.steam:update(Math.float(.016)) r.steam:update() end
	assert(#v.puffs==7)
	for variant,pool in ipairs(v.pool) do
		assert(#pool==14)
		for _,puff in ipairs(pool) do
			assert(puff.frame.ZIndex==(variant==3 and Layers.SteamBack or Layers.SteamFront))
			local count=0 for _ in pairs(puff.atlas.fixedFrames) do count+=1 end assert(count==11)
		end
	end
	local position,phase,state=r.physics.candy.pos,t.phase,t.state
	r:resize(Vector2.new(1440,2800))
	assert(r.physics.candy.pos==position and t.phase==phase and t.state==state)
	layer:Destroy()
end)
local gui=game.Players.LocalPlayer.PlayerGui:WaitForChild("CutTheRopeGui")
gui:SetAttribute("DxSteamChecks",game.HttpService:JSONEncode(results))
print("DX STEAM CHECKS",game.HttpService:JSONEncode(results))
