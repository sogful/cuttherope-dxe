local Frames=require(script.Parent.HazardFrames)
local Layers=require(script.Parent.GameplayLayers)
local effect={}
effect.__index=effect

function effect.image(parent,name,quad,point)
	local image=Instance.new("ImageLabel")
	image.Name,image.BackgroundTransparency,image.AnchorPoint=name,1,Vector2.new(.5,.5)
	image.Image,image.ImageRectOffset=Frames.pages[quad[1]],Vector2.new(quad[2],quad[3])
	image.ImageRectSize=Vector2.new(quad[4],quad[5])
	-- Spikes and particle quads use trimmed bounds, not restored atlas canvases.
	image.Size=UDim2.fromScale(quad[4]/2560,quad[5]/1440)
	image.Position,image.ZIndex,image.Parent=UDim2.fromScale(point.X/2560,point.Y/1440),Layers.Effect,parent
	return image
end

function effect.new(parent,point,skin,random,inverted)
	local self=setmetatable({particles={},time=0,parent=parent,gravity=inverted and -500 or 500},effect)
	random=random or Random.new()
	for index=1,5 do
		local angle,speed=math.rad(random:NextNumber(-140,-40)),random:NextNumber(80,220)
		if inverted then angle+=math.pi end
		local quadindex=random:NextInteger(1,5)
		local image=effect.image(parent,"CandyFragment"..index,Frames["candy"..skin][quadindex],point)
		image:SetAttribute("SourceQuad",quadindex+2)
		table.insert(self.particles,{image=image,point=point,velocity=Vector2.new(math.cos(angle),math.sin(angle))*speed,
			radial=random:NextNumber(-1,1),tangent=random:NextNumber(-1,1),rotation=random:NextNumber(-600,600)})
	end
	return self
end

function effect:update(delta)
	self.time+=delta
	for _,particle in ipairs(self.particles) do
		local radial=particle.point.Magnitude>0 and particle.point.Unit or Vector2.zero
		local tangent=Vector2.new(-radial.Y,radial.X)
		particle.velocity+=(Vector2.new(0,self.gravity)+radial*particle.radial+tangent*particle.tangent)*delta
		particle.point+=particle.velocity*delta
		particle.image.Position=UDim2.fromScale(particle.point.X/2560,particle.point.Y/1440)
		particle.image.Rotation+=particle.rotation*delta
		particle.image.Visible=self.time<3
	end
	self.parent:SetAttribute("CandyBreakTime",self.time)
end

return effect
