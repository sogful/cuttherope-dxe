local Atlas=require(script.Parent.AtlasSprite)
local Frames=require(script.Parent.CheeseFrames)
local Layers=require(script.Parent.GameplayLayers)
local Math=require(script.Parent.DxMath)
local visuals={}
visuals.__index=visuals

local function sprite(parent,name,z,frames)
	local root=Instance.new("Frame")
	root.Name,root.BackgroundTransparency,root.AnchorPoint=name,1,Vector2.new(.5,.5)
	root.ZIndex,root.Parent=z,parent
	return {root=root,atlas=Atlas.new(root,{"mouse"},Frames,{mouse=frames})}
end
local function show(visual,quad,point,angle)
	local q=Frames.mouse[quad+1]
	visual.root.Size=UDim2.fromScale(q[8]/2560,q[9]/1440)
	visual.root.Position=UDim2.fromScale(point.X/2560,point.Y/1440)
	visual.root.Rotation=angle or 0
	visual.atlas:show("mouse",quad)
end

function visuals.new(layer,mechanics)
	local self=setmetatable({mechanics=mechanics,holes={}},visuals)
	if #mechanics.objects==0 then return self end
	for i,o in ipairs(mechanics.objects) do
		local hole=sprite(layer,"MouseHole"..i,Layers.MouseHole,{0})
		show(hole,0,o.point)
		table.insert(self.holes,hole)
	end
	self.body=sprite(layer,"MouseBody",Layers.Mouse,{1,2,3,4,14,15,16,17,18,19,21,24,26,28})
	self.eyes=sprite(layer,"MouseEyes",Layers.Mouse+1,{5,6,7,8,9,10,11,12,13})
	self:update()
	return self
end

function visuals:update()
	local o=self.mechanics.active
	if not o then return end
	local offset=Vector2.zero
	if o.bounce then
		local out=Math.rotate(Vector2.new(0,-142*.15*.45),Math.radians(o.angle))
		local back=Math.rotate(Vector2.new(0,142*.15*.4),Math.radians(o.angle))
		out=Vector2.new(math.modf(out.X),math.modf(out.Y))
		back=Vector2.new(math.modf(back.X),math.modf(back.Y))
		local t=o.bounce/.05
		if t<1 then offset=out*t elseif t<2 then offset=out+(back-out)*(t-1) else offset=back*(3-t) end
	end
	self.body.root.Visible=o.phase~="hidden"
	show(self.body,o.quad,o.point+offset,o.angle)
	self.eyes.root.Visible=o.eyes~=nil and o.phase~="hidden"
	if o.eyes then show(self.eyes,5+math.min(8,math.floor(o.eyes/.05)),o.point+offset,o.angle) end
	self.body.root:SetAttribute("MouseIndex",o.index)
	self.body.root:SetAttribute("MouseActive",o.active)
	self.body.root:SetAttribute("MousePhase",o.phase)
	self.body.root:SetAttribute("MouseHasCandy",o.carry~=nil)
end

return visuals
