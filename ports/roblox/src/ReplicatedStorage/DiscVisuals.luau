-- RotatedCircle.Draw: face/highlights stay upright; sticker/handles rotate.
local Frames=require(script.Parent.DiscFrames)
local Atlas=require(script.Parent.AtlasSprite)
local Layers=require(script.Parent.GameplayLayers)
local GhostFrames=require(script.Parent.GhostFrames)
local visuals={}
visuals.__index=visuals
local function frame(parent,name,z)
	local item=Instance.new("Frame")
	item.Name,item.BackgroundTransparency,item.Size=name,1,UDim2.fromScale(1,1)
	item.ZIndex,item.Parent=z,parent
	return item
end
local function pose(item,point,size,angle)
	item.AnchorPoint=Vector2.new(.5,.5)
	item.Position=UDim2.fromScale(point.X/2560,point.Y/1440)
	item.Size=UDim2.fromScale(size.X/2560,size.Y/1440)
	item.Rotation=angle or 0
end
local function sprite(parent,name,group,index,z)
	local holder=frame(parent,name,z)
	local atlas=Atlas.new(holder,{group},Frames,{[group]={index}})
	atlas:show(group,index)
	return {frame=holder,atlas=atlas,quad=Frames[group][index+1]}
end
local function place(visual,point,scale,angle)
	local q=visual.quad
	pose(visual.frame,point,Vector2.new(q[8],q[9])*scale,angle)
end
local function rotated(offset,angle)
	local a=math.rad(angle)
	return Vector2.new(offset.X*math.cos(a)-offset.Y*math.sin(a),offset.X*math.sin(a)+offset.Y*math.cos(a))
end
local function arc(parent,name,center,radius,start,finish,width,alpha,z,fade)
	local root=frame(parent,name,z)
	fade=fade or 1
	for i=1,80 do
		local a=start+(finish-start)*(i-1)/80
		local b=start+(finish-start)*i/80
		local p=center+Vector2.new(math.cos(a),math.sin(a))*(radius-width*.5)
		local q=center+Vector2.new(math.cos(b),math.sin(b))*(radius-width*.5)
		local line=frame(root,"Arc"..i,z)
		line.BackgroundColor3,line.BackgroundTransparency,line.BorderSizePixel=Color3.new(1,1,1),1-alpha,0
		pose(line,(p+q)*.5,Vector2.new((q-p).Magnitude+.35,width+2*fade),math.deg(math.atan2(q.Y-p.Y,q.X-p.X)))
		local gradient=Instance.new("UIGradient")
		local edge=fade/(width+2*fade)
		gradient.Rotation=90
		gradient.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(edge,0),NumberSequenceKeypoint.new(1-edge,0),NumberSequenceKeypoint.new(1,1)})
		gradient.Parent=line
	end
	return root
end
function visuals.new(layer,mechanics)
	local self=setmetatable({root=frame(layer,"RotatingDiscs",Layers.Disc),mechanics=mechanics,items={},spares={}},visuals)
	-- Stage duplicate art during level loading, not when overlapping discs reorder.
	for _,d in ipairs(mechanics.objects) do
		local placeholder=table.clone(d)
		placeholder.copy=true
		local item=self:create(placeholder)
		self.items[placeholder]=nil
		item.root.Visible=false
		self.spares[d.index]=item
	end
	return self
end
function visuals:create(d)
	local root=frame(self.root,(d.copy and "DiscCopy" or "Disc")..d.index,1)
	local base=d.size/167
	local stickerScale,controllerScale=math.max(base,.4),math.max(base,.75)
	local item={root=root,face={},sticker={},idle={},active={},highlights={},contours={}}
	local function add(name,group,index,z) return sprite(root,name,group,index,z) end
	item.ring=arc(root,"ActiveRing",d.point,d.radius+9*controllerScale,0,math.pi*2,12*controllerScale,1,1,5)
	for index=0,0 do
		local s=add("Face"..index,"face",index,2)
		pose(s.frame,d.point,Vector2.new(1066,1066)*base)
		table.insert(item.face,s)
	end
	item.highlights[1]=add("HighlightLeft","highlight",0,4)
	item.highlights[2]=add("HighlightRight","highlightMirror",0,4)
	place(item.highlights[1],d.point+Vector2.new(-267*base,248.5*base),base)
	place(item.highlights[2],d.point+Vector2.new(267*base,248.5*base),base)
	item.label=Instance.new("ImageLabel")
	item.label.Name,item.label.BackgroundTransparency,item.label.Image="ContinuousSticker",1,GhostFrames.discSticker
	item.label.ZIndex,item.label.Parent=5,root
	for index=1,2 do
		item.active[index]=add("ActiveHandle"..index,"active",0,6)
		item.idle[index]=add("Handle"..index,"idle",0,7)
	end
	item.center=add("Center","center",0,8)
	place(item.center,d.point,1-(1-stickerScale)*.5)
	item.base,item.stickerScale,item.controllerScale=base,stickerScale,controllerScale
	self.items[d]=item
	return item
