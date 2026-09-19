local Frames = require(script.Parent.TraceFrames)
local Presets = require(script.Parent.TracePresets)
local Session = require(script.Parent.SessionState)
local trace = {}
trace.__index = trace
local emitters = {{}, {1}, {2}, {3}, {4}, {5,6}, {7}, {8}, {9}, {10}, {11}}
local function sprite(parent, group, index)
	local q = Frames[group][index + 1]
	local image = Instance.new("ImageLabel")
	image.Name, image.BackgroundTransparency = "TraceParticle", 1
	image.AnchorPoint, image.Image = Vector2.new(.5,.5), Frames.pages[q[1]]
	image.ImageRectOffset, image.ImageRectSize = Vector2.new(q[2],q[3]), Vector2.new(q[4],q[5])
	image.ZIndex, image.Parent = 25, parent
	return image, q
end
local function gradient(mode, t)
	if mode == 0 then return Color3.new(1,1,1), 1 end
	if mode == 3 then
		local a,b,f
		if t < .33 then a,b,f=Color3.new(1,.30196,.99216),Color3.new(1,.64314,.29412),t*3
		elseif t < .66 then a,b,f=Color3.new(1,.64314,.29412),Color3.new(1,.95294,.20392),(t-.33)*3
		else a,b,f=Color3.new(1,.95294,.20392),Color3.new(1,1,1),(t-.66)*3 end
		return a:Lerp(b,f),1
	elseif mode == 4 then
		if t < .5 then return Color3.new(.13,.59608,.75686):Lerp(Color3.new(.51765,1,1),t*2), t*2 end
		return Color3.new(.51765,1,1):Lerp(Color3.new(1,1,1),(t-.5)*2),1
	elseif mode == 5 then
		if t < .7 then return Color3.new(.7882,.2157,.298):Lerp(Color3.new(.98824,.20784,.16863),t*2),math.min(1,t*2) end
		return Color3.new(.98824,.20784,.16863):Lerp(Color3.new(.95294,.61961,.41961),(t-.7)*2),1
	elseif mode == 6 then
		return t < .35 and Color3.new(.14118,.81961,.87451):Lerp(Color3.new(1,1,1),t*3) or Color3.new(1,1,1),1
	end
	return t < .5 and Color3.new(1,.87451,.0549):Lerp(Color3.new(1,1,1),math.min(1,t*3)) or Color3.new(1,1,1),1
end
function trace.new(parent)
	return setmetatable({parent=parent, segments={}, particles={}, lines={}, history={}, counters={}, random=Random.new(), burst=0, mode=0},trace)
end
function trace:reset()
	if self.glow then self.glow:Destroy() self.glow=nil end
	for _,p in ipairs(self.particles) do p.image:Destroy() end
	for _,line in ipairs(self.lines) do line:Destroy() end
	self.segments,self.particles,self.lines,self.history,self.counters={},{},{},{},{}
	self.burst=0
end
function trace:begin(point)
	self:reset()
	self.mode,self.last=Session.trace or 0,point
end
function trace:append(point)
	if not self.last then self:begin(point) return end
	local delta=point-self.last
	if delta.Magnitude < .01 then return end
	local life=self.mode==0 and .1 or self.mode==2 and math.clamp(delta.Magnitude*.007+.05,.01,.25) or .15
	table.insert(self.segments,{a=self.last,b=point,life=life})
	table.insert(self.history,delta)
	if #self.history>10 then table.remove(self.history,1) end
	self.last,self.head,self.burst=point,point,.1
end
function trace:finish() self.last=nil end
function trace:spawn(config, direction)
	local function vary(base, amount) return base+self.random:NextNumber(-1,1)*amount end
	local angle=direction+math.rad(vary(180,config.AngleVarianceDegrees))
	local speed=vary(config.Speed,config.SpeedVariance)
	local life=math.max(.05,vary(config.Life,config.LifeVariance))
	local start=self.head+Vector2.new(vary(0,config.SpawnPositionVariance),vary(0,config.SpawnPositionVariance))
	local image,q=sprite(self.parent,"particles",config.FirstQuad+self.random:NextInteger(0,config.QuadCount-1))
	local spin=math.rad(vary(config.SpinDegrees,config.SpinVarianceDegrees))
	table.insert(self.particles,{image=image,q=q,config=config,pos=start,origin=start,velocity=Vector2.new(math.cos(angle),math.sin(angle))*speed,
		life=life,total=life,scale=vary(config.StartScale,config.StartScaleVariance),rotation=0,spin=config.SpinIsTotalDegreesOverLife and spin/life or spin})
