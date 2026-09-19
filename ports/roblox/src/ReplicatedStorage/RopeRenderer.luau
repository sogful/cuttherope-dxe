--!native
local AssetService=game:GetService("AssetService")
local Drawing=require(script.Parent.RopeDrawing)
local Raster=require(script.Parent.RopeRasterizer)
local Session=require(script.Parent.SessionState)
local renderer={}
renderer.__index=renderer
local width,height=1024,576
local black=Color3.new(0,0,0)

function renderer.new(layer)
	local root=layer:FindFirstAncestorWhichIsA("ScreenGui")
	if root and not root.Enabled then return nil end
	local texture
	local ok,message=pcall(function()
		texture=AssetService:CreateEditableImage({Size=Vector2.new(width,height)})
		if texture then texture:WritePixelsBuffer(Vector2.zero,Vector2.new(1,1),buffer.create(4)) end
	end)
	if not ok or not texture then
		if texture then texture:Destroy() end
		layer:SetAttribute("RopeRenderer","GuiFallback")
		layer:SetAttribute("RopeRendererError",tostring(message))
		return nil
	end
	local image=Instance.new("ImageLabel")
	image.Name,image.BackgroundTransparency,image.ZIndex="RopeSurface",1,require(script.Parent.GameplayLayers).Rope
	image.ImageContent,image.Size,image.Parent=Content.fromObject(texture),UDim2.fromScale(1,1),layer
	layer:SetAttribute("RopeRenderer","ConnectedRaster")
	layer:SetAttribute("RopeRendererError",nil)
	local self=setmetatable({layer=layer,image=image,texture=texture,raster=Raster.new(width,height),width=width,height=height,pixels=width/2560,vertices={},colors={},frames=0},renderer)
	image.Destroying:Connect(function() self.texture:Destroy() end)
	return self
end

function renderer:resize(camera)
	local v=camera.visible or Vector2.new(2560,1440)
	local pixels=1024/math.max(v.X,v.Y)
	local w,h=math.ceil(v.X*pixels-1e-5),math.ceil(v.Y*pixels-1e-5)
	if w~=self.width or h~=self.height then
		-- Allocate first and replace atomically; never display an unloaded asset.
		local replacement=assert(AssetService:CreateEditableImage({Size=Vector2.new(w,h)}),"rope surface allocation")
		local previous=self.texture
		self.texture,self.width,self.height=replacement,w,h
		self.raster=Raster.new(w,h)
		self.image.ImageContent=Content.fromObject(replacement)
		previous:Destroy()
	end
	self.pixels=pixels
end

function renderer:strip(samples,camera,style,halfwidth,outline)
	local previousleft,previousright
	local scale=self.pixels*camera.scale
	local vertices=self.vertices
	local colors=self.colors or {}
	self.colors=colors
	for index=1,#samples-1 do
		local start=camera:screen(samples[index])*self.pixels
		local finish=camera:screen(samples[index+1])*self.pixels
		local delta=finish-start
		if delta.Magnitude>.00001 then
			local normal=Vector2.new(-delta.Y,delta.X).Unit
			local left=previousleft or start+normal*(halfwidth*scale)
			local right=previousright or start-normal*(halfwidth*scale)
			previousleft,previousright=finish+normal*(halfwidth*scale),finish-normal*(halfwidth*scale)
			local alpha=style.alpha*(outline and .4 or 1)
			local extended=start+delta*(alpha==1 and not style.highlighted and 1.02 or 1)
			local endleft,endright=extended+normal*(halfwidth*scale),extended-normal*(halfwidth*scale)
			vertices[1],vertices[2]=left,endleft
			vertices[3],vertices[4]=left-normal*scale,endleft-normal*scale
			vertices[5],vertices[6]=start,finish
			vertices[7],vertices[8]=right+normal*scale,endright+normal*scale
			vertices[9],vertices[10]=right,endright
			local color=outline and black or Drawing.color(index,#samples-1,style)
			local bright=Color3.new(math.min(1,color.R+.15),math.min(1,color.G+.15),math.min(1,color.B+.15))
			colors[1],colors[2],colors[9],colors[10]=black,black,black,black
			colors[3],colors[4],colors[7],colors[8]=bright,bright,bright,bright
			colors[5],colors[6]=color,color
			for vertex=1,8 do
				local aa=(vertex<=2 or vertex>=9) and 0 or alpha
				local ab=(vertex+1<=2 or vertex+1>=9) and 0 or alpha
				local ac=(vertex+2<=2 or vertex+2>=9) and 0 or alpha
				self.raster:triangle(vertices[vertex],vertices[vertex+1],vertices[vertex+2],colors[vertex],colors[vertex+1],colors[vertex+2],aa,ab,ac)
			end
		end
	end
end

function renderer:changed(ropes,camera)
	local previous=self.signature or {} self.signature=previous
	local cursor,changed=0,false
	local function value(next)
		cursor+=1 if previous[cursor]~=next then changed=true previous[cursor]=next end
	end
	value(camera.visible.X) value(camera.visible.Y) value(camera.render.X) value(camera.render.Y) value(camera.scale) value(Session.rope)
	for _,rope in ipairs(ropes) do
		local visible=rope.active and (not rope.cut or rope.remaining>0)
		value(visible)
		if visible then
			value(rope.cut==true) value(rope.cut and rope.remaining or 0) value(rope.pendingCut~=nil)
			value(rope.highlighted==true) value(rope.split or 0) value(rope.hideTailParts==true) value(#rope.points)
			for _,point in ipairs(rope.points) do value(point.X) value(point.Y) end
		end
	end
	if #previous~=cursor then changed=true for index=#previous,cursor+1,-1 do previous[index]=nil end end
	return changed
end

function renderer:draw(ropes,camera)
	local began=os.clock()
	if not self:changed(ropes,camera) then
		self.milliseconds,self.resolveMilliseconds,self.uploadMilliseconds=0,0,0
		self.skipped=(self.skipped or 0)+1
		return
	end
	self:resize(camera)
	self.raster:clear()
	for _,rope in ipairs(ropes) do
		if not rope.cut or rope.remaining>0 then
			for _,path in ipairs(Drawing.paths(rope)) do
				local samples,style=Drawing.samples(path),Drawing.style(path,rope)
				style.highlighted=rope.highlighted
				if style.outline then self:strip(samples,camera,style,7,true) end
				self:strip(samples,camera,style,5,false)
			end
		end
	end
	local resolved=os.clock()
	self.raster:finish()
	local pixels,offset,size=self.raster:region()
	self.resolveMilliseconds=(os.clock()-resolved)*1000
	local upload=os.clock()
	if pixels then self.texture:WritePixelsBuffer(offset,size,pixels) end
	self.uploadBytes=pixels and buffer.len(pixels) or 0
	self.uploadMilliseconds=(os.clock()-upload)*1000
	-- Counteract GameLayer's camera transform; only pixels inside this surface move.
	self.image.Position=UDim2.fromScale(camera.render.X/2560,camera.render.Y/1440)
	self.image.Size=UDim2.fromScale(self.width/self.pixels/2560/camera.scale,self.height/self.pixels/1440/camera.scale)
	self.image:SetAttribute("RasterSize",Vector2.new(self.width,self.height))
	self.frames+=1
	self.milliseconds=(os.clock()-began)*1000
	if self.frames%60==0 then self.layer:SetAttribute("RopeDrawMilliseconds",self.milliseconds) end
end

return renderer
