if not game:GetService("RunService"):IsStudio() then return end
local shared=game.ReplicatedStorage.CutTheRope.Shared
local Physics=require(shared.DxPhysics)
local Runtime=require(shared.LevelRuntime)
local Levels=require(shared.LevelData)
local results={}
local function check(name,callback)
	local ok,message=pcall(callback)
	results[name]=ok and "PASS" or tostring(message)
	if not ok then warn("DX GHOST CHECK",name,message) end
end
local function level(forms,radius)
	return {id="ghost-test",pack=12,candyStart=Vector2.new(1000,200),target=Vector2.new(1200,1200),
		mapSize=Vector2.new(960,1440),canvasSize=Vector2.new(2560,1440),ropes={},stars={},bubbles={},spikes={},
		ghosts={{point=Vector2.new(1000,600),forms=forms or 15,radius=radius or 150,angle=30}}}
end
check("AuthoredSpookyMaps",function()
	local ghosts=0
	for i=1,25 do local l=Levels.get(i,12) assert(l) ghosts+=#l.ghosts end
	assert(ghosts==53)
end)
check("AllowedFormsAndTouchBoundary",function()
	local p=Physics.new(level()) local g=p.ghosts.objects[1]
	assert(not p.ghosts:press(g.point+Vector2.new(80,0)))
	for _,form in ipairs({2,4,8,2,4}) do assert(p.ghosts:press(g.point) and g.form==form) end
	local p2=Physics.new(level(5)) local g2=p2.ghosts.objects[1]
	p2.ghosts:press(g2.point) local app=g2.app
	p2.ghosts:press(g2.point) assert(g2.app==app and g2.morphs==1)
end)
check("CaptureLocksGhostAndPopReturnsIdle",function()
	local d=level() d.candyStart=d.ghosts[1].point
	local p=Physics.new(d) local g=p.ghosts.objects[1]
	p.ghosts:press(g.point) p:tick()
	assert(p.bubble and p.ghosts:bubbleOwner(g.app)==p.candy)
	assert(not p.ghosts:press(g.point) and g.form==2)
	p:popBubble(p.candy)
	assert(not p.bubble and g.form==1)
	for _=1,20 do p:tick() end
	assert(#p.ghosts.apps==0)
end)
check("NearestSplitAnchorAndCutReset",function()
	local d=level(5,-1) d.halves={Vector2.new(800,200),Vector2.new(1000,500)}
	local p=Physics.new(d) local g=p.ghosts.objects[1]
	p.ghosts:press(g.point)
	local r=g.app.rope
	assert(r.tail==p.split[2] and r.length==100)
	p:sever(r,1) p:tick()
	assert(g.form==1 and r.cut)
	for _=1,20 do p:tick() end
	assert(r.removed and #p.split[2].constraints==0)
end)
check("BubbleReplacementReleasesOnlyItsOwner",function()
	local d=level() d.ghosts[2]={point=Vector2.new(1000,600),forms=3,radius=0,angle=0}
	d.candyStart=d.ghosts[1].point
	local p=Physics.new(d) local a,b=p.ghosts.objects[1],p.ghosts.objects[2]
	p.ghosts:reset(a,2) p:tick() p.ghosts:reset(b,2) p:tick()
	assert(a.form==1 and b.form==2 and p.bubble)
	p:retireCandy() assert(b.form==1)
end)
check("MergeParksSecondGhostUntilPop",function()
	local d=level(3) d.halves={Vector2.new(990,600),Vector2.new(1010,600)}
	d.ghosts[2]={point=Vector2.new(1010,600),forms=3,radius=0,angle=0}
	local p=Physics.new(d) local a,b=p.ghosts.objects[1],p.ghosts.objects[2]
	p.ghosts:reset(a,2) p.ghosts:reset(b,2)
	for i,g in ipairs({a,b}) do
		local body=p.split[i] body.bubble,body.bubbleIndex=true,g.app.index
		p.usedBubbles[g.app.index],g.app.owner=true,body
	end
	p:merge(true) p.split.distance=.01 p:merge(false)
	assert(not p.split and p.bubble and p.ghosts.parked==b.app)
	assert(not p.ghosts:touch(b,b.point))
	p:popBubble(p.candy)
	assert(a.form==1 and b.form==1 and not p.ghosts.parked)
end)
check("RetiredSlotsStayBoundedAndStopColliding",function()
	local p=Physics.new(level()) local g=p.ghosts.objects[1]
	for _=1,100 do
		p.ghosts:press(g.point)
		for _=1,14 do p:tick() end
	end
	assert(#p.ropes<=2 and #p.bubbles<=2 and #p.bouncers.objects<=2 and #p.ghosts.apps<=1)
	p.ghosts:reset(g,1)
	for _=1,14 do p:tick() end
	for _,o in ipairs(p.bouncers.objects) do assert(o.removed) end
end)
local gui=game.Players.LocalPlayer.PlayerGui:WaitForChild("CutTheRopeGui")
check("SameRenderBubbleSwapHidesOutgoingArt",function()
	local d=level()
	d.candyStart=d.ghosts[1].point
	d.bubbles={d.candyStart}
	local layer=Instance.new("Frame")
	layer.Size,layer.Visible,layer.Parent=UDim2.fromOffset(1120,630),false,gui
	local r=Runtime.new(layer,d)
	local g=r.physics.ghosts.objects[1]
	r.physics.ghosts:reset(g,2)
	r:update(1/30)
	assert(r.physics.bubble and r.physics.bubbleIndex==g.app.index)
	assert(not r.bubbles[1].visual.Visible and not r.bubbles[1].shadow.Visible)
	layer:Destroy()
end)
check("AllSpookyFormRenderers",function()
	local layer=Instance.new("Frame")
	layer.Size,layer.Visible,layer.Parent=UDim2.fromOffset(1120,630),false,gui
	for i=1,25 do
		local r=Runtime.new(layer,Levels.get(i,12))
		for cycle=1,4 do
			for _,g in ipairs(r.physics.ghosts.objects) do r.physics.ghosts:touch(g,g.point) end
			for _=1,24 do r:update(1/60) end
			for _,app in ipairs(r.physics.ghosts.apps) do assert(r.ghosts.items[app]) end
		end
		assert(#r.ghosts.particles==#r.physics.ghosts.objects*7)
		task.wait()
	end
	layer:Destroy()
end)
check("PrewarmedFormsAndResize",function()
	local layer=Instance.new("Frame")
	layer.Size,layer.Visible,layer.Parent=UDim2.fromOffset(1120,630),false,gui
	local r=Runtime.new(layer,level()) local g=r.physics.ghosts.objects[1]
	for _,form in ipairs({2,4,8}) do
		assert(#r.ghosts.pool[g][form]==2)
		r.physics.ghosts:reset(g,form) r:update(1/60)
		assert(r.ghosts.items[g.app])
	end
	local app,pos,time=g.app,r.physics.candy.pos,r.elapsed
	r:resize(Vector2.new(1440,2800))
	assert(g.app==app and r.physics.candy.pos==pos and r.elapsed==time)
	layer:Destroy()
end)
gui:SetAttribute("DxGhostChecks",game.HttpService:JSONEncode(results))
print("DX GHOST CHECKS",game.HttpService:JSONEncode(results))
