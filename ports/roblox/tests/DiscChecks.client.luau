if not game:GetService("RunService"):IsStudio() then return end
local shared=game.ReplicatedStorage.CutTheRope.Shared
local Physics=require(shared.DxPhysics)
local Levels=require(shared.LevelData)
local Runtime=require(shared.LevelRuntime)
local Math=require(shared.DxMath)
local Layers=require(shared.GameplayLayers)
local results={}
local function check(name,callback)
	local ok,message=pcall(callback)
	results[name]=ok and "PASS" or tostring(message)
	if not ok then warn("DX DISC CHECK",name,message) end
end
local function definition()
	return {pack=11,id="disc-test",canvasSize=Vector2.new(2560,1440),mapSize=Vector2.new(960,1440),
		candyStart=Vector2.new(0,800),target=Vector2.new(0,1200),stars={},bubbles={},spikes={},pumps={},socks={},ropes={},
		discs={{point=Vector2.zero,size=100,angle=0,oneHandle=false}}}
end
check("AvatarlessOpaqueShell",function()
	local p=game.Players.LocalPlayer
	local shell=p.PlayerGui:WaitForChild("CutTheRopeBlackBacking")
	assert(not game.Players.CharacterAutoLoads and p.Character==nil)
	assert(p.DevComputerMovementMode==Enum.DevComputerMovementMode.Scriptable and p.DevTouchMovementMode==Enum.DevTouchMovementMode.Scriptable)
	assert(workspace.CurrentCamera.CameraType==Enum.CameraType.Scriptable)
	assert(shell.Enabled and shell.DisplayOrder<0 and shell.IgnoreGuiInset and not shell.ResetOnSpawn)
	assert(shell.Black.BackgroundTransparency==0 and shell.Black.BackgroundColor3==Color3.new(0,0,0))
	assert(shell.Black.Size==UDim2.fromScale(1,1))
end)
check("SourceDimensionsAndOneHandle",function()
	local level=definition()
	level.discs[1].oneHandle=true
	local physics=Physics.new(level)
	local discs=physics.mechanics.discs
	local d=discs.objects[1]
	assert(d.radius==Math.float(534*Math.float(100/167)))
	assert(not discs:press(d.left) and discs:blocksCut(d.left))
	assert(discs:press(d.right) and discs.held==d)
	discs:release()
	assert(not discs.held and not d.activeRight)
end)
check("AnchorPinAndNonPlatformHooks",function()
	local level=definition()
	level.ropes={{anchor=Vector2.new(0,200),length=400,radius=-1},{anchor=Vector2.new(50,180),length=100,radius=100,rail={vertical=true,length=200,offset=0}},
		{anchor=Vector2.new(-50,180),length=100,radius=100,movement={offsets={Vector2.zero,Vector2.new(100,0)},speed=100,rotateSpeed=0}}}
	local physics=Physics.new(level)
	local discs=physics.mechanics.discs
	local previous=physics.ropes[1].bodies[1].previous
	local rail,bee=physics.ropes[2].anchor,physics.ropes[3].anchor
	discs:press(Vector2.new(300,0)) discs:drag(Vector2.new(0,300))
	assert((physics.ropes[1].anchor-Vector2.new(-200,0)).Magnitude<.001)
	assert(physics.ropes[1].bodies[1].pin==physics.ropes[1].anchor and physics.ropes[1].bodies[1].previous==previous)
	assert(physics.ropes[2].anchor==rail and physics.ropes[3].anchor==bee)
	assert(not physics:cut(Vector2.new(-1000,400),Vector2.new(1000,400)))
end)
check("FreeVersusCapturedBubblesAndImmutableMap",function()
	local level=definition()
	level.bubbles={Vector2.new(0,100),Vector2.new(0,150)}
	local physics=Physics.new(level)
	physics.usedBubbles[2]=true
	local discs=physics.mechanics.discs
	discs:press(Vector2.new(300,0)) discs:drag(Vector2.new(0,300))
	assert((physics.bubbles[1]-Vector2.new(-100,0)).Magnitude<.001)
	assert(physics.bubbles[2]==Vector2.new(0,150) and level.bubbles[1]==Vector2.new(0,100))
	assert(Physics.new(level).bubbles[1]==level.bubbles[1])
end)
check("PumpDirectionAndTargetAuthoredSquare",function()
	local level=definition()
	level.pumps={{point=Vector2.new(0,150),angle=0}}
	level.target=Vector2.new(0,50)
	local physics=Physics.new(level)
	local discs=physics.mechanics.discs
	discs:press(Vector2.new(300,0)) discs:drag(Vector2.new(0,300))
	assert((physics.mechanics.pumps[1].point-Vector2.new(-150,0)).Magnitude<.001)
	assert(math.abs(physics.mechanics.pumps[1].angle-90)<.001)
	assert((physics.target-Vector2.new(-50,0)).Magnitude<.001 and level.target==Vector2.new(0,50))
	physics.target=Vector2.new(0,150)
	discs:drag(Vector2.new(-300,0))
	assert(physics.target==Vector2.new(0,150),"target uses size=100, not radius=319")
end)
check("OverlapReorderAndNestedDisc",function()
	local level=definition()
	level.discs[2]={point=Vector2.new(400,0),size=100,angle=0}
	local physics=Physics.new(level)
	local discs=physics.mechanics.discs
	assert(discs:press(discs.objects[1].left))
	assert(#discs.order==3 and discs.order[1].copy and discs.order[3]==discs.objects[1])
	for _=1,14 do discs:update(.016) end
	assert(#discs.order==2 and discs.order[2]==discs.objects[1])
	level.discs[2].point,level.discs[2].size=Vector2.zero,30
	discs=Physics.new(level).mechanics.discs
	discs:press(discs.objects[1].left)
	assert(#discs.order==2 and discs.order[1]==discs.objects[1],"outer disc must stay behind nested disc")
end)
local gui=game.Players.LocalPlayer.PlayerGui:WaitForChild("CutTheRopeGui")
check("RegisteredArtAndPooledOverlapFrames",function()
	local layer=Instance.new("Frame")
	layer.Size,layer.Visible,layer.Parent=UDim2.fromOffset(1120,630),false,gui
	local level=table.clone(Levels.get(1,11))
	local first=level.discs[1]
	level.discs={first,{point=first.point+Vector2.new(400,0),size=first.size,angle=0}}
	local runtime=Runtime.new(layer,level)
	local discs=runtime.physics.mechanics.discs
	local visual=runtime.discs.items[discs.objects[1]]
	assert(runtime.discs.root.ZIndex==Layers.Disc and Layers.Disc<Layers.Bubble and Layers.Disc>Layers.Target)
	assert(math.abs(visual.face[1].frame.Size.X.Scale*2560-1066*first.size/167)<.001)
	assert(visual.highlights[1].frame.Rotation==0 and visual.label.Rotation==first.angle)
	assert(visual.label.Name=="ContinuousSticker" and not visual.root:FindFirstChild("Sticker1"))
	local pool=runtime.discs.spares[1]
	assert(pool)
	discs:press(discs.objects[1].left)
	runtime.discs:update()
	assert(runtime.discs.items[discs.order[1]]==pool,"overlap must use staged art")
	for _=1,14 do discs:update(.016) end
	runtime.discs:update()
	assert(runtime.discs.spares[1]==pool and not pool.root.Visible)
	layer:Destroy()
end)
check("DynamicResizeDoesNotTurnOrCutDisc",function()
	local layer=Instance.new("Frame")
	layer.Size,layer.Visible,layer.Parent=UDim2.fromOffset(700,900),false,gui
	local runtime=Runtime.new(layer,Levels.get(1,11),Vector2.new(1440,2560))
	local d=runtime.physics.mechanics.discs.objects[1]
	local position,angle,time=runtime.physics.candy.pos,d.angle,runtime.elapsed
	runtime:resize(Vector2.new(3440,1440))
	assert(runtime.physics.candy.pos==position and d.angle==angle and runtime.elapsed==time)
	assert(runtime.discs.items[d].root.Visible)
	layer:Destroy()
end)
gui:SetAttribute("DxDiscChecks",game.HttpService:JSONEncode(results))
print("DX DISC CHECKS",game.HttpService:JSONEncode(results))
