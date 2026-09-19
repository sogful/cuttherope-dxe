local shared=game.ReplicatedStorage.CutTheRope.Shared
local Renderer,Physics,Camera,Levels=require(shared.RopeRenderer),require(shared.DxPhysics),require(shared.GameplayCamera),require(shared.LevelData)
local RunService=game:GetService("RunService")
local gui=Instance.new("ScreenGui")
gui.Name,gui.DisplayOrder,gui.IgnoreGuiInset,gui.Parent="DxLiveRopeChecks",-950,true,game.Players.LocalPlayer.PlayerGui
local board=Instance.new("Frame") board.Size,board.BackgroundTransparency,board.Parent=UDim2.fromScale(1,1),1,gui
local layer=Instance.new("Frame") layer.Size,layer.BackgroundTransparency,layer.Parent=UDim2.fromScale(1,1),1,board
local total,uploads,resolves,count,maximum=0,0,0,0,0
local values={}
for _,number in ipairs({7,15,22,23,25}) do
	local sim,cam=Physics.new(Levels.get(number)),Camera.new(Levels.get(number))
	local r=assert(Renderer.new(layer),"EditableImage full write is still blocked")
	for frame=1,45 do
		sim:update(1/60)
		cam:tick(sim.candy.pos)
		layer.Position=UDim2.fromScale(-cam.render.X*cam.scale/2560,-cam.render.Y*cam.scale/1440)
		layer.Size=UDim2.fromScale(cam.scale,cam.scale)
		r:draw(sim.ropes,cam)
		count+=1 total+=r.milliseconds uploads+=r.uploadMilliseconds resolves+=r.resolveMilliseconds
		maximum=math.max(maximum,r.milliseconds) table.insert(values,r.milliseconds)
		RunService.RenderStepped:Wait()
		assert((r.image.AbsolutePosition-board.AbsolutePosition).Magnitude<1,"Scrolling detached rope surface")
		assert((r.image.AbsoluteSize-board.AbsoluteSize).Magnitude<1,"Camera scaled surface twice")
	end
	-- Fresh canvas after every cut fragment expires: no stale rope pixels.
	sim.disableCapture=true
	for _,rope in ipairs(sim.ropes) do if rope.active then sim:sever(rope,1) end end
	for _=1,150 do sim:update(1/60) end
	r:draw(sim.ropes,cam)
	local output=r.raster.output
	for offset=3,buffer.len(output)-1,4 do assert(buffer.readu8(output,offset)==0,"Stale cut pixels") end
	r.image:Destroy()
	assert(not layer:FindFirstChild("RopeSurface"))
end
table.sort(values)
gui:SetAttribute("MeanDrawMs",total/count)
gui:SetAttribute("MeanUploadMs",uploads/count)
gui:SetAttribute("MeanResolveMs",resolves/count)
gui:SetAttribute("MaxDrawMs",maximum)
gui:SetAttribute("P95DrawMs",values[math.ceil(count*.95)])
gui:SetAttribute("Passed",true)
board:Destroy()
-- Observe the real gameplay surface too; this diagnostic is disabled for handoff.
local original=Renderer.draw
local live={}
Renderer.draw=function(self,...)
	original(self,...)
	if self.layer.Name~="GameLayer" then return end
	table.insert(live,self.milliseconds)
	if #live==240 then
		Renderer.draw=original
		table.sort(live)
		local sum=0 for _,value in ipairs(live) do sum+=value end
		gui:SetAttribute("LiveMeanDrawMs",sum/#live)
		gui:SetAttribute("LiveP95DrawMs",live[228])
	end
end
print("DX LIVE ROPE CHECKS PASS: actual image writes, five maps, scroll transforms, cut clearing, image disposal")
