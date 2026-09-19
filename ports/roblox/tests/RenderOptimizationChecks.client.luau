if not game:GetService("RunService"):IsStudio() then return end
local shared=game.ReplicatedStorage.CutTheRope.Shared
local Drawing=require(shared.RopeDrawing)
local Previous=require(shared.RopeDrawingBaseline)
local Raster=require(shared.RopeRasterizer)
local OldRaster=require(shared.RopeRasterizerBaseline)
local evidence=Instance.new("Folder") evidence.Name,evidence.Parent="DxRenderOptimizationChecks",game.Players.LocalPlayer.PlayerGui
local results={}
local function check(name,fn)
	local ok,message=pcall(fn) results[name]=ok and "PASS" or tostring(message)
	if not ok then warn("DX RENDER CHECK",name,message) end
end
check("SameBezierCurveAndSampleCount",function()
	local random=Random.new(728) local maximum=0
	for _,count in {3,5,10,20,40,80} do
		local points={}
		for i=1,count do points[i]=Vector2.new(random:NextNumber(-1000,4000),random:NextNumber(-1000,3000)) end
		for pass=1,3 do
			local a,b=Drawing.samples(points),Previous.samples(points) assert(#a==#b)
			for i=1,#a do maximum=math.max(maximum,(a[i]-b[i]).Magnitude) end
			points[2]+=Vector2.new(2.5,-.7)
		end
		task.wait()
	end
	evidence:SetAttribute("MaximumCurveDifference",maximum)
	assert(maximum<.025,"Bezier changed by "..maximum)
end)
check("DirtyRasterMatchesEveryPixelAndClearsOldRopes",function()
	local random=Random.new(83) local a,b=Raster.new(128,96),OldRaster.new(128,96)
	local composite=buffer.create(128*96*4)
	for frame=1,10 do
		a:clear() b:clear()
		for i=1,(frame==10 and 0 or 12) do
			local p=Vector2.new(random:NextNumber(-20,140),random:NextNumber(-20,110))
			local q=p+Vector2.new(random:NextNumber(-40,40),random:NextNumber(-40,40))
			local r=q+Vector2.new(random:NextNumber(-8,8),random:NextNumber(-8,8))
			local ca,cb,cc=Color3.new(.7,.3,.1),Color3.new(.5,.4,.2),Color3.new(.2,.1,.1)
			a:triangle(p,q,r,ca,cb,cc,1,.5,0) b:triangle(p,q,r,ca,cb,cc,1,.5,0)
		end
		local current,expected=a:finish(),b:finish()
		assert(buffer.tostring(current)==buffer.tostring(expected),"raster frame "..frame)
		local region,offset,size=a:region()
		if region then for y=0,size.Y-1 do buffer.copy(composite,((offset.Y+y)*128+offset.X)*4,region,y*size.X*4,size.X*4) end end
		assert(buffer.tostring(composite)==buffer.tostring(expected),"upload frame "..frame)
		task.wait()
	end
end)
evidence:SetAttribute("Results",game:GetService("HttpService"):JSONEncode(results))
evidence:SetAttribute("Complete",true)
