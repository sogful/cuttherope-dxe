if not game:GetService("RunService"):IsStudio() then return end
local shared=game.ReplicatedStorage.CutTheRope.Shared
local Physics=require(shared.DxPhysics)
local Levels=require(shared.LevelData)
local Runtime=require(shared.LevelRuntime)
local Frames=require(shared.AdvancedFrames)
local results={}
local function check(name,callback)
	local ok,message=pcall(callback)
	results[name]=ok and "PASS" or tostring(message)
	if not ok then warn("DX advanced check",name,message) end
	task.wait()
end
check("CoalescedWheelArc",function()
	local coarse=Physics.new(Levels.get(1,7)).ropes[1].wheel
	local fine=Physics.new(Levels.get(1,7)).ropes[1].wheel
	local function point(w,degrees) local a=math.rad(degrees) return w.rope.anchor+Vector2.new(math.cos(a),math.sin(a))*90 end
	coarse:begin(point(coarse,0)) fine:begin(point(fine,0))
	for step=1,4 do coarse:dragPointer(point(coarse,-step*90)) end
	for step=1,80 do fine:drag(point(fine,-step*4.5)) end
	assert(#coarse.rope.bodies==#fine.rope.bodies,"fast arc must reel the same segment count")
	assert(#coarse.rope.bodies<=8,"fast turn must retract several segments")
	assert(math.abs(coarse.angle+360)<.01)
	local count=#coarse.rope.bodies
	coarse:dragPointer(coarse.last)
	assert(#coarse.rope.bodies==count,"stationary pointer must not reel")
	for step=1,80 do coarse:dragPointer(point(coarse,-360-step*90)) end
	assert(#coarse.rope.bodies==3,"coalescing preserves lower bound")
end)
check("NearestGravityAndNoSwitch",function()
	local definition=table.clone(Levels.get(1,8))
	definition.gravityButtons={Vector2.new(0,0),Vector2.new(1270,710),Vector2.new(2550,1430)}
	local physics=Physics.new(definition)
	assert(physics.mechanics:toggleNearestGravity(Vector2.new(1280,720)))
	assert(physics.gravityInverted and physics.mechanics.lastGravityButton==2)
	physics.mechanics:toggleNearestGravity(Vector2.new(2400,1400))
	assert(not physics.gravityInverted and physics.mechanics.lastGravityButton==3)
	local no=Physics.new(Levels.get(1,1))
	assert(not no.mechanics:toggleNearestGravity(Vector2.zero) and not no.gravityInverted)
end)
check("LinkedSpikesAndCancelledPress",function()
	local physics=Physics.new(Levels.get(25,9))
	local hazards=physics.hazards
	local index
	for i,o in ipairs(hazards.objects) do if o.group==1 then index=i break end end
	local object=hazards.objects[index]
	assert(physics.mechanics:press(object.point))
	physics.mechanics:release(nil)
	assert(not object.normal and not object.pressed)
	physics.mechanics:press(object.point)
	physics.mechanics:release(object.point)
	for _,o in ipairs(hazards.objects) do assert(o.normal==(o.group==1)) end
	for _=1,20 do hazards:update(.016) end
	for _,o in ipairs(hazards.objects) do if o.group==1 then assert(math.abs(o.angle-o.origAngle-90)<.001) end end
	assert(hazards.objects[index].half==({202,319,444,559})[Levels.get(25,9).spikes[index].size]/2)
end)
check("MovingHookPinnedAndPathWins",function()
	local physics=Physics.new(Levels.get(1,10))
	local rope=physics.ropes[2]
	local first=rope.anchor
	physics:tick()
	assert(rope.anchor~=first and rope.bodies[1].pos==rope.anchor and rope.bodies[1].pin==rope.anchor)
	physics:sever(rope,2)
	local cut=rope.anchor
	physics:tick()
	assert(rope.anchor~=cut,"bee keeps moving after cut")
	for _,level in ipairs(Levels.packs[10]) do for _,r in ipairs(level.ropes) do assert(not (r.movement and r.rail)) end end
end)
check("SecondLayerObjects",function()
	local level=Levels.get(25,10)
	assert(#level.stars==3 and #level.ropes==5 and level.halves)
	local count=0
	for _,rope in ipairs(level.ropes) do if rope.movement then count+=1 end end
	assert(count==3)
end)
check("BeeAndSpikeVisualRegistration",function()
	local gui=game.Players.LocalPlayer.PlayerGui:WaitForChild("CutTheRopeGui")
	local layer=Instance.new("Frame")
	layer.Size,layer.Visible,layer.Parent=UDim2.fromOffset(1120,630),false,gui
	local bee=Runtime.new(layer,Levels.get(1,10))
	assert(layer.Bee2.ZIndex<layer.Candy.ZIndex)
	assert(#bee.advanced.pollen>30 and #Frames.bee==4)
	assert(math.abs(layer.Bee2.Size.X.Scale-275*.77/2560)<.00001)
	local spikes=Runtime.new(layer,Levels.get(1,9))
	assert(layer.Spike1:FindFirstChild("RotateButton") and layer.Spike1:GetAttribute("SourceQuad")==3)
	assert(spikes.advanced.buttons[1] and #Frames.buttonMirror==4)
	layer:Destroy()
end)
check("GravityUsesScrolledViewCenter",function()
	local definition=table.clone(Levels.get(1,8))
	definition.gravityButtons={Vector2.new(1280,720),Vector2.new(1280,1700),Vector2.new(2400,1400)}
	local layer=Instance.new("Frame")
	layer.Visible,layer.Parent=false,game.Players.LocalPlayer.PlayerGui:WaitForChild("CutTheRopeGui")
	local runtime=Runtime.new(layer,definition)
	runtime.camera.render=Vector2.new(0,980)
	runtime.camera.scale=1
	assert(runtime:gravityShortcut() and layer:GetAttribute("LastGravityButton")==2)
	runtime.camera.ignoreTouches=true
	assert(not runtime:gravityShortcut() and runtime.physics.gravityInverted)
	runtime.camera.ignoreTouches=false
	runtime.state="won"
	assert(not runtime:gravityShortcut() and runtime.physics.gravityInverted)
	layer:Destroy()
end)
local gui=game.Players.LocalPlayer.PlayerGui:WaitForChild("CutTheRopeGui")
gui:SetAttribute("DxAdvancedCheckResults",game.HttpService:JSONEncode(results))
print("DX ADVANCED CHECKS",game.HttpService:JSONEncode(results))
