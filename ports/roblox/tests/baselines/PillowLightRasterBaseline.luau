--!native
-- Approximate SRC_ALPHA,ONE against the sampled Pillow background. Roblox GUI
-- has no additive blending. Bound straight-alpha coverage to retain foreground
-- ropes/Om Nom instead of replacing them with an opaque, backdrop-colored disc.
local AssetService=game:GetService("AssetService")
local Data=require(script.Parent.PillowLightData)
local function decode(hex)
	return buffer.fromstring((hex:gsub("..",function(pair) return string.char(tonumber(pair,16)) end)))
end
local light,back=decode(Data.light),decode(Data.background)
local raster={}
raster.__index=raster
local n,bw,bh=Data.lightSize,Data.backgroundWidth,Data.backgroundHeight
local function sample(x,y,c)
	x,y=x%bw,y%bh
	local ix,iy=math.floor(x),math.floor(y)
	local fx,fy=x-ix,y-iy
	local a=buffer.readu8(back,(iy*bw+ix)*3+c)
	local b=buffer.readu8(back,(iy*bw+(ix+1)%bw)*3+c)
	local d=buffer.readu8(back,(((iy+1)%bh)*bw+ix)*3+c)
	local e=buffer.readu8(back,(((iy+1)%bh)*bw+(ix+1)%bw)*3+c)
	return ((a+(b-a)*fx)*(1-fy)+(d+(e-d)*fx)*fy)/255
end
function raster.new(parent)
	local root=parent:FindFirstAncestorWhichIsA("ScreenGui")
	if root and not root.Enabled then return nil end
	local ok,texture=pcall(function() return AssetService:CreateEditableImage({Size=Vector2.new(n,n)}) end)
	if not ok or not texture then return nil end
	local image=Instance.new("ImageLabel")
	image.Name,image.BackgroundTransparency,image.Size="AdditiveLight",1,UDim2.fromScale(1,1)
	image.ImageContent,image.ZIndex,image.Parent=Content.fromObject(texture),parent.ZIndex+1,parent
	image.Destroying:Connect(function() texture:Destroy() end)
	return setmetatable({texture=texture,pixels=buffer.create(n*n*4),image=image,rows={}},raster)
end
function raster:update(point,radius,camera)
	local v=camera.visible or Vector2.new(2560,1440)
	local scale=math.max(v.X/camera.scale/2048,v.Y/camera.scale/1152)
	if self.point and (self.point-point).Magnitude<.5 and self.scale==scale then return end
	self.point,self.scale=point,scale
	local width,height=radius*3,radius*3*425/405
	for y=0,n-1 do for x=0,n-1 do
		local i=(y*n+x)*4
		local strength=buffer.readu8(light,i+3)/255*.6
		local worldX=point.X+((x+.5)/n-.5)*width
		local worldY=point.Y+((y+.5)/n-.5)*height
		local u=((worldX-1280)/scale+1024)/2048*bw-.5
		local v0=((worldY-720)/scale+576)/1152*bh-.5
		local alpha=0
		for c=0,2 do
			local b=sample(u,v0,c)
			local added=math.min(1-b,buffer.readu8(light,i+c)/255*strength)
			self.rows[c*2+1],self.rows[c*2+2]=b,added
			alpha=math.max(alpha,added/math.max(.0001,1-b))
		end
		alpha=math.min(alpha,.38)
		for c=0,2 do
			local value=alpha>0 and self.rows[c*2+1]+self.rows[c*2+2]/alpha or 0
			buffer.writeu8(self.pixels,i+c,math.clamp(math.floor(value*255+.5),0,255))
		end
		buffer.writeu8(self.pixels,i+3,math.clamp(math.floor(alpha*255+.5),0,255))
	end end
	self.texture:WritePixelsBuffer(Vector2.zero,Vector2.new(n,n),self.pixels)
end
return raster