end
function visuals:update()
	local mechanics=self.mechanics
	local alive={}
	for index,d in ipairs(mechanics.order) do
		alive[d]=true
		local item=self.items[d]
		if not item and d.copy and self.spares[d.index] then
			item=self.spares[d.index]
			self.spares[d.index]=nil
			self.items[d]=item
		end
		item=item or self:create(d)
		item.root.Visible=true
		item.root.ZIndex=index
		item.root:SetAttribute("Angle",d.angle)
		item.root:SetAttribute("Active",mechanics.held==d)
		item.root:SetAttribute("HandleLeftX",d.left.X) item.root:SetAttribute("HandleLeftY",d.left.Y)
		item.root:SetAttribute("HandleRightX",d.right.X) item.root:SetAttribute("HandleRightY",d.right.Y)
		item.root:SetAttribute("Radius",d.radius)
		item.ring.Visible=not d.copy and (d.activeLeft or d.activeRight or false)
		local transparency=d.copy and 0 or 1-math.clamp(d.fade/.2,0,1)
		if item.ringAlpha~=transparency then
			for _,line in ipairs(item.ring:GetChildren()) do line.BackgroundTransparency=transparency end
			item.ringAlpha=transparency
		end
		for _,s in ipairs(item.face) do s.atlas:fade(transparency) end
		for _,s in ipairs(item.highlights) do s.atlas:fade(transparency) end
		local controllerOffset=d.radius-(67.5-.089999996*d.size)+(1-item.controllerScale)*92
		pose(item.label,d.point+rotated(Vector2.new(-.5,0),d.angle),Vector2.new(290,288)*item.stickerScale,d.angle)
		for side=1,2 do
			local sign=side==1 and -1 or 1
			local handlePoint=d.point+rotated(Vector2.new(sign*controllerOffset,0),d.angle)
			local handleAngle=d.angle-sign*90
			place(item.idle[side],handlePoint+rotated(Vector2.new(0,-sign*.5*item.controllerScale),d.angle),item.controllerScale,handleAngle)
			place(item.active[side],handlePoint,item.controllerScale,handleAngle)
			item.idle[side].frame.Visible=not d.copy and (side==2 or not d.oneHandle)
			item.idle[side].atlas:fade(transparency)
			item.active[side].frame.Visible=not d.copy and (side==1 and d.activeLeft or side==2 and d.activeRight or false)
		end
		local used={}
		for j=1,index-1 do
			local other=mechanics.order[j]
			local distance=(d.point-other.point).Magnitude
			if mechanics:sharesAny(other) and distance>0 and distance<d.radius+other.radius and d.radius<distance+other.radius then
				used[other]=true
				local contour=item.contours[other]
				if not contour then
					local intersection=(d.radius*d.radius-other.radius*other.radius+distance*distance)/(2*distance)
					local offset=math.acos(math.clamp((distance-intersection)/other.radius,-1,1))
					local angle=math.atan2(d.point.Y-other.point.Y,d.point.X-other.point.X)
					contour=arc(item.root,"OverlapContour",other.point,other.radius,angle-offset,angle+offset,21*(other.size/167)*.5,.2,3)
					item.contours[other]=contour
				end
				contour.Visible=true
			end
		end
		for other,contour in pairs(item.contours) do
			if not table.find(mechanics.order,other) then
				contour:Destroy() item.contours[other]=nil
			elseif not used[other] then contour.Visible=false end
		end
	end
	for d,item in pairs(self.items) do if not alive[d] then
		item.root.Visible=false
		if not self.spares[d.index] then self.spares[d.index]=item else item.root:Destroy() end
		self.items[d]=nil
	end end
end
return visuals
