local Atlas=require(script.Parent.AtlasSprite)
local Frames=require(script.Parent.SteamFrames)
local Steam=require(script.Parent.SteamMechanics)
local Layers=require(script.Parent.GameplayLayers)
local visuals={}
visuals.__index=visuals

local function rotate(p,angle)
	local c,s=math.cos(math.rad(angle)),math.sin(math.rad(angle))
	return Vector2.new(p.X*c-p.Y*s,p.X*s+p.Y*c)
end
local function sprite(layer,name,group,index,z)
	local q=Frames[group][index+1]
	local frame=Instance.new("Frame")
	frame.Name,frame.BackgroundTransparency,frame.AnchorPoint=name,1,Vector2.new(.5,.5)
	frame.Size,frame.ZIndex,frame.Parent=UDim2.fromScale(q[8]/2560,q[9]/1440),z,layer
	local atlas=Atlas.new(frame,{group},Frames,true)
	atlas:show(group,index)
	return {frame=frame,atlas=atlas,size=Vector2.new(q[8],q[9])}
end
local function place(visual,tube,offset,scale,spin)
	scale=scale or 1
	local p=tube.point+rotate(offset,tube.angle)
	visual.frame.Position=UDim2.fromScale(p.X/2560,p.Y/1440)
	visual.frame.Size=UDim2.fromScale(visual.size.X*scale/2560,visual.size.Y*scale/1440)
	visual.frame.Rotation=tube.angle+(spin or 0)
end

function visuals.new(layer,mechanics)
	local self=setmetatable({mechanics=mechanics,objects={}},visuals)
	for index,tube in ipairs(mechanics.objects) do
		local v={tube=tube,revision=-1,puffs={},pool={}}
		v.body=sprite(layer,"SteamTube"..index,"pipe",0,Layers.SteamBack)
		v.valve=sprite(layer,"SteamValve"..index,"pipe",1,Layers.SteamBack)
		for variant=1,3 do
			v.pool[variant]={}
			for number=1,14 do
				local puff=sprite(layer,"SteamPuff"..index.."_"..variant.."_"..number,"puff"..variant,0,variant==3 and Layers.SteamBack or Layers.SteamFront)
				puff.variant,puff.active=variant,false
				puff.atlas:fade(1)
				table.insert(v.pool[variant],puff)
			end
		end
		table.insert(self.objects,v)
	end
	self:update()
	return self
end

function visuals:adjust(v)
	local tube,time=v.tube,self.mechanics.time
	for _,puff in ipairs(v.puffs) do
		if not puff.stop then
			puff.stop=puff.start+math.max(1,math.floor(math.max(0,time-puff.start)/.6)+1)*.6
		end
	end
	local count=({7,14,20})[tube.state+1]
	for i=0,count-1 do
		local variant=3-i%3
		local puff
		for _,candidate in ipairs(v.pool[variant]) do if not candidate.active then puff=candidate break end end
		if not puff then
			for _,candidate in ipairs(v.pool[variant]) do
				if candidate.stop and (not puff or candidate.stop<puff.stop) then puff=candidate end
			end
			puff=puff or v.pool[variant][1]
			local old=table.find(v.puffs,puff)
			if old then table.remove(v.puffs,old) end
		end
		local height=-Steam.height(tube,false)*(1+.1*(math.random()*2-1))
		if variant~=3 then height*=tube.state==1 and .95 or tube.state==2 and .94 or 1 end
		puff.height=math.ceil(height)
		puff.horizontal=variant==3 and 0 or (variant==2 and tube.state or -tube.state)
		puff.start,puff.stop,puff.active=time+.6*i/count,nil,true
		table.insert(v.puffs,puff)
	end
	v.revision=tube.revision
end

function visuals:update()
	local time=self.mechanics.time
	for _,v in ipairs(self.objects) do
		local tube=v.tube
		if v.revision~=tube.revision then self:adjust(v) end
		local scale=tube.beltScale or 1
		-- SteamTube.SetTransporterScale scales the parent and the two sprites;
		-- the puffs inherit only the parent transform.
		place(v.body,tube,Vector2.new(.5,v.body.size.Y*.5)*scale,scale*scale)
		place(v.valve,tube,Vector2.new(0,27*tube.scale+.5)*scale,scale*scale,tube.valveRotation)
		v.valve.frame:SetAttribute("SteamState",tube.state)
		v.body.frame:SetAttribute("SteamHeight",Steam.height(tube,true))
		for i=#v.puffs,1,-1 do
			local puff=v.puffs[i]
			local age=time-puff.start
			if puff.stop and time>=puff.stop then
				puff.active=false
				puff.atlas:fade(1)
				table.remove(v.puffs,i)
			elseif age<0 then puff.atlas:fade(1)
			else
				local progress=age%.6/.6
				local ease=1-(1-progress)^2
				local puffScale=1+.5*progress
				place(puff,tube,Vector2.new(puff.horizontal*ease,puff.height*ease+.5*puffScale)*scale,puffScale*scale)
				puff.atlas:show("puff"..puff.variant,math.min(10,math.floor(progress*11)))
				puff.atlas:fade(0)
			end
		end
	end
end

return visuals
