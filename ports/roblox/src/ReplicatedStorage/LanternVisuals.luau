-- Lantern.cs child order, restored sprite pivots, and activation timelines.
local Atlas=require(script.Parent.AtlasSprite)
local Frames=require(script.Parent.LanternFrames)
local Layers=require(script.Parent.GameplayLayers)
local visuals={}
visuals.__index=visuals
local function lerp(a,b,t) return a+(b-a)*math.clamp(t,0,1) end
local function ease(t) return 1-(1-t)^2 end
local function sprite(layer,name,group,index,z)
	local q=Frames[group][index+1]
	local frame=Instance.new("Frame")
	frame.Name,frame.BackgroundTransparency,frame.AnchorPoint=name,1,Vector2.new(.5,.5)
	frame.Size,frame.ZIndex,frame.Parent=UDim2.fromScale(q[8]/2560,q[9]/1440),z,layer
	local atlas=Atlas.new(frame,{group},Frames,{[group]={index}})
	atlas:show(group,index)
	return {frame=frame,atlas=atlas,size=Vector2.new(q[8],q[9])}
end
local function place(v,object,x,y,sx,sy,alpha,tint)
	local a=math.rad(object.angle)
	local p=object.point+Vector2.new(x*math.cos(a)-y*math.sin(a),x*math.sin(a)+y*math.cos(a))
	v.frame.Position=UDim2.fromScale(p.X/2560,p.Y/1440)
	v.frame.Size=UDim2.fromScale(v.size.X*sx/2560,v.size.Y*sy/1440)
	v.frame.Rotation=object.angle
	v.atlas:fade(1-alpha)
	if tint then
		for _,label in pairs(v.atlas.fixedFrames) do label.ImageColor3=Color3.new(tint,tint,tint) end
	end
end
function visuals.new(layer,mechanics,skin)
	local self=setmetatable({objects={},mechanics=mechanics},visuals)
	if #mechanics.objects==0 then return self end
	local root=Instance.new("Frame")
	root.Name,root.BackgroundTransparency,root.Size="LanternLayer",1,UDim2.fromScale(1,1)
	root.ZIndex,root.Parent=Layers.Lantern,layer
	self.root=root
	for i,object in ipairs(mechanics.objects) do
		local v={object=object}
		local group=Instance.new("Frame")
		group.Name,group.BackgroundTransparency,group.Size="Lantern"..i,1,UDim2.fromScale(1,1)
		group.ZIndex,group.Parent=i,root
		-- Explicit child passes. Equal world-root Z values can batch the active
		-- shell over its candy after independently animated scale changes.
		v.fire=sprite(group,"LanternFire"..i,"lantern",0,1)
		v.idle=sprite(group,"LanternIdle"..i,"lantern",2,2)
		v.active=sprite(group,"LanternActive"..i,"lantern",1,3)
		v.candy=sprite(group,"LanternCandy"..i,"candy"..skin,0,4)
		table.insert(self.objects,v)
	end
	self:update()
	return self
end
function visuals:update()
	for _,v in ipairs(self.objects) do
		local o=v.object
		local age=o.age
		local activation=o.phase=="appear" and math.min(1,age/.3) or o.phase=="hide" and math.max(0,1-age/.3) or 0
		place(v.idle,o,0,0,1,1,1-activation)
		place(v.active,o,0,1,1,1,activation)
		local sx,sy,y,alpha,brightness=1,1,-4,0,1
		local firex,firey,fireAlpha=1.4,1,0
		if o.phase=="appear" then
			alpha=math.min(1,age/.2)
			if age<.07 then sy=lerp(1,.8,age/.07)
			elseif age<.12 then sx,sy=lerp(1,.85,(age-.07)/.05),lerp(.8,1.05,(age-.07)/.05)
			else sx,sy=lerp(.85,1,(age-.12)/.05),lerp(1.05,1,(age-.12)/.05) end
			y=age<.1 and lerp(-4,0,age/.1) or lerp(0,-1,(age-.1)/.05)
			if age>=o.idleStart then
				local phase=(age-o.idleStart)%1.4
				local quarter=math.floor(phase/.35)
				local t=(phase-quarter*.35)/.35
				local values={1,.93,.87,.93,1}
				sx=lerp(values[quarter+1],values[quarter+2],quarter%2==0 and t*t or ease(t))
				sy=sx
			end
			fireAlpha=.7
			if age>=o.fireStart then
				local phase=(age-o.fireStart)%1
				local t=phase<.5 and phase/.5 or (1-phase)/.5
				firex,firey,fireAlpha=lerp(1.4,1.05,ease(t)),lerp(1,1.3,ease(t)),lerp(.7,1,t)
			end
		elseif o.phase=="hide" then
			if age<.06 then
				local t=age/.06
				alpha,sx,sy,y=lerp(1,.6,t),lerp(1,1.15,t),lerp(1,.8,t),lerp(0,-4,ease(t))
			else
				local t=math.clamp((age-.06)/.04,0,1)
				alpha,sx,sy,y=lerp(.6,0,t),lerp(1.15,1,t),lerp(.8,1,t),lerp(-4,4,t*t)
			end
			brightness=alpha
		end
		place(v.candy,o,0,y,sx,sy,alpha,brightness)
		place(v.fire,o,0,0,firex,firey,fireAlpha,fireAlpha)
		v.idle.frame:SetAttribute("LanternState",o.state)
		v.idle.frame:SetAttribute("LanternPhase",o.phase)
	end
end
return visuals
