local background={}
local Frames=require(script.Parent.BoxFrames)
local SplitFrames=require(script.Parent.SplitFrames)
local WheelFrames=require(script.Parent.WheelFrames)
local AdvancedFrames=require(script.Parent.AdvancedFrames)
local DiscFrames=require(script.Parent.DiscFrames)
local GhostFrames=require(script.Parent.GhostFrames)
local SteamFrames=require(script.Parent.SteamFrames)
local LanternFrames=require(script.Parent.LanternFrames)
local CheeseFrames=require(script.Parent.CheeseFrames)
local PillowFrames=require(script.Parent.PillowFrames)
local MechanicalFrames=require(script.Parent.MechanicalFrames)
local Atlas=require(script.Parent.AtlasSprite)
background.__index=background
background.seam="rbxassetid://76373038554923"

function background.new(image)
	local holder=Instance.new("Frame")
	holder.Name,holder.BackgroundTransparency,holder.Size="ScrollingCardboard",1,UDim2.fromScale(1,1)
	holder.ZIndex,holder.Parent=image.ZIndex,image.Parent
	image.Parent=holder
	local self=setmetatable({holder=holder,tiles={image},seams={},earths={},definition=Frames.backgrounds[1]},background)
	for i=2,4 do
		local tile=image:Clone()
		tile.Name,tile.Parent="CardboardSection"..i,holder
		self.tiles[i]=tile
	end
	for i=1,4 do
		local earth=Instance.new("Frame")
		earth.Name,earth.BackgroundTransparency,earth.AnchorPoint="Earth"..i,1,Vector2.new(.5,.5)
		earth.ZIndex,earth.Visible,earth.Parent=holder.ZIndex+2,false,holder
		local atlas=Atlas.new(earth,{"earth"},WheelFrames,true)
		atlas:show("earth",0)
		self.earths[i]=earth
	end
	return self
end

function background:setPack(pack)
	self.definition=assert(Frames.backgrounds[pack] or SplitFrames.backgrounds[pack] or WheelFrames.backgrounds[pack] or AdvancedFrames.backgrounds[pack] or DiscFrames.backgrounds[pack] or GhostFrames.backgrounds[pack] or SteamFrames.backgrounds[pack] or LanternFrames.backgrounds[pack] or CheeseFrames.backgrounds[pack] or PillowFrames.backgrounds[pack] or MechanicalFrames.backgrounds[pack],"Missing box background")
	self.holder.Name="BoxBackground"..pack
	for _,tile in ipairs(self.tiles) do tile.Image=self.definition.image end
	for _,seam in ipairs(self.seams) do seam.Image=self.definition.seam or "" end
end

function background:update(camera,physics)
	local definition=self.definition
	local v=camera.visible or Vector2.new(2560,1440)
	local sourcewidth,sourceheight=definition.width,definition.height
	local scale=math.max(v.X/camera.scale/sourcewidth,v.Y/camera.scale/sourceheight)
	local origin=Vector2.new(1280/scale-sourcewidth*.5,720/scale-sourceheight*.5)
	local view=camera.render/scale
	local firstx=math.floor((view.X-origin.X)/sourcewidth)
	local firsty=math.floor((view.Y-origin.Y)/sourceheight)
	local factor=scale*camera.scale
	local index=0
	for y=0,1 do for x=0,1 do
		index+=1
		local tile=self.tiles[index]
		local world=origin+Vector2.new((firstx+x)*sourcewidth,(firsty+y)*sourceheight)
		local point=(world-view)*factor
		tile.Position=UDim2.fromScale(point.X/v.X,point.Y/v.Y)
		tile.Size=UDim2.fromScale(sourcewidth*factor/v.X,sourceheight*factor/v.Y)
		tile.ScaleType=Enum.ScaleType.Stretch
		local earth=self.earths[index]
		earth.Visible=definition.earth~=nil
		if definition.earth then
			local center=(world+definition.earth-view)*factor
			earth.Position=UDim2.fromScale(center.X/v.X,center.Y/v.Y)
			earth.Size=UDim2.fromScale(492*factor/v.X,494*factor/v.Y)
			earth.Rotation=physics and physics:earthRotation() or 0
		end
	end end
	local count=definition.seam and math.max(0,math.ceil(camera.size.Y/1440-.001)-1) or 0
	local used=0
	for seam=0,count-1 do for column=firstx,firstx+1 do
		used+=1
		local image=self.seams[used]
		if not image then
			image=Instance.new("ImageLabel")
			image.Name,image.BackgroundTransparency,image.Image="BoxSeam"..used,1,definition.seam
			image.ScaleType,image.ZIndex,image.Parent=Enum.ScaleType.Stretch,self.holder.ZIndex+1,self.holder
			self.seams[used]=image
		end
		-- PackConfig bgr_01_p2 at1120, repeated at the1440 P1 cadence.
		local point=(origin+Vector2.new(column*sourcewidth,definition.seamY+seam*sourceheight)-view)*factor
		image.Position=UDim2.fromScale(point.X/v.X,point.Y/v.Y)
		image.Size=UDim2.fromScale(definition.seamWidth*factor/v.X,definition.seamHeight*factor/v.Y)
		image.Visible=true
	end end
	for i=used+1,#self.seams do self.seams[i].Visible=false end
	self.holder:SetAttribute("CameraY",camera.render.Y)
	self.holder:SetAttribute("SeamCount",count)
end

return background
