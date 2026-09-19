if not game:GetService("RunService"):IsStudio() then return end
local shared=game.ReplicatedStorage.CutTheRope.Shared
local Physics=require(shared.DxPhysics)
local Runtime=require(shared.LevelRuntime)
local Levels=require(shared.LevelPack15)
local Layers=require(shared.GameplayLayers)
local Frames=require(shared.CheeseFrames)
local root=Instance.new("ScreenGui")
root.Name,root.Enabled,root.Parent="DxCheeseChecks",false,game.Players.LocalPlayer.PlayerGui
local results={}
local function check(name,fn)
	local ok,message=pcall(fn)
	results[name]=ok and "PASS" or tostring(message)
	if not ok then warn("DX CHEESE",name,message) end
	task.wait()
end
local function level()
	return {id="mouse-test",pack=15,canvasSize=Vector2.new(2560,1440),mapSize=Vector2.new(960,1440),target=Vector2.new(2000,1300),
		candyStart=Vector2.new(1000,400),ropes={},stars={},bubbles={},spikes={},
		mice={{point=Vector2.new(1000,400),index=2,radius=150,duration=.3},{point=Vector2.new(1200,700),index=1,radius=150,duration=.3}}}
end
check("AllAuthoredMouseDefinitions",function()
	local count=0
	for _,l in ipairs(Levels) do
		assert(l.pack==15 and #l.mice>=2)
		local p=Physics.new(l)
		assert(p.mice.active.index==1)
		for i,d in ipairs(l.mice) do
			local m=p.mice.objects[i]
			assert(m.point==d.point and m.angle==d.angle and m.radius==d.radius and m.duration==Vector2.new(d.duration,0).X)
			count+=1
		end
	end
	root:SetAttribute("AuthoredMice",count)
end)
check("EntryActivationAndStrictTouchRadius",function()
	local p=Physics.new(level())
	local m=p.mice.active
	for _=1,4 do p.mice:update(.016) end
	assert(not m.active)
	p.mice:update(.016)
	assert(m.active)
	p.mice:grab(m,p.candy)
	assert(not p.mice:press(m.point+Vector2.new(m.radius,0)))
	assert(p.mice:press(m.point+Vector2.new(m.radius-.01,0)))
	assert(not m.carry and m.retreating and not m.active and not p.candy.disableGravity)
	assert(p.candy.previous==p.candy.pos)
end)
check("GrabPreservesBubbleAndCutsOnlyOwnRopes",function()
	local l=level()
	l.ropes={{anchor=Vector2.new(1000,100),length=300,radius=-1}}
	local p=Physics.new(l)
	p.bubble,p.bubbleIndex=true,1
	p.mice:grab(p.mice.active,p.candy)
	assert(p.bubble and p.candy.disableGravity and p.ropes[1].cut)
	assert(#p.candy.constraints>0,"source keeps deferred cut constraints")
	for _=1,3 do p:tick() end
	assert(#p.candy.constraints==0)
end)
check("SameCarryTransfersByLogicalIndex",function()
	local p=Physics.new(level())
	local a=p.mice.active
	p.mice:grab(a,p.candy)
	p.mice:retreat(a)
	for _=1,10 do p.mice:update(.016) end
	assert(p.mice.active.index==2 and p.mice.active.carry==p.candy and not a.carry)
	assert(p.candy.disableGravity)
	for _=1,40 do p.mice:update(.016) end
	assert(p.mice.handoffs>=2)
end)
check("SplitAndLanternCaptureEligibility",function()
	local l=level()
	l.halves={l.mice[2].point,l.mice[2].point+Vector2.new(500,0)}
	local p=Physics.new(l)
	for _=1,20 do p.mice:update(.016) end
	assert(p.mice.captures==0)
	p.split=nil p.candy.pos=p.mice.active.point p.lanterns.inLantern=true
	for _=1,10 do p.mice:update(.016) end
	assert(p.mice.captures==0)
end)
check("ShutdownAndRetirementDoNotStrandCandy",function()
	local p=Physics.new(level())
	p.mice:grab(p.mice.active,p.candy)
	p.mice:shutdown()
	assert(not p.candy.disableGravity and not p.mice.active.carry and p.mice.locked)
	for _=1,200 do p.mice:update(.016) end
	assert(p.mice.handoffs==0 and p.mice.captures==1)
	local q=Physics.new(level())
	q.mice:grab(q.mice.active,q.candy)
	q:retireCandy()
	assert(q.retired and not q.mice.active.carry)
end)
check("OriginalFramesLayersAndNoAllocation",function()
	local layer=Instance.new("Frame",root)
	local r=Runtime.new(layer,Levels[1])
	assert(#Frames.mouse==29 and #Frames.support==1)
	assert(#r.mice.holes==#Levels[1].mice)
	assert(r.mice.body.root.ZIndex<r.candy.ZIndex and r.mice.holes[1].root.ZIndex<Layers.Support)
	local count=#layer:GetDescendants()
	for _=1,300 do r.physics.mice:update(.016) r.mice:update() end
	assert(#layer:GetDescendants()==count)
	local before=r.physics.mice.active
	r:resize(Vector2.new(390,844))
	assert(r.physics.mice.active==before)
	layer:Destroy()
end)
check("RestartDoesNotMutateDefinitions",function()
	local p=Physics.new(Levels[1])
	for _=1,500 do p:tick() end
	local q=Physics.new(Levels[1])
	assert(q.mice.captures==0 and q.mice.handoffs==0 and not q.mice.active.active and q.mice.active.index==1)
	assert(Levels[1].mice[1].carry==nil and Levels[1].mice[1].elapsed==nil)
end)
root:SetAttribute("Results",game.HttpService:JSONEncode(results))
root:SetAttribute("Complete",true)
print("DX CHEESE CHECKS",game.HttpService:JSONEncode(results))