end
function trace:update(dt)
	dt=math.min(dt,.05)
	self.burst=math.max(0,self.burst-dt)
	for i=#self.segments,1,-1 do
		self.segments[i].life-=dt
		if self.segments[i].life<=0 then table.remove(self.segments,i) end
	end
	local direction=Vector2.zero
	for _,v in ipairs(self.history) do direction+=v end
	local angle=math.atan2(direction.Y,direction.X)
	local average=direction/math.max(1,#self.history)
	local glowIndex=(self.mode==2 or self.mode==3) and 0 or self.mode==4 and 1 or self.mode>=6 and 2 or nil
	if glowIndex~=nil then
		if not self.glow then self.glow,self.glowQuad=sprite(self.parent,"glow",glowIndex) end
		local alpha=math.clamp(math.min(#self.segments/5,average.Magnitude/10),0,1)
		self.glow.Visible=alpha>0
		if self.head then self.glow.Position=UDim2.fromScale(self.head.X/2560,self.head.Y/1440) end
		self.glow.Size=UDim2.fromScale(self.glowQuad[4]/2560,self.glowQuad[5]/1440)
		self.glow.Rotation,self.glow.ImageTransparency=math.deg(angle)+90,1-alpha
	end
	local rate=self.mode==0 and 0 or self.mode==1 and 80 or self.mode==5 and 35 or 50
	for _,index in ipairs(emitters[self.mode+1]) do
		if self.burst>0 then
			self.counters[index]=(self.counters[index] or 0)+dt
			while self.counters[index]>1/rate and #self.particles<200 do
				self.counters[index]-=1/rate
				self:spawn(Presets[index],angle)
			end
		end
	end
	for i=#self.particles,1,-1 do
		local p=self.particles[i]
		p.life-=dt
		if p.life<=0 then p.image:Destroy() table.remove(self.particles,i) else
			local c=p.config
			local radial=p.origin-p.pos
			if radial.Magnitude>.0001 then p.velocity+=radial.Unit*c.RadialAcceleration*dt end
			p.velocity+=Vector2.new(0,c.GravityY*dt)
			p.pos+=p.velocity*dt
			p.rotation=c.RotateToVelocity and math.deg(math.atan2(p.velocity.Y,p.velocity.X)+1.5708) or p.rotation+p.spin*dt
			local ratio=p.life/p.total
			local scale=p.scale+(c.EndScale-p.scale)*(1-ratio)
			p.image.Position=UDim2.fromScale(p.pos.X/2560,p.pos.Y/1440)
			p.image.Size=UDim2.fromScale(p.q[4]*scale/2560,p.q[5]*scale/1440)
			p.image.Rotation,p.image.ImageTransparency=p.rotation,1-c.Alpha*(c.FadeAlphaWithLife and ratio or 1)
		end
	end
	local points={}
	if self.mode==2 then
		self:lightning(dt)
		self.parent:SetAttribute("TraceSkin",self.mode)
		self.parent:SetAttribute("TraceParticles",#self.particles)
		return
	end
	if self.mode~=1 then
		for _,segment in ipairs(self.segments) do table.insert(points,segment.a) end
		if #self.segments>0 then table.insert(points,self.segments[#self.segments].b) end
	end
	local sampled={}
	if #points>=2 then
		local count=#points*2-1
		for index=0,count-1 do
			local work=table.clone(points)
			for n=#work-1,1,-1 do for j=1,n do work[j]=work[j]:Lerp(work[j+1],index/(count-1)) end end
			table.insert(sampled,work[1])
		end
	end
	for i=1,#sampled-1 do
		local line=self.lines[i]
		if not line then
			line=Instance.new("Frame")
			line.Name,line.BorderSizePixel,line.AnchorPoint="TraceRibbon",0,Vector2.new(.5,.5)
			line.ZIndex,line.Parent=24,self.parent
			self.lines[i]=line
		end
		local a,b=sampled[i],sampled[i+1]
		local d=b-a
		local t=(i-1)/math.max(1,#sampled-1)
		local color,alpha=gradient(self.mode,t)
		line.Visible,line.BackgroundColor3,line.BackgroundTransparency=true,color,1-math.clamp(alpha,0,1)
		line.Position=UDim2.fromScale((a.X+b.X)/5120,(a.Y+b.Y)/2880)
		line.Size=UDim2.fromScale(d.Magnitude/2560,(2+24*t)/1440)
		line.Rotation=math.deg(math.atan2(d.Y,d.X))
	end
	for i=math.max(1,#sampled),#self.lines do self.lines[i].Visible=false end
	self.parent:SetAttribute("TraceSkin",self.mode)
	self.parent:SetAttribute("TraceParticles",#self.particles)
end
function trace:lightning(dt)
	self.variantTime=(self.variantTime or 0)-dt
	local refresh=self.variantTime<=0
	if refresh then self.variantTime=.06 end
	local total=0
	for _,s in ipairs(self.segments) do total+=(s.b-s.a).Magnitude end
	local count=math.floor(total/112)+1
	local stride=total/count
	local first,used=1,0
	for quad=0,count-1 do
		if first>#self.segments then break end
		local last,acc=first,0
		repeat acc+=(self.segments[last].b-self.segments[last].a).Magnitude last+=1 until acc>=stride or last>#self.segments
		local ending=last>#self.segments and last-1 or last
		if ending>first then
			local a,b=self.segments[first].a,self.segments[ending].b
			local delta=b-a
			used+=1
			local line=self.lines[used]
			local index=quad==0 and self.random:NextInteger(20,23) or self.random:NextInteger(14,19)
			if not line then line=sprite(self.parent,"particles",index) self.lines[used]=line
			elseif refresh then
				local q=Frames.particles[index+1]
				line.Image,line.ImageRectOffset,line.ImageRectSize=Frames.pages[q[1]],Vector2.new(q[2],q[3]),Vector2.new(q[4],q[5])
			end
			line.Visible=true
			line.Position=UDim2.fromScale((a.X+b.X)/5120,(a.Y+b.Y)/2880)
			line.Size=UDim2.fromScale((quad+1)*30/2560,delta.Magnitude*1.25/1440)
			line.ImageColor3=Color3.new(1,1,(quad+.5)/count)
			line.Rotation=math.deg(math.atan2(delta.Y,delta.X))+90
		end
		first=ending+1
	end
	for i=used+1,#self.lines do self.lines[i].Visible=false end
end
return trace
