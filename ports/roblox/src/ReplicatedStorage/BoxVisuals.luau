local Frames=require(script.Parent.BoxFrames)
local Atlas=require(script.Parent.AtlasSprite)
local Mechanics=require(script.Parent.BoxMechanics)
local Layers=require(script.Parent.GameplayLayers)
local SplitFrames=require(script.Parent.SplitFrames)
local WheelFrames=require(script.Parent.WheelFrames)
local visuals={}
visuals.__index=visuals

local function at(object,point)
	object.Position=UDim2.fromScale(point.X/2560,point.Y/1440)
end
local function holder(parent,name,size,z)
	local frame=Instance.new("Frame")
	frame.Name,frame.BackgroundTransparency,frame.AnchorPoint=name,1,Vector2.new(.5,.5)
	frame.Size,frame.ZIndex,frame.Parent=UDim2.fromScale(size.X/2560,size.Y/1440),z,parent
	return frame
end
local function sprite(parent,name,group,index,scale,z,library)
	library=library or Frames
	local q=library[group][index+1]
	local frame=holder(parent,name,Vector2.new(q[8],q[9])*(scale or 1),z or 8)
	local atlas=Atlas.new(frame,{group},library,true)
	atlas:show(group,index)
	return {frame=frame,atlas=atlas}
end
local function crop(parent,name,q,x,width)
	local image=Instance.new("ImageLabel")
	image.Name,image.BackgroundTransparency,image.Image=name,1,Frames.pages[q[1]]
	image.ImageRectOffset,image.ImageRectSize=Vector2.new(q[2],q[3]),Vector2.new(q[4],q[5])
	image.Position,image.Size=UDim2.fromScale(x,0),UDim2.fromScale(width,1)
	image.ZIndex,image.Parent=parent.ZIndex,parent
	return image
end

function visuals.new(layer,physics,pack)
	local self=setmetatable({layer=layer,physics=physics,pumps={},hats={},spiders={},rails={},particles={},bouncers={},wheels={},switches={}},visuals)
	for index,point in ipairs(physics.mechanics.gravityButtons) do
		local visual=sprite(layer,"GravitySwitch"..index,"gravity",0,1,Layers.GravitySwitch,WheelFrames)
		at(visual.frame,point)
		self.switches[index]=visual
	end
	for index,object in ipairs(physics.bouncers.objects) do
		local visual=sprite(layer,"Bouncer"..index,"bouncer",(object.size-1)*5,1,Layers.Bouncer,SplitFrames)
		self.bouncers[index]=visual
	end
	for index,pump in ipairs(physics.mechanics.pumps) do
		local visual=sprite(layer,"Pump"..index,"pump",0,1,Layers.Pump)
		at(visual.frame,pump.point)
		visual.frame.Rotation=pump.angle
		self.pumps[index]=visual
	end
	for index,hat in ipairs(physics.mechanics.hats) do
		local pivot=holder(layer,"HatPivot"..index,Vector2.new(431,431)*.7,Layers.Hat)
		local visual=sprite(pivot,"HatArt","hat",math.max(0,hat.group)%2,1,10)
		visual.frame.Size=UDim2.fromScale(1,1)
		-- Integer half-extents give pivot y=84.5; GameScene.Draw shifts the
		-- hat up 85 before drawing it, so its final world pivot is y-.5.
		visual.frame.Position=UDim2.fromScale(.5+.5/431,.5+131/431)
		local flash=sprite(pivot,"HatFlash","hat",2,1,11)
		flash.frame.Size,flash.frame.Position=UDim2.fromScale(1,1),UDim2.fromScale(.5+.5/431,.5-30/431)
		flash.frame.Visible=false
		self.hats[index]={pivot=pivot,visual=visual,flash=flash}
	end
	for index,spider in pairs(physics.mechanics.spiders) do
		self.spiders[index]=sprite(layer,"Spider"..index,"spider",0,1,Layers.Spider)
	end
	for index,rope in ipairs(physics.ropes) do
		if rope.wheel then
			local parts={}
			for quad,name in ipairs({"Base","Arm","Highlight","Indicator"}) do
				parts[quad]=sprite(layer,"Wheel"..index..name,"wheel",quad-1,1,quad==1 and Layers.WheelBase or Layers.WheelArm,WheelFrames)
			end
			self.wheels[index]=parts
		end
		local rail=rope.definition.rail
		if rail then
			local length=rail.length+142
			local track=holder(layer,"HookRail"..index,Vector2.new(length,Frames.rail[1][5]),Layers.HookBack)
			local offset=rail.length*.5-rail.offset-3
			at(track,rope.definition.anchor+(rail.vertical and Vector2.new(0,offset) or Vector2.new(offset,0)))
			track.Rotation=rail.vertical and 90 or 0
			local left,right=Frames.rail[1][4],Frames.rail[2][4]
			crop(track,"LeftCap",Frames.rail[1],0,left/length)
			-- HorizontallyTiledImage.Draw tiles quad 8 at its native width. The
			-- atlas edge extrusion prevents transparent filtering seams; a one
			-- source-pixel overlap also covers fractional GUI raster boundaries.
			local middle=length-left-right
			local tile=Frames.rail[3]
			local cursor=0
			while cursor<middle do
				local width=math.min(tile[4],middle-cursor)
				local part=table.clone(tile)
				part[2],part[4]=tile[2]-1,width+2
				crop(track,"CenterRail"..cursor,part,(left+cursor-1)/length,(width+2)/length)
				cursor+=width
			end
			crop(track,"RightCap",Frames.rail[2],1-right/length,right/length)
			local hook=sprite(layer,"RailHook"..index,"rail",4,1,Layers.HookFront)
			local glow=sprite(layer,"RailHookHighlight"..index,"rail",3,1,Layers.HookHighlight)
			hook.frame.Rotation,glow.frame.Rotation=track.Rotation,track.Rotation
			self.rails[index]={hook=hook,glow=glow}
		end
	end
	return self
