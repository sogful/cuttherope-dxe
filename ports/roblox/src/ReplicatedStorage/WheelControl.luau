-- WheelControl.cs / Bungee.Roll and RollBack. Length is added at the tail,
-- including DX's integer rest-length rounding and 105-unit segment rollover.
local Math=require(script.Parent.DxMath)
local float=Math.float
local wheel={}
wheel.__index=wheel
local function trunc(value) return value<0 and math.ceil(value) or math.floor(value) end
local function tailLink(rope)
	local previous=rope.bodies[#rope.bodies-1]
	for _,link in ipairs(rope.tail.constraints) do if link.other==previous then return link end end
end
function wheel.length(rope)
	local length=0
	for i=2,#rope.bodies do length+=math.floor(Math.length(rope.bodies[i].pos-rope.bodies[i-1].pos)) end
	return length
end
function wheel.roll(rope,amount)
	local link=tailLink(rope)
	local rest=link and trunc(link.length) or -1
	while amount>0 do
		if amount>=105 then
			local previous=rope.bodies[#rope.bodies-1]
			local body={pos=previous.pos,previous=nil,mass=float(.02),inverse=50,velocity=Vector2.zero,constraints={{other=previous,length=105}}}
			table.insert(rope.bodies,#rope.bodies,body)
			if link then link.other,link.length=body,rest end
			amount-=105
		else
			local nextRest=trunc(float(amount+rest))
			if nextRest>105 then amount,rest=105,nextRest-105
			else if link then link.length=nextRest end amount=0 end
		end
	end
end
function wheel.rollBack(rope,amount)
	local link=tailLink(rope)
	local rest=link and trunc(link.length) or -1
	while amount>0 do
		if amount>=105 then
			if link then link.other,link.length=rope.bodies[#rope.bodies-2],rest end
			table.remove(rope.bodies,#rope.bodies-1)
			amount-=105
		else
			local nextRest=trunc(float(rest-amount))
			if nextRest<1 then amount,rest=105,105+nextRest+1
			else if link then link.length=nextRest end amount=0 end
		end
	end
	for _,constraint in ipairs(rope.tail.constraints) do
		if constraint.maximum then constraint.length=(#rope.bodies-1)*108 end
	end
end
function wheel.new(rope) return setmetatable({rope=rope,angle=0,operating=false},wheel) end
function wheel:inside(point)
	local d=point-self.rope.anchor
	return d.X>=-110 and d.X<110 and d.Y>=-110 and d.Y<110
end
function wheel:begin(point)
	if not self:inside(point) then return false end
	self.last,self.operating=point,true
	return true
end
function wheel:drag(point)
	if not self.operating or point==self.last then return end
	if self.audio and not self.audioPointerBatch then self.audio:play("wheel") end
	local first,last=self.last-self.rope.anchor,point-self.rope.anchor
	local a=float(math.atan2(first.Y,first.X))
	local b=float(math.atan2(last.Y,last.X))
	local angle=float(float(float(b-a)*180)/float(math.pi))
	if angle>180 then angle-=360 elseif angle< -180 then angle+=360 end
	self.angle=float(self.angle+angle)
	local amount=angle>0 and math.clamp(angle,1,4.5) or math.clamp(angle,-4.5,-1)
	local rope=self.rope
	if rope.active and (not rope.cut or rope.remaining>0) and #rope.bodies>=3 then
		if amount>0 and wheel.length(rope)<1650 then wheel.roll(rope,amount)
		elseif amount<0 and #rope.bodies>3 then wheel.rollBack(rope,-amount) end
	end
	self.last=point
end
function wheel:armScale()
	local rope=self.rope
	if not rope.active or (rope.cut and rope.remaining<=0) then return 0 end
	local length=wheel.length(rope)
	return length==0 and 0 or math.clamp(1-float(float(length*.7)/700),0,1.2)
end
function wheel:dragPointer(point)
	if not self.operating or point==self.last then return end
	if self.audio then self.audio:play("wheel") end
	self.audioPointerBatch=true
	local center=self.rope.anchor
	local first,last=self.last-center,point-center
	local start=math.atan2(first.Y,first.X)
	local angle=(math.atan2(last.Y,last.X)-start+math.pi)%(2*math.pi)-math.pi
	local steps=math.max(1,math.ceil(math.abs(math.deg(angle))/4.5))
	-- Roblox coalesces pointer moves. Recover the swept arc before DX's
	-- per-event clamp so a fast turn does not reel only one tiny increment.
	for index=1,steps-1 do
		local fraction=index/steps
		local radius=first.Magnitude+(last.Magnitude-first.Magnitude)*fraction
		local a=start+angle*fraction
		self:drag(center+Vector2.new(math.cos(a),math.sin(a))*radius)
	end
	self:drag(point)
	self.audioPointerBatch=nil
end
return wheel
