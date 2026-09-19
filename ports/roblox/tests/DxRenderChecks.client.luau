local shared=game.ReplicatedStorage.CutTheRope.Shared
local Raster=require(shared.RopeRasterizer)
local Animator=require(shared.TargetAnimator)
local Xml=require(shared.XmlTargetAnimator)
local RunService=game:GetService("RunService")
local gui=Instance.new("ScreenGui")
gui.Name,gui.DisplayOrder,gui.Parent="DxRenderChecks",-900,game.Players.LocalPlayer.PlayerGui
local raster=Raster.new(48,48)
local white=Color3.new(1,1,1)
local a,b,c,d=Vector2.new(8,8),Vector2.new(40,8),Vector2.new(40,40),Vector2.new(8,40)
raster:triangle(a,b,c,white,white,white,.5,.5,.5)
raster:triangle(c,d,a,white,white,white,.5,.5,.5)
local output=raster:finish()
for y=8,39 do for x=8,39 do
	local alpha=buffer.readu8(output,(y*48+x)*4+3)
	assert(math.abs(alpha-128)<=1,"Shared triangle edge cracked or blended twice: "..alpha)
end end
assert(buffer.readu8(output,3)==0)
raster:clear()
raster:triangle(Vector2.new(-100,-100),Vector2.new(-10,-100),Vector2.new(-10,-10),white,white,white,1,1,1)
raster:triangle(a,a,a,white,white,white,1,1,1)
assert(buffer.readu32(raster:finish(),(20*48+20)*4)==0,"Stale rope pixels")
gui:SetAttribute("TriangleJoins",true)
local Renderer=require(shared.RopeRenderer)
local Levels,Physics,Camera=require(shared.LevelData),require(shared.DxPhysics),require(shared.GameplayCamera)
local bench=setmetatable({raster=Raster.new(1024,576),texture={WritePixelsBuffer=function() end},image={},layer=gui,vertices={},frames=0},Renderer)
local simulation=Physics.new(Levels.get(7))
local camera=Camera.new(Levels.get(7))
local maximum,total,resolve=0,0,0
for _=1,30 do
	simulation:update(1/60)
	bench:draw(simulation.ropes,camera)
	maximum=math.max(maximum,bench.milliseconds)
	total+=bench.milliseconds resolve+=bench.resolveMilliseconds
	RunService.RenderStepped:Wait()
end
gui:SetAttribute("SixRopeRasterMaxMs",maximum)
gui:SetAttribute("SixRopeRasterMeanMs",total/30)
gui:SetAttribute("SixRopeResolveMeanMs",resolve/30)
for _,skin in ipairs({0,1}) do
	local parent=Instance.new("Frame")
	parent.Size,parent.Parent=UDim2.fromOffset(270,270),gui
	local target=skin==0 and Animator.new(parent,Random.new(42)) or Xml.new(parent,skin,Random.new(42))
	local visual=target.visual
	local total=0
	for _ in pairs(visual.fixedFrames) do total+=1 end
	local deadline=os.clock()+40
	repeat RunService.RenderStepped:Wait() until visual.current or os.clock()>deadline
	assert(visual.current,"Initial pose never became ready")
	local poses={}
	for _,state in ipairs({"opening","chewing","idle","sad","greeting","excited","closing","variationone","variationtwo"}) do
		target:play(state)
		for frame=1,24 do
			target:update(1/30)
			RunService.RenderStepped:Wait()
			local count=0
			for _,label in pairs(visual.fixedFrames) do
				if label.Visible and label.ImageTransparency<.99 then count+=1 assert(label.IsLoaded,"Promoted an undrawable pose") end
			end
			assert(count==1,"Blank/overlapping target poses: "..count)
			poses[visual.current]=true
		end
	end
	local after=0
	for _ in pairs(visual.fixedFrames) do after+=1 end
	assert(after==total,"Created a cold pose during animation handoff")
	local previous=visual.current
	local group=skin==0 and "sad" or "t"..target.data.config.timelines.Sad
	local label=visual.fixedFrames[group..":0"]
	visual.ready[label]=nil
	assert(not visual:show(group,0) and visual.current==previous and previous.Visible)
	visual:show(visual.group,visual.index)
	assert(visual.pending==nil,"Stale pending pose was not canceled")
	visual.ready[label]=true
	assert(visual:show(group,0))
	local seen=0 for _ in pairs(poses) do seen+=1 end
	gui:SetAttribute("Skin"..skin.."Poses",seen)
	parent:Destroy()
end
gui:SetAttribute("Passed",true)
print("DX RENDER CHECKS PASS: crack-free translucent joins, clipping/clear, classic/XML warm handoffs")
