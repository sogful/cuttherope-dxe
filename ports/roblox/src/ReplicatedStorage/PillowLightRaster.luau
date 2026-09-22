--!native
local AssetService=game:GetService("AssetService")
local Pixels=require(script.Parent.PillowLightPixels)
local size=require(script.Parent.PillowLightData).lightSize
local raster={}
raster.__index=raster

function raster.new(parent)
	local root=parent:FindFirstAncestorWhichIsA("ScreenGui")
	if root and not root.Enabled then return nil end
	local ok,texture=pcall(function() return AssetService:CreateEditableImage({Size=Vector2.new(size,size)}) end)
	if not ok or not texture then return nil end
	local image=Instance.new("ImageLabel")
	image.Name,image.BackgroundTransparency,image.Size="AdditiveLight",1,UDim2.fromScale(1,1)
	image.ImageContent,image.ZIndex,image.Parent=Content.fromObject(texture),parent.ZIndex+1,parent
	image.Destroying:Connect(function() texture:Destroy() end)
	local kernel=Pixels.new()
	return setmetatable({texture=texture,pixels=kernel.output,image=image,kernel=kernel},raster)
end

function raster:update(point,radius,camera)
	debug.profilebegin("DX Pillow light")
	local output=self.kernel:update(point,radius,camera)
	if output then self.texture:WritePixelsBuffer(Vector2.zero,Vector2.new(size,size),output) end
	debug.profileend()
end

return raster
