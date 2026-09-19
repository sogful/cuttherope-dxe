if not game:GetService("RunService"):IsStudio() then return end
local shared=game.ReplicatedStorage.CutTheRope.Shared
local Layout=require(shared.ViewportLayout)
local Camera=require(shared.GameplayCamera)
local Runtime=require(shared.LevelRuntime)
local Levels=require(shared.LevelData)
local Background=require(shared.LevelBackground)
local Panels=require(shared.BoxTransition)
local Packs=require(shared.PackSelection)
local Hud=require(shared.LevelHud)
local RunService=game:GetService("RunService")
local root=Instance.new("ScreenGui")
root.Name,root.Enabled,root.IgnoreGuiInset,root.Parent="DxViewportChecks",false,true,game.Players.LocalPlayer.PlayerGui
local results={}
local function check(name,callback)
	local ok,message=pcall(callback)
	results[name]=ok and "PASS" or tostring(message)
	if not ok then warn("DX viewport check",name,message) end
	task.wait()
end
local sizes={Vector2.new(1920,1080),Vector2.new(1600,1000),Vector2.new(1024,768),Vector2.new(900,900),
	Vector2.new(2560,1080),Vector2.new(3440,1440),Vector2.new(390,844),Vector2.new(320,800)}
local function host(size)
	local frame=Instance.new("Frame")
	frame.Size,frame.BackgroundTransparency,frame.Parent=UDim2.fromOffset(size.X,size.Y),1,root
	return frame
