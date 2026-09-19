-- ConveyorBelt.BuildVisuals and ConveyorBeltVisual.Draw: raw (not restored)
-- source quads, native 63-unit moving tiles, mirrored corner/rail pieces.
local Frames=require(script.Parent.MechanicalFrames)
local Layers=require(script.Parent.GameplayLayers)
local visuals={}
visuals.__index=visuals
local function frame(parent,name,w,h)
	local v=Instance.new("Frame")
	v.Name,v.BackgroundTransparency,v.BorderSizePixel=name,1,0
	v.AnchorPoint=Vector2.new(.5,.5)
	v.Size=UDim2.fromScale(w/2560,h/1440)
	v.Parent=parent
	return v
end
local function image(parent,name,group,index,x,y,w,h,z)
	local q=Frames[group][index+1]
	local v=Instance.new("ImageLabel")
	v.Name,v.BackgroundTransparency,v.BorderSizePixel=name,1,0
	v.AnchorPoint=Vector2.new(.5,.5)
	v.Image=Frames.pages[q[1]]
	v.ImageRectOffset,v.ImageRectSize=Vector2.new(q[2],q[3]),Vector2.new(q[4],q[5])
	v.Position,v.Size=UDim2.fromScale(x,y),UDim2.fromScale(w,h)
	v.ZIndex,v.Parent=z,parent
	return v
end
function visuals.new(layer,mechanics)
	local self=setmetatable({layer=layer,mechanics=mechanics,objects={}},visuals)
	if #mechanics.objects==0 then return self end
	self.root=frame(layer,"Conveyors",2560,1440)
	self.root.AnchorPoint=Vector2.zero
	self.root.ZIndex=Layers.Conveyor
	for i,b in ipairs(mechanics.objects) do
		local w,h=b.width,b.length
		local root=frame(self.root,"Conveyor"..i,w,h)
		root.Position=UDim2.fromScale((b.point.X+b.c*h*.5)/2560,(b.point.Y-b.s*h*.5)/1440)
		root.Rotation=90-b.angle
		image(root,"Middle","belt",2,.5,.5,(w-10)/w,1,1)
		image(root,"BottomCap","belt",0,.5,1+(18-79*.5)/h,.6,79/h,2)
		image(root,"TopCap","belt",0,.5,(-18+79*.5)/h,.6,79/h,2)
		image(root,"LeftRail","beltx",3,67*.5/w,.5,67/w,(h-36)/h,3)
		image(root,"RightRail","belt",3,1-67*.5/w,.5,67/w,(h-36)/h,3)
		image(root,"BottomRight","belt",1,1-67*.5/w,1+(18-79*.5)/h,67/w,79/h,4)
		image(root,"BottomLeft","beltx",1,67*.5/w,1+(18-79*.5)/h,67/w,79/h,4)
		image(root,"TopLeft","beltxy",1,67*.5/w,(-18+79*.5)/h,67/w,79/h,4)
		image(root,"TopRight","belty",1,1-67*.5/w,(-18+79*.5)/h,67/w,79/h,4)
		local v={root=root,belt=b,tiles={}}
		for j=1,math.ceil(h/63)+1 do
			local tile=image(root,"Plate"..j,"belt",4,.5,0,.8,63/h,5)
			if not b.manual then
				local arrow=image(tile,"Direction","belt",5,.5,.5,66/235,35/63,1)
				arrow.Rotation=b.velocity>0 and 0 or 180
			end
			v.tiles[j]=tile
		end
		image(root,"BottomHighlight","belt",6,.5,1-12/h,.8,24/h,6)
		image(root,"TopHighlight","belty",6,.5,12/h,.8,24/h,6)
		self.objects[i]=v
	end
	self:update()
	return self
end
function visuals:update()
	if not self.root then return end
	local order=table.clone(self.mechanics.objects)
	table.sort(order,function(a,b)
		if a.manual~=b.manual then return a.manual end
		if a.manual and a.activation~=b.activation then return a.activation<b.activation end
		return a.index<b.index
	end)
	for rank,b in ipairs(order) do
		local v=self.objects[b.index]
		v.root.ZIndex=rank
		local y,used=0,0
		local first=b.offset%63
		while y<b.length do
			used+=1
			local height=math.min(b.length-y,used==1 and first>0 and first or 63)
			local tile=v.tiles[used]
			tile.Visible=true
			tile.Position=UDim2.fromScale(.5,(y+height*.5)/b.length)
			tile.Size=UDim2.fromScale(.8,height/b.length)
			y+=height
		end
		for i=used+1,#v.tiles do v.tiles[i].Visible=false end
		v.root:SetAttribute("Manual",b.manual)
		v.root:SetAttribute("Offset",b.offset)
		v.root:SetAttribute("BoundItems",#b.items)
		v.root:SetAttribute("Wraps",b.wraps)
	end
	self.layer:SetAttribute("ConveyorWraps",self.mechanics.wraps)
	self.layer:SetAttribute("ConveyorHandoffs",self.mechanics.handoffs)
	self.layer:SetAttribute("DraggingConveyor",self.mechanics.held and self.mechanics.held.index or 0)
end
return visuals