end

function visuals:emit(pump)
	local angle=math.rad(pump.angle-90)
	local start=pump.point+Mechanics.rotate(Vector2.new(80,0),angle)
	local speed=544*60/(.9*(1-.9^36)/.1)
	for index=1,5 do
		local quad=Frames.pump[math.random(7,9)]
		local size=1+math.random()*2
		local frame=holder(self.layer,"PumpAir",Vector2.new(quad[4],quad[5])*size,Layers.Effect)
		crop(frame,"Particle",quad,0,1)
		local direction=angle+math.rad(math.random()*20-10)
		table.insert(self.particles,{frame=frame,point=start,velocity=Vector2.new(math.cos(direction),math.sin(direction))*(speed+math.random()*200-100),age=0})
	end
end

function visuals:update(delta)
	local mechanics=self.physics.mechanics
	self.layer:SetAttribute("GravityInverted",self.physics.gravityInverted)
	for _,visual in ipairs(self.switches) do visual.atlas:show("gravity",self.physics.gravityInverted and 1 or 0) end
	for index,parts in pairs(self.wheels) do
		local wheel=self.physics.ropes[index].wheel
		for quad,visual in ipairs(parts) do
			at(visual.frame,wheel.rope.anchor)
			visual.frame.Rotation=quad==1 and 0 or wheel.angle
		end
		-- Arm.passTransformationsToChilds=false: dial/highlight do NOT shrink
		-- or inherit a second rotation when the inner arm scales with rope length.
		local scale=wheel:armScale()
		parts[2].frame.Size=UDim2.fromScale(107*scale/2560,102*scale/1440)
		parts[3].frame.Visible=wheel.operating
		parts[4].frame.Visible=not wheel.operating
		parts[1].frame:SetAttribute("RopeLength",wheel.length(wheel.rope))
		parts[1].frame:SetAttribute("Parts",#wheel.rope.bodies)
		parts[1].frame:SetAttribute("Angle",wheel.angle)
	end
	for index,visual in ipairs(self.bouncers) do
		local object=self.physics.bouncers.objects[index]
		local age=self.physics.bouncers.time-object.hit
		local quad=(object.size-1)*5+(age<.2 and math.min(4,math.floor(age/.04)) or 0)
		local q=SplitFrames.bouncer[quad+1]
		local scale=object.beltScale or 1
		visual.frame.Size=UDim2.fromScale(q[8]*scale/2560,q[9]*scale/1440)
		at(visual.frame,object.point)
		visual.frame.Rotation=object.angle
		visual.atlas:show("bouncer",quad)
		visual.frame:SetAttribute("Hits",object.hits)
	end
	for index,visual in ipairs(self.pumps) do
		local pump=mechanics.pumps[index]
		local q=Frames.pump[1]
		local scale=pump.beltScale or 1
		visual.frame.Size=UDim2.fromScale(q[8]*scale/2560,q[9]*scale/1440)
		at(visual.frame,pump.point)
		visual.frame.Rotation=pump.angle
		local age=mechanics.time-pump.fired
		visual.atlas:show("pump",age<.15 and ({1,2,3})[math.floor(age/.05)+1] or 0)
		visual.frame:SetAttribute("Shots",pump.shots)
		if visual.shots~=pump.shots then
			if pump.shots>0 then self:emit(pump) end
			visual.shots=pump.shots
		end
	end
	for index,visual in ipairs(self.hats) do
		local hat=mechanics.hats[index]
		local scale=hat.beltScale or .7
		visual.pivot.Size=UDim2.fromScale(431*scale/2560,431*scale/1440)
		at(visual.pivot,hat.point+Vector2.new(0,-.5))
		visual.pivot.Rotation=hat.angle
		local age=mechanics.time-hat.flash
		visual.flash.frame.Visible=age<.2
		if age<.2 then visual.flash.atlas:show("hat",({2,3,4,4})[math.floor(age/.05)+1]) end
	end
	for index,visual in pairs(self.spiders) do
		local spider=mechanics.spiders[index]
		at(visual.frame,spider.point)
		visual.frame.Rotation=spider.angle
		visual.frame.Visible=not spider.hidden
		visual.atlas:show("spider",spider.quad)
		visual.frame:SetAttribute("State",spider.state)
		visual.frame:SetAttribute("Distance",spider.distance)
	end
	for index,visual in pairs(self.rails) do
		local rope=self.physics.ropes[index]
		at(visual.hook.frame,rope.anchor)
		at(visual.glow.frame,rope.anchor)
		visual.glow.frame.Visible=mechanics.heldRail==rope
	end
	for index=#self.particles,1,-1 do
		local particle=self.particles[index]
		particle.age+=delta
		if particle.age>=.6 then particle.frame:Destroy() table.remove(self.particles,index)
		else
			particle.velocity*=.9^(delta*60)
			particle.point+=particle.velocity*delta
			at(particle.frame,particle.point)
			particle.frame.Particle.ImageTransparency=1-.6*(1-particle.age/.6)
		end
	end
end

visuals.sprite=sprite
visuals.at=at
return visuals