end
check("ContentFitAndNoAspectClamp",function()
	assert(Layout.compute(sizes[1]).content==1)
	assert(math.abs(Layout.compute(Vector2.new(400,1000)).content-1.55)<1e-5)
	local wide=Layout.compute(Vector2.new(4000,1000))
	assert(wide.visible.X==5760 and wide.content==1.15)
end)
check("All425CameraFitsAndInputRoundTrips",function()
	local count=0
	for pack=1,17 do for index=1,25 do
		local level=Levels.get(index,pack)
		for _,size in ipairs(sizes) do
			local v=Layout.compute(size).visible
			local c=Camera.new(level,v)
			assert(v.X/c.scale>=c.window.X-.001 and v.Y/c.scale>=c.window.Y-.001)
			for _,point in ipairs({Vector2.zero,level.candyStart,level.target,Vector2.new(2560,1440)}) do
				assert((c:world(c:screen(point))-point).Magnitude<.002)
			end
			local position,mode=c.position,c.mode
			c:resize(Vector2.new(2560,1440)) c:resize(v)
			assert(c.position==position and c.mode==mode,"fit must not advance camera tracking")
		end
		count+=1
	end task.wait() end
	assert(count==425)
end)
check("UniformWorldAndStatePreservingResize",function()
	for _,id in ipairs({{1,1},{1,15},{5,1},{7,1},{8,1},{9,1},{10,1},{11,1},{11,18},{13,1},{13,9},{13,22},{14,1},{14,8},{14,25},{15,1},{15,19},{15,25}}) do
		local container=host(sizes[1])
		local frame=Instance.new("Frame") frame.Parent=container
		local runtime=Runtime.new(frame,Levels.get(id[2],id[1]))
		for tick=1,10 do runtime:update(1/60) end
		local candy,elapsed,clock,count,position=runtime.physics.candy.pos,runtime.elapsed,runtime.clock,runtime.count,runtime.camera.position
		for _,size in ipairs(sizes) do
			container.Size=UDim2.fromOffset(size.X,size.Y)
			runtime:resize(Layout.compute(size).visible)
			RunService.Heartbeat:Wait()
			assert(math.abs(frame.AbsoluteSize.X/2560-frame.AbsoluteSize.Y/1440)<.002,"world stretch")
			assert(runtime.physics.candy.pos==candy and runtime.elapsed==elapsed and runtime.clock==clock and runtime.count==count)
			assert(runtime.camera.position==position)
		end
		container:Destroy()
	end
end)
check("BackgroundAndClosedPanelsCoverEveryShape",function()
	for _,size in ipairs(sizes) do
		local container=host(size)
		local image=Instance.new("ImageLabel") image.Parent=container
		local background=Background.new(image)
		local c=Camera.new(Levels.get(1),Layout.compute(size).visible)
		background:update(c)
		local panels=Panels.new(container,1,true)
		RunService.Heartbeat:Wait()
		local p,s=panels.root.AbsolutePosition-container.AbsolutePosition,panels.root.AbsoluteSize
		assert(p.X<=1 and p.Y<=1 and p.X+s.X>=size.X-1 and p.Y+s.Y>=size.Y-1)
		for _,corner in ipairs({Vector2.new(1,1),Vector2.new(size.X-1,1),size-Vector2.one,Vector2.new(1,size.Y-1)}) do
			local found=false
			for _,tile in ipairs(background.tiles) do
				local a,b=tile.AbsolutePosition-container.AbsolutePosition,tile.AbsoluteSize
				if corner.X>=a.X-.01 and corner.Y>=a.Y-.01 and corner.X<=a.X+b.X+.01 and corner.Y<=a.Y+b.Y+.01 then found=true end
				assert(math.abs(b.X/2560-b.Y/1440)<.002,"background stretch")
			end
			assert(found,"uncovered background corner")
		end
		container:Destroy()
	end
end)
check("ResponsivePackSlotsAndScreenLockedMonster",function()
	local container=host(sizes[1]) container:SetAttribute("PageReady",true)
	local pack=Packs.new(container,8,function() end,function() end,function() return false end)
	local function settleLayout()
		-- Roblox defers AbsoluteSize signals and GUI layout independently. Await
		-- both phases before comparing screen coordinates across a resize. Hidden
		-- ScreenGuis also evaluate AbsoluteSize lazily, so explicitly resolve it.
		for _=1,4 do
			local resolved=container.AbsoluteSize+pack.root.AbsoluteSize+pack.strip.AbsoluteSize
			assert(resolved.X>0)
			RunService.RenderStepped:Wait() RunService.Heartbeat:Wait()
		end
	end
	local maximum=0
	for _,size in ipairs(sizes) do
		container.Size=UDim2.fromOffset(size.X,size.Y)
		settleLayout()
		local count=pack.root:GetAttribute("VisibleBoxes")
		assert(count>=1 and count<=3)
		if size.X/size.Y<1 then assert(count==1) end
		assert(pack.model.selected==8)
		local entry=pack.cards[8]
		local monster=entry.monster.AbsolutePosition
		pack.model.x-=100
		settleLayout()
		local drift=(entry.monster.AbsolutePosition-monster).Magnitude
		maximum=math.max(maximum,drift)
		assert(drift<.01,"monster drift="..drift.." at "..tostring(size))
		pack.model.x=-(8-1)*640
	end
	root:SetAttribute("MonsterMaxDrift",maximum)
	container:Destroy()
end)
check("ConnectedRopeSurfaceCoversDynamicViewport",function()
	local container=host(sizes[1]) container.Visible=false
	root.Enabled=true
	local frame=Instance.new("Frame") frame.Parent=container
	local runtime=Runtime.new(frame,Levels.get(1))
	assert(runtime.ropeRenderer,"EditableImage unavailable")
	for _,size in ipairs(sizes) do
		container.Size=UDim2.fromOffset(size.X,size.Y)
		runtime:resize(Layout.compute(size).visible)
		for _=1,2 do RunService.RenderStepped:Wait() RunService.Heartbeat:Wait() end
		local renderer=runtime.ropeRenderer
		assert(renderer and renderer.width<=1024 and renderer.height<=1024)
		local image=renderer.image
		assert((image.AbsolutePosition-container.AbsolutePosition).Magnitude<.01)
		assert(image.AbsoluteSize.X>=size.X-.01 and image.AbsoluteSize.Y>=size.Y-.01)
		assert(image.AbsoluteSize.X-size.X<4 and image.AbsoluteSize.Y-size.Y<4)
	end
	container:Destroy()
	root.Enabled=false
end)
check("HudLabelHigherAndBottomAnchored",function()
	local container=host(sizes[1])
	local hud=Hud.new(container,{}) hud:reset(1,1)
	local design=hud.label.Design
	assert(design.AnchorPoint==Vector2.new(0,1))
	local height=hud.texts.Number.Size.Y.Offset
	assert(hud.texts.Level.Position.Y.Offset==hud.texts.Number.Position.Y.Offset-height+18)
	for _,size in ipairs(sizes) do
		container.Size=UDim2.fromOffset(size.X,size.Y)
		RunService.Heartbeat:Wait()
		assert(math.abs(design.AbsolutePosition.Y+design.AbsoluteSize.Y-container.AbsolutePosition.Y-size.Y)<.01)
	end
	container:Destroy()
end)
root:SetAttribute("Results",game:GetService("HttpService"):JSONEncode(results))
root:SetAttribute("Complete",true)
print("DX VIEWPORT CHECKS",root:GetAttribute("Results"))
