-- LightBulb.DrawLight/DrawBottleAndFirefly, Star night layers, original ZZZ states.
local Frames=require(script.Parent.PillowFrames)
local Box=require(script.Parent.BoxVisuals)
local Atlas=require(script.Parent.AtlasSprite)
local Math=require(script.Parent.DxMath)
local LightRaster=require(script.Parent.PillowLightRaster)
local night={}
night.__index=night
local zzzStates={
	{.4,.61,.8,29,9,0,1},{.3,.8,.89,9,-2,1,1},{.2,.89,.98,-2,-13,1,1},
	{.5,.98,.59,-13,-33,1,0},{.4,0,0,0,0,0,0},
}
local function visual(parent,name,group,quad,scale,z)
	return Box.sprite(parent,name,group,quad,scale,z,Frames)
end
function night.new(runtime)
	local self=setmetatable({runtime=runtime,physics=runtime.physics,bulbs={},stars={},zzz={},time=0},night)
	for i,b in ipairs(self.physics.bulbs) do
		local glow=visual(runtime.layer,"BulbGlow"..i,"lighter",0,3*b.radius/405,69)
		glow.atlas:fade(.4)
		local lightRaster=LightRaster.new(glow.frame)
		if lightRaster then glow.atlas:fade(1) end
		local bottle=visual(runtime.layer,"LightBulb"..i,"lighter",1,1,83)
		local cap=visual(bottle.frame,"BottleCap","lighter",2,1,2)
		cap.frame.Position=UDim2.fromScale(.5,.5)
		cap.frame.Size=UDim2.fromScale(1,1)
		local fire=visual(bottle.frame,"Fireflies","lighter",3,1,3)
		local q=Frames.lighter[4]
		fire.frame.Position=UDim2.fromScale(.5,.5)
		fire.frame.Size=UDim2.fromScale(q[8]/749,q[9]/749)
		self.bulbs[i]={glow=glow,bottle=bottle,fire=fire,lightRaster=lightRaster}
	end
	if self.physics.night.enabled then
		for i,s in ipairs(runtime.stars) do
			s.glow:fade(1)
			local glow=visual(s.container,"NightGlow","nightstar",0,1,5)
			local dim=visual(s.container,"UnlitStar","nightstar",1,1,7)
			local effect=visual(s.container,"LightChange","nightstar",25,1,8)
			-- Night sheet is 300-square; the normal sheet is 552-square.
			for _,v in ipairs({glow,dim,effect}) do v.frame.Position=UDim2.fromScale(.5,.5) v.frame.Size=UDim2.fromScale(300/552,300/552) end
			effect.frame.Visible=false
			self.stars[i]={glow=glow,dim=dim,effect=effect,alpha=0}
		end
		for i=1,2 do self.zzz[i]=visual(runtime.layer,"SleepZ"..i,"zzz",0,1,12) end
	end
	return self
end
function night:tick(delta)
	self.time+=delta
	local r,p=self.runtime,self.physics
	if not p.night.enabled then return end
	for i,s in ipairs(self.stars) do
		local lit=p.night.lit[i]==true
		if s.lit~=nil and s.lit~=lit then s.change=self.time s.up=lit end
		s.lit=lit
		s.alpha=math.clamp(s.alpha+(lit and .1 or -.1),0,1)
	end
	if r.state=="playing" then
		local awake=p.night.awake
		if self.awake~=awake then
			self.awake=awake
			r.animator.mouth=false
			r.animator:play(awake and "excited" or "sleeping")
			self.sleepStart=awake and nil or self.time
		end
	end
end
function night:update()
	local p,r=self.physics,self.runtime
	for i,v in ipairs(self.bulbs) do
		local b=p.bulbs[i]
		v.glow.frame.Visible=not b.removed and not b.transport
		v.bottle.frame.Visible=v.glow.frame.Visible
		Box.at(v.glow.frame,b.pos) Box.at(v.bottle.frame,b.pos)
		if v.lightRaster and v.glow.frame.Visible then v.lightRaster:update(b.pos,b.radius,r.camera) end
		v.fire.atlas:show("lighter",3+math.min(39,math.floor((p.night.time%1.95)/.05)))
		v.bottle.frame:SetAttribute("BulbX",b.pos.X)
		v.bottle.frame:SetAttribute("BulbY",b.pos.Y)
		v.bottle.frame:SetAttribute("LightRadius",b.radius)
	end
	if not p.night.enabled then return end
	for i,s in ipairs(self.stars) do
		s.glow.atlas:fade(1-s.alpha)
		r.stars[i].idle:fade(1-s.alpha)
		s.dim.atlas:fade(s.alpha)
		s.dim.atlas:show("nightstar",1+(math.floor(self.time*20)+i*5)%18)
		s.effect.frame.Visible=s.change~=nil and self.time-s.change<.25
		if s.effect.frame.Visible then s.effect.atlas:show("nightstar",(s.up and 25 or 19)+math.min(5,math.floor((self.time-s.change)*20))) end
		r.stars[i].container:SetAttribute("Lit",s.lit==true)
	end
	local sleeping=self.sleepStart~=nil and r.state=="playing" and r.animator.state=="sleeping"
	local age=self.sleepStart and self.time-self.sleepStart or 0
	for i,z in ipairs(self.zzz) do
		z.frame.Visible=sleeping
		if sleeping then
			local t=(age+(i==2 and 1.4 or 0))%1.8
			local row=zzzStates[5]
			for _,candidate in ipairs(zzzStates) do if t<candidate[1] then row=candidate break else t-=candidate[1] end end
			local fraction=t/row[1]
			local scale=row[2]+(row[3]-row[2])*fraction
			local angle=row[4]+(row[5]-row[4])*fraction
			z.atlas:fade(1-row[6]-(row[7]-row[6])*fraction)
			local q=Frames.zzz[1]
			z.frame.Size=UDim2.fromScale(q[8]*scale/2560,q[9]*scale/1440)
			z.frame.Rotation=angle
			local offset=Vector2.new(i==1 and 120 or 100,i==1 and -120 or -100)
			local pivot=Vector2.new(-160,0)
			Box.at(z.frame,p.target+offset+pivot-Math.rotate(pivot,math.rad(angle)))
		end
	end
	if r.layer:GetAttribute("OmNomSkin")==0 then
		local scale=sleeping and age>=.35 and .95+(math.sin(age*2)+1)*.05 or 1
		r.target.Size=UDim2.fromScale(270/1120,270/630*scale)
		Box.at(r.target,p.target+Vector2.new(0,86*(1-scale)))
	end
	r.layer:SetAttribute("NightAwake",p.night.awake)
end
return night
