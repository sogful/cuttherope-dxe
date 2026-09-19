local shared=game.ReplicatedStorage.CutTheRope.Shared
local Camera,Runtime,Levels=require(shared.GameplayCamera),require(shared.LevelRuntime),require(shared.LevelData)
local Traces=require(shared.DesktopCameraTraces)
local root=Instance.new("ScreenGui")
root.Name,root.Enabled,root.Parent="DxCameraChecks",false,game.Players.LocalPlayer.PlayerGui
local function layer()
	local frame=Instance.new("Frame")
	frame.Size,frame.Parent=UDim2.fromOffset(1120,630),root
	return frame
end
local maximum=0
for _,run in ipairs(Traces) do
	local runtime=Runtime.new(layer(),Levels.get(15))
	local sampleindex=1
	for tick=0,480 do
		if tick%30==0 then task.wait() end
		if tick>0 then
			if run.fast and tick==31 then assert(runtime.camera:press()) end
			runtime:update(1/60)
		end
		local sample=run.samples[sampleindex]
		if sample and sample.tick==tick then
			local c=runtime.camera
			for _,pair in ipairs({{c.render.X,sample.x},{c.render.Y,sample.y},{c.position.X,sample.trackedX},
				{c.position.Y,sample.trackedY},{c.speed,sample.speed},{runtime.physics.candy.pos.X,sample.candyX},
				{runtime.physics.candy.pos.Y,sample.candyY}}) do
				local error=math.abs(pair[1]-pair[2])
				maximum=math.max(maximum,error)
				assert(error<.1,"Camera/candy golden mismatch at"..tick..": "..error)
			end
			assert(c.ignoreTouches==sample.ignoreTouches,"Input handoff mismatch")
			assert((c.mode=="intro")== (sample.mode=="CAMERASPEEDPIXELS"),"Camera mode mismatch")
			sampleindex+=1
		end
	end
	assert(sampleindex==#run.samples+1)
	runtime.layer:Destroy()
end
root:SetAttribute("GoldenMaxError",maximum)

for _,level in ipairs(Levels.list) do
	local c=Camera.new(level)
	for _,point in ipairs({Vector2.zero,level.candyStart,level.target,Vector2.new(2560,1440)}) do
		assert((c:world(c:screen(point))-point).Magnitude<.001)
	end
	if level.id~="1_15" then assert(c.mode=="follow" and c.render==Vector2.zero and c.scale==1) end
end
local runtime=Runtime.new(layer(),Levels.get(15))
local start=runtime.physics.candy.pos
for tick=1,60 do runtime:update(1/60) if tick%30==0 then task.wait() end end
assert(runtime.camera.mode=="intro" and runtime.physics.candy.pos==start)
assert(runtime.elapsed==0 and runtime.clock==0 and runtime.count==0)
assert(not runtime:cut(Vector2.new(0,2400),Vector2.new(2560,2400)))
runtime.camera:press()
for tick=1,120 do runtime:update(1/60) if tick%30==0 then task.wait() end end
assert(runtime.camera.mode=="follow" and runtime.state=="playing" and runtime.elapsed>0)
assert(not runtime.camera:outside(Vector2.new(1280,3100)))
assert(runtime.camera:outside(Vector2.new(1280,3281)))
assert(not runtime.camera:outside(Vector2.new(1280,-399)))
assert(runtime.camera:outside(Vector2.new(1280,-401)))
runtime.layer:Destroy()

local a,b=Runtime.new(layer(),Levels.get(15)),Runtime.new(layer(),Levels.get(15))
for tick=1,480 do a:update(1/60) if tick%30==0 then task.wait() end end
for tick=1,240 do b:update(1/30) if tick%30==0 then task.wait() end end
assert((a.physics.candy.pos-b.physics.candy.pos).Magnitude<.001)
assert((a.camera.render-b.camera.render).Magnitude<.001)
assert(math.abs(a.elapsed-b.elapsed)<.0001)
a.layer:Destroy() b.layer:Destroy()
local Background=require(shared.LevelBackground)
local original=Instance.new("ImageLabel")
original.Parent=layer()
local background=Background.new(original)
local tall=Camera.new(Levels.get(15))
for _,y in ipairs({0,720,1440}) do
	tall.position=Vector2.new(tall.origin.X,y)
	tall:fit()
	background:update(tall)
	assert(background.holder:GetAttribute("SeamCount")==1)
	assert(#background.tiles==4 and #background.seams==2)
	local first,second=background.tiles[1],background.tiles[2]
	assert(math.abs(first.Position.X.Scale+first.Size.X.Scale-second.Position.X.Scale)<.000001,"Background gap")
end
background:update(Camera.new(Levels.get(1)))
assert(background.holder:GetAttribute("SeamCount")==0)
for _,seam in ipairs(background.seams) do assert(not seam.Visible,"Tall seam leaked into1-1") end
background.holder.Parent:Destroy()
root:SetAttribute("Passed",true)
print("DX CAMERA CHECKS PASS: real DX traces, pan freeze/acceleration, "..#Levels.list.." map transforms, loss bounds, 30/60Hz")
