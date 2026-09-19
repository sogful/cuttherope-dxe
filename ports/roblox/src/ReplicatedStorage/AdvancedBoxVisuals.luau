-- Spikes.Init / Grab.SetBee / PollenDrawer registration and timelines.
local Frames=require(script.Parent.AdvancedFrames)
local Atlas=require(script.Parent.AtlasSprite)
local Box=require(script.Parent.BoxVisuals)
local Layers=require(script.Parent.GameplayLayers)
local visuals={}
visuals.__index=visuals
local function move(value,target,delta) return value+math.clamp(target-value,-delta,delta) end

function visuals.new(layer,physics)
	local self=setmetatable({layer=layer,physics=physics,buttons={},bees={},pollen={},time=0},visuals)
	for index,object in ipairs(physics.hazards.objects) do
		if object.group and object.group>0 then
			local parent=layer["Spike"..index]
			local holder=Instance.new("Frame")
			holder.Name,holder.BackgroundTransparency,holder.Size="RotateButton",1,UDim2.fromScale(1,1)
			holder.ZIndex,holder.Parent=Layers.Hazard+1,parent
			local atlas=Atlas.new(holder,{"button","buttonMirror"},Frames,true)
			self.buttons[index]=atlas
		end
	end
	for index,rope in ipairs(physics.ropes) do
		if rope.mover then
			local body=Box.sprite(layer,"Bee"..index,"bee",0,.77,Layers.Bee,Frames)
			local wings=Box.sprite(layer,"BeeWings"..index,"bee",1,.77,Layers.Bee+1,Frames)
			self.bees[index]={body=body,wings=wings,phase=math.random(0,2)}
			if not rope.definition.hidePath then
				local path=rope.mover.path
				local function segment(a,b)
					local difference=path[b]-path[a]
					local distance=difference.Magnitude
					local direction=distance>0 and difference/distance or Vector2.zero
					for i=0,math.floor(distance/44) do
						local point=path[a]+direction*(i*44)+Vector2.new(math.random(-2,2),math.random(-2,2))
						local visual=Box.sprite(layer,"Pollen"..(#self.pollen+1),"pollen",0,1.5,Layers.Pollen,Frames)
						Box.at(visual.frame,point)
						local size=({.3,.3,.5,.5,.6})[math.random(1,5)]
						local x,y=size,size
						if math.random(0,1)==1 then x*=1+math.random(0,1)/10 else y*=1+math.random(0,1)/10 end
						local offset=math.min(1-x,1-y)
						local random=math.random()
						table.insert(self.pollen,{visual=visual,x=(x+offset)*random,y=(y+offset)*random,
							tx=x,ty=y,sx=x+offset,sy=y+offset,alpha=.7*random+.3,ta=.3,sa=1})
					end
				end
				for i=1,#path-1 do if not rope.definition.movement.radius or (i-1)%3==0 then segment(i,i+1) end end
				if #path>2 then segment(1,#path) end
			end
		end
	end
	-- The source deliberately submits pollenCount-1 quads.
	if #self.pollen>0 then self.pollen[#self.pollen].visual.frame.Visible=false end
	self:update()
	return self
end

function visuals:update()
	local time=self.physics.mechanics.time
	local delta=time-self.time
	self.time=time
	for index,atlas in pairs(self.buttons) do
		local object=self.physics.hazards.objects[index]
		atlas:show(object.normal and "buttonMirror" or "button",(object.group-1)*2+(object.pressed and 1 or 0))
		local parent=atlas.parent.Parent
		parent:SetAttribute("Group",object.group)
		parent:SetAttribute("Normal",object.normal)
		parent:SetAttribute("Angle",object.angle)
	end
	for index,bee in pairs(self.bees) do
		local rope=self.physics.ropes[index]
		local angle=math.rad(rope.beeAngle)
		-- Source rotation/scale pivot is (143,196), exactly at the hook center.
		local offset=Vector2.new(-5.5,-58.5)*.77
		local center=rope.anchor+Vector2.new(offset.X*math.cos(angle)-offset.Y*math.sin(angle),offset.X*math.sin(angle)+offset.Y*math.cos(angle))
		for _,visual in ipairs({bee.body,bee.wings}) do
			Box.at(visual.frame,center)
			visual.frame.Rotation=rope.beeAngle
		end
		local phase=(math.floor(rope.beeAge/.03)+bee.phase)%4
		bee.wings.atlas:show("bee",({1,2,3,2})[phase+1])
		bee.body.frame:SetAttribute("HookX",rope.anchor.X)
		bee.body.frame:SetAttribute("HookY",rope.anchor.Y)
	end
	for _,p in ipairs(self.pollen) do
		p.x,p.y,p.alpha=move(p.x,p.tx,delta),move(p.y,p.ty,delta),move(p.alpha,p.ta,delta)
		if delta>0 then
			if p.x==p.tx then p.tx,p.sx=p.sx,p.tx end
			if p.y==p.ty then p.ty,p.sy=p.sy,p.ty end
			if p.alpha==p.ta then p.ta,p.sa=p.sa,p.ta end
		end
		p.visual.frame.Size=UDim2.fromScale(37.5*p.x/2560,37.5*p.y/1440)
		p.visual.atlas:fade(1-p.alpha)
	end
end
return visuals
