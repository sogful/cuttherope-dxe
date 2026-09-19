local Frames=require(script.Parent.GhostFrames)
local Atlas=require(script.Parent.AtlasSprite)
local Box=require(script.Parent.BoxVisuals)
local SplitFrames=require(script.Parent.SplitFrames)
local Sprites=require(script.Parent.DxSprites)
local Radius=require(script.Parent.HookRadius)
local Mechanics=require(script.Parent.GhostMechanics)
local Layers=require(script.Parent.GameplayLayers)
local visuals={}
visuals.__index=visuals

local function root(parent,name,z)
	local frame=Instance.new("Frame")
	frame.Name,frame.BackgroundTransparency,frame.Size=name,1,UDim2.fromScale(1,1)
	frame.ZIndex,frame.Parent=z,parent
	return frame
end
local function image(parent,name,asset,size,z)
	local im=Instance.new("ImageLabel")
	im.Name,im.Image,im.BackgroundTransparency=name,asset,1
	im.AnchorPoint,im.Size=Vector2.new(.5,.5),UDim2.fromScale(size.X/2560,size.Y/1440)
	im.ZIndex,im.Parent=z,parent
	return im
end
local function quad(parent,name,index,z)
	return Box.sprite(parent,name,"ghost",index,1,z,Frames)
end
local function ease(t,inside) return inside and t*t or 1-(1-t)*(1-t) end
local function wave(t,duration,a,b,c)
	local phase=t/duration%4
	local segment=math.floor(phase)
	local values={a,b,c,b,a}
	return values[segment+1]+(values[segment+2]-values[segment+1])*ease(phase-segment,segment%2==0)
end
local bubbleClouds={
	{6,85,25,.8,.78,.76,.48,1,1}, {5,65,55,.93,.965,1,.4,1,1},
	{5,-90,15,.33,.365,.4,.43,1,1}, {6,-75,45,.6,.565,.53,.42,-1,1},
	{2,-20,75,.93,.965,1,.47,1,-1,350},
}
local grabClouds={
	{5,-60,2,.43,.465,.5,.65,-1,1}, {4,58,18,.9,.8,.7,.45,1,1},
	{2,-15,45,1.1,1,.9,.5,-1,1},
}
local function cloudDefinitions(form,angle)
	if form==2 then return bubbleClouds end
	if form==4 then return grabClouds end
	local a,b=math.rad(10+angle),math.rad(170+angle)
	local radius=math.sqrt(9000)
	return {
		{4,radius*math.cos(a),radius*math.sin(a),.9,.8,.7,.39,1,1,0,true},
		{4,radius*math.cos(b),radius*math.sin(b),.7,.55,.4,.35,1,1,0,true},
		{3,60,55,1.1,1,.9,.45,1,1}, {2,-50,55,1.1,1,.9,.5,-1,1},
	}
end

function visuals.new(layer,mechanics)
	local self=setmetatable({layer=layer,mechanics=mechanics,items={},idle={},pool={},particles={}},visuals)
	for _,g in ipairs(mechanics.objects) do
		local holder=root(layer,"Ghost"..g.index,55)
		self.idle[g]={root=holder,body=quad(holder,"Body",0,1),face=quad(holder,"Face",1,2),morphs=0}
		self.pool[g]={}
		for i=1,7 do
			local holder=root(layer,"Ghost"..g.index.."Puff"..i,55)
			holder.AnchorPoint=Vector2.new(.5,.5)
			local atlas=Atlas.new(holder,{"ghost"},Frames,{ghost={4,5,6}})
			atlas:show("ghost",4)
			holder.Visible=false
			table.insert(self.particles,{ghost=g,visual={frame=holder,atlas=atlas},active=false,index=i})
		end
		for _,form in ipairs({2,4,8}) do if bit32.band(g.forms,form)~=0 then
			self.pool[g][form]={self:create(g,form),self:create(g,form)}
		end end
	end
	return self
end

function visuals:create(g,form)
	local z=form==2 and Layers.Bubble or form==4 and Layers.HookFront or Layers.Bouncer
	local holder=root(self.layer,"Ghost"..g.index.."Form"..form,z)
	local item={root=holder,clouds={},form=form,ghost=g}
	for i,d in ipairs(cloudDefinitions(form,g.angle)) do
		local visual=quad(holder,"Cloud"..i,d[1],d[11] and 1 or 3)
		item.clouds[i]={visual=visual,definition=d}
	end
	if form==2 then
		item.bubble=image(holder,"Bubble","",Vector2.new(449,446),2)
		item.atlas=Atlas.new(item.bubble,{"bubble"},nil,{bubble={0,4,5,6,7,8,9,10,11,12,13,14,15,16}})
		item.shadow=image(self.layer,"Ghost"..g.index.."BubbleShadow",Sprites.Bubble.shadows[math.random(1,3)],Vector2.new(449,446),Layers.BubbleShadow)
		Box.at(item.shadow,g.point)
		item.atlas:show("bubble",0)
	elseif form==4 then
		local automatic=g.radius>=0
		item.back=image(self.layer,"Ghost"..g.index.."HookBack",automatic and Sprites.Hook.autoBack or Sprites.Hook.static,Vector2.new(120,120)*(2560/1120),Layers.HookBack)
		item.front=image(holder,"HookFront",automatic and Sprites.Hook.autoFront or Sprites.Hook.staticFront,Vector2.new(120,120)*(2560/1120),2)
		Box.at(item.back,g.point) Box.at(item.front,g.point)
		if automatic then item.radius=Radius.new(self.layer,"Ghost"..g.index,{anchor=g.point,radius=g.radius}) end
	else
		item.bouncer=Box.sprite(holder,"Bouncer","bouncer",0,1,2,SplitFrames)
		Box.at(item.bouncer.frame,g.point)
		item.bouncer.frame.Rotation=g.angle
	end
	self:hide(item)
	return item
