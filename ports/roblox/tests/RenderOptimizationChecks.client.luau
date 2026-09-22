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
	for frame=1,50 do
		a:clear() b:clear()
		for i=1,(frame%10==0 and 0 or 12) do
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
check("PillowPixelsMatchPreviousShader",function()
	local Current=require(shared.PillowLightPixels)
	local Baseline=require(shared.PillowLightRasterBaseline)
	local size=require(shared.PillowLightData).lightSize
	local current=Current.new()
	local previous={pixels=buffer.create(size*size*4),rows={},texture={WritePixelsBuffer=function() end}}
	local maximum=0
	for _,visible in {Vector2.new(2560,1440),Vector2.new(1920,1440),Vector2.new(3200,1440),Vector2.new(1440,2560)} do
		for _,radius in {75,180,320} do
			for _,point in {Vector2.new(700,300),Vector2.new(-512,1780),Vector2.new(4096,-120)} do
				local camera={visible=visible,scale=.75}
				previous.point=nil
				Baseline.update(previous,point,radius,camera)
				local output=current:update(point,radius,camera)
				assert(output,"changed input must render")
				for offset=0,buffer.len(output)-1 do
					local difference=math.abs(buffer.readu8(output,offset)-buffer.readu8(previous.pixels,offset))
					maximum=math.max(maximum,difference)
				end
				assert(buffer.tostring(output)==buffer.tostring(previous.pixels),"light pixels changed at "..tostring(point))
				task.wait()
			end
		end
	end
	local point,camera=Vector2.new(700,300),{visible=Vector2.new(2560,1440),scale=1}
	assert(current:update(point,180,camera))
	assert(current:update(point,180,camera)==nil)
	assert(current:update(point,181,camera),"radius invalidation")
	assert(current:update(point,181,{visible=Vector2.new(1440,2560),scale=1}),"viewport invalidation")
	assert(current:update(point,181,{visible=Vector2.new(1440,2560),scale=.5}),"zoom invalidation")
	evidence:SetAttribute("MaximumLightByteDifference",maximum)
end)
check("HookRadiusCacheInvalidation",function()
	local Radius=require(shared.HookRadius)
	local parent={AbsoluteSize=Vector2.new(1280,720)}
	local state={parent=parent,definition={anchor=Vector2.new(300,200)},segments={}}
	local writes=0
	local storage={}
	local object=setmetatable({},{
		__index=storage,
		__newindex=function(_,key,value) writes+=1 storage[key]=value end,
	})
	state.segments[1]={object=object,delta=Vector2.new(12,7),offset=Vector2.new(20,30)}
	local function update(alpha,anchor) Radius.update(state,alpha,anchor) end
	update(1)
	local initial=writes
	update(1)
	assert(writes==initial,"unchanged circle rewrote GUI properties")
	local anchor=Vector2.new(400,300)
	update(1,anchor)
	assert(writes>initial and storage.Position==UDim2.fromScale(420/2560,330/1440))
	local before=storage.Size
	parent.AbsoluteSize=Vector2.new(1600,900)
	update(1,anchor)
	assert(storage.Size~=before,"viewport resize stayed cached")
	update(.5,anchor)
	assert(storage.BackgroundTransparency==.5)
	update(0,anchor)
	assert(not storage.Visible)
	initial=writes
	update(0,anchor+Vector2.new(100,100))
	assert(writes==initial,"invisible circle rewrote GUI properties")
	update(1,anchor+Vector2.new(100,100))
	assert(storage.Visible and storage.Position==UDim2.fromScale(520/2560,430/1440))
end)
evidence:SetAttribute("Results",game:GetService("HttpService"):JSONEncode(results))
evidence:SetAttribute("Complete",true)
