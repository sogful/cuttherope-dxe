if not game:GetService("RunService"):IsStudio() then return end
local shared=game.ReplicatedStorage.CutTheRope.Shared
local Physics=require(shared.DxPhysics)
local Levels=require(shared.LevelData)
local Runtime=require(shared.LevelRuntime)
local Background=require(shared.LevelBackground)
local Frames=require(shared.WheelFrames)
local results={}
local function check(name,callback)
	local ok,message=pcall(callback)
	results[name]=ok and "PASS" or tostring(message)
	if not ok then warn("DX wheel check",name,message) end
end
check("WheelRolloverAndLimit",function()
	local physics=Physics.new(Levels.get(1,7))
	local rope=physics.ropes[1]
	local wheel=rope.wheel
	assert(physics.mechanics:press(rope.anchor+Vector2.new(90,0)))
	local initial=#rope.bodies
	for i=1,260 do
		local a=math.rad(-i*8)
		physics.mechanics:drag(rope.anchor+Vector2.new(math.cos(a),math.sin(a))*90)
		assert(not rope.cut)
	end
	assert(#rope.bodies==3 and #rope.points==3 and #rope.bodies<initial)
	for i=1,60 do
		local a=math.rad(-260*8+i*8)
		physics.mechanics:drag(rope.anchor+Vector2.new(math.cos(a),math.sin(a))*90)
	end
	assert(#rope.bodies>3 and #rope.points==#rope.bodies)
	physics.mechanics:release()
	assert(not wheel.operating and not physics.mechanics.heldWheel)
end)
check("WheelExclusionZone",function()
	local physics=Physics.new(Levels.get(1,7))
	local rope=physics.ropes[1]
	assert(not physics:cut(rope.anchor+Vector2.new(-150,0),rope.anchor+Vector2.new(150,0)))
	assert(not physics:cut(rope.anchor,rope.anchor,100))
	local midpoint=(rope.anchor+physics.candy.pos)*.5
	assert(physics:cut(midpoint-Vector2.new(300,0),midpoint+Vector2.new(300,0)))
end)
check("UncapturedAutoWheel",function()
	local definition=table.clone(Levels.get(1,7))
	definition.ropes={{anchor=Vector2.new(100,100),length=100,radius=120,wheel=true}}
	local physics=Physics.new(definition)
	local rope=physics.ropes[1]
	assert(rope.wheel:begin(rope.anchor+Vector2.new(90,0)))
	rope.wheel:drag(rope.anchor+Vector2.new(0,90))
	assert(not rope.active and rope.wheel:armScale()==0)
	physics.candy.pos,physics.candy.previous=rope.anchor,rope.anchor
	physics:tick()
	assert(rope.active and #rope.bodies>2)
end)
check("GravityReleaseAndCancellation",function()
	local physics=Physics.new(Levels.get(1,8))
	local objects=physics.mechanics
	local point=objects.gravityButtons[1]
	assert(objects:press(point) and not physics.gravityInverted)
	objects:release(point+Vector2.new(300,0))
	assert(not physics.gravityInverted)
	objects:press(point) objects:release()
	assert(not physics.gravityInverted)
	local previous,velocity=physics.candy.previous,physics.candy.velocity
	objects:press(point) objects:release(point)
	assert(physics.gravityInverted and physics.gravity.Y==-784 and physics.candy.previous==previous and physics.candy.velocity==velocity)
	objects:release(point)
	assert(physics.gravityInverted,"one toggle per captured gesture")
	objects:press(point) objects:release(point)
	assert(not physics.gravityInverted and physics.gravity.Y==784)
end)
check("InvertedBubbleAndEarthTimeline",function()
	local definition={candyStart=Vector2.zero,ropes={},stars={},bubbles={Vector2.zero}}
	local a,b=Physics.new(definition),Physics.new(definition)
	b:toggleGravity()
	assert(b:earthRotation()==0)
	for _=1,19 do a:tick() b:tick() end
	assert(a.bubble and b.bubble and (a.candy.pos+b.candy.pos).Magnitude<.001)
	assert(b:earthRotation()==180)
	b:toggleGravity()
	assert(b:earthRotation()==180)
	for _=1,19 do b:tick() end
	assert(b:earthRotation()==0)
end)
check("InvertedSpiderFall",function()
	local definition=table.clone(Levels.get(1,1))
	definition.ropes={{anchor=Vector2.new(1280,200),length=300,spider=true}}
	local physics=Physics.new(definition)
	physics:toggleGravity()
	physics.mechanics:bust(1)
	local spider=physics.mechanics.spiders[1]
	physics.mechanics:tick(.3)
	assert(spider.point.Y>spider.origin.Y)
	physics.mechanics:tick(.9)
	assert(spider.point.Y<spider.origin.Y)
end)
check("WheelAndGravityRegistration",function()
	local root=Instance.new("ScreenGui")
	root.Enabled,root.Parent=false,game.Players.LocalPlayer.PlayerGui
	local layer=Instance.new("Frame",root)
	local runtime=Runtime.new(layer,Levels.get(1,7))
	local parts=runtime.objects.wheels[1]
	assert(parts[1].frame.ZIndex<layer.Candy.ZIndex and parts[2].frame.ZIndex>layer.HookFront1.ZIndex)
	assert(parts[3].frame.Size==UDim2.fromScale(237/2560,237/1440))
	local before=parts[4].frame.Size
	local wheel=runtime.physics.ropes[1].wheel
	wheel:begin(wheel.rope.anchor+Vector2.new(90,0))
	wheel:drag(wheel.rope.anchor+Vector2.new(0,-90))
	runtime.objects:update(0)
	assert(parts[3].frame.Visible and not parts[4].frame.Visible and parts[4].frame.Size==before)
	assert(parts[2].frame.Rotation==parts[3].frame.Rotation)
	root:Destroy()
end)
check("CosmicBackgroundRegistration",function()
	local root=Instance.new("ScreenGui")
	root.Enabled,root.Parent=false,game.Players.LocalPlayer.PlayerGui
	local image=Instance.new("ImageLabel",root)
	local background=Background.new(image)
	background:setPack(8)
	local physics=Physics.new(Levels.get(1,8))
	background:update({scale=1,render=Vector2.zero,size=Vector2.new(2560,1440)},physics)
	local earth=background.earths[1]
	assert(earth.Position==UDim2.fromScale(1284/2560,724/1440) and earth.Rotation==0)
	assert(earth.Size==UDim2.fromScale(492/2560,494/1440))
	physics:toggleGravity()
	for _=1,19 do physics:tick() end
	background:update({scale=1,render=Vector2.zero,size=Vector2.new(2560,1440)},physics)
	assert(earth.Rotation==180)
	background:setPack(7)
	background:update({scale=1,render=Vector2.zero,size=Vector2.new(2560,1440)},physics)
	assert(not earth.Visible)
	root:Destroy()
end)
local gui=game.Players.LocalPlayer.PlayerGui:WaitForChild("CutTheRopeGui")
gui:SetAttribute("DxWheelChecks",game.HttpService:JSONEncode(results))
print("DX WHEEL CHECKS",game.HttpService:JSONEncode(results))