end

function visuals:hide(item)
	item.root.Visible=false
	if item.shadow then item.shadow.Visible=false end
	if item.back then item.back.Visible=false end
	if item.radius then item.radius:update(0) end
end

function visuals:emit(g)
	local start=math.random()*math.pi*2
	for _,p in ipairs(self.particles) do if p.ghost==g then
		local q=math.random(4,6)
		local angle=start+p.index*math.pi*2/7+math.rad(math.random()*30-15)
		p.quad,p.point,p.velocity=q,g.point,Vector2.new(math.cos(angle),math.sin(angle))*(45+math.random()*30)
		p.age,p.life,p.size,p.spin=0,.45+math.random()*.3,.4+math.random()*.8,math.random()*60-30
		p.active,p.visual.frame.Visible=true,true
		p.visual.atlas:show("ghost",q)
	end end
end

function visuals:update(delta)
	local mechanics=self.mechanics
	for g,item in pairs(self.idle) do
		local alpha=g.idleAppearing and math.min(1,g.idleAge/.36) or math.max(0,1-g.idleAge/.16)
		item.root.Visible=alpha>0
		item.root:SetAttribute("Form",g.form)
		item.root:SetAttribute("Morphs",g.morphs)
		item.root:SetAttribute("Captured",g.form==2 and mechanics:bubbleOwner(g.app)~=nil)
		for i,v in ipairs({item.body,item.face}) do
			local amplitude=i==1 and 3 or 2
			local start=g.phase+(i==2 and .005 or 0)
			local y=mechanics.time<start and -amplitude*ease(mechanics.time/math.max(.001,start),false)
				or wave(math.max(0,mechanics.time-start),.38,-amplitude,0,amplitude)
			Box.at(v.frame,g.point+Vector2.new(0,y))
			v.atlas:fade(1-alpha)
		end
		if item.morphs~=g.morphs then item.morphs=g.morphs self:emit(g) end
	end
	local alive={}
	for _,app in ipairs(mechanics.apps) do
		alive[app]=true
		local item=self.items[app]
		if not item then
			item=table.remove(self.pool[app.ghost][app.form]) or self:create(app.ghost,app.form)
			self.items[app]=item
		end
		local alpha=Mechanics.alpha(app)
		item.root.Visible=alpha>0
		item.root:SetAttribute("Retiring",app.retiring==true)
		item.root:SetAttribute("Alpha",alpha)
		local point,cloudTime=app.point,app.age
		local cloudAlpha=alpha
		if app.form==2 then
			local owner=mechanics:bubbleOwner(app)
			local attached=owner and mechanics.parked~=app and not app.retiring
			item.shadow.Visible=alpha>0
			item.shadow.ImageTransparency=1-alpha
			if attached then
				point,cloudTime,cloudAlpha=owner.pos,mechanics.time,1
				item.root.ZIndex=Layers.AttachedBubble
				item.bubble.Size=UDim2.fromScale(250/2560,250/1440)
				local age=math.max(0,mechanics.time-(owner.bubbleCaptureTime or 0))
				item.atlas:show("bubble",age<.65 and math.min(12,math.floor(age*20))+4 or 7)
			else
				item.root.ZIndex=Layers.Bubble
				item.bubble.Size=UDim2.fromScale(449/2560,446/1440)
				item.atlas:show("bubble",0)
				item.root.Visible=not mechanics.physics.usedBubbles[app.index]
			end
			item.atlas:fade(1-cloudAlpha)
			Box.at(item.bubble,point)
		elseif app.form==4 then
			item.back.Visible=alpha>0
			item.back.ImageTransparency,item.front.ImageTransparency=1-alpha,1-alpha
			if item.radius then item.radius:update(app.rope.radiusAlpha*alpha,app.point) end
		else
			local age=mechanics.physics.bouncers.time-app.bouncer.hit
			local index=age<.2 and math.min(4,math.floor(age/.04)) or 0
			item.bouncer.atlas:show("bouncer",index)
			item.bouncer.atlas:fade(1-alpha)
			item.root:SetAttribute("Hits",app.bouncer.hits)
		end
		for _,cloud in ipairs(item.clouds) do
			local d,v=cloud.definition,cloud.visual
			local scale=wave(cloudTime,d[7],d[4],d[5],d[6])
			local offset=Vector2.new(d[2]+wave(cloudTime,d[7],d[8],0,-d[8]),d[3]+wave(cloudTime,d[7],d[9],0,-d[9]))
			Box.at(v.frame,point+offset)
			local q=Frames.ghost[d[1]+1]
			v.frame.Size=UDim2.fromScale(q[8]*scale/2560,q[9]*scale/1440)
			v.frame.Rotation=d[10] or 0
			v.atlas:fade(d[11] and 0 or 1-cloudAlpha)
		end
	end
	for app,item in pairs(self.items) do if not alive[app] then
		self:hide(item)
		table.insert(self.pool[item.ghost][item.form],item)
		self.items[app]=nil
	end end
	for _,p in ipairs(self.particles) do
		if not p.active then continue end
		p.age+=delta
		if p.age>=p.life then p.visual.frame.Visible,p.active=false,false
		else
			p.point+=p.velocity*delta
			p.velocity*=.83^(delta/.016)
			p.size*=1.015^(delta/.016)
			local q=Frames.ghost[p.quad+1]
			p.visual.frame.Size=UDim2.fromScale(q[8]*p.size/2560,q[9]*p.size/1440)
			p.visual.frame.Rotation=p.spin*p.age
			Box.at(p.visual.frame,p.point)
			p.visual.atlas:fade(1-math.min(1,(p.life-p.age)/.42))
		end
	end
end

return visuals
