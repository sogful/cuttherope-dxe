-- GameScene.LoadRotatedCircles / Input / Update and RotatedCircle.SetSize.
local Math=require(script.Parent.DxMath)
local f=Math.float
local pi,tau=f(math.pi),f(math.pi*2)
local discs={}
discs.__index=discs
local function bound(angle)
	return angle>pi and f(angle-tau) or angle< -pi and f(angle+tau) or angle
end
local function degrees(angle) return f(f(angle*180)/pi) end
local function follows(rope) return not rope.mover and not rope.definition.rail and not rope.definition.ghost end
local function handles(d)
	local a=bound(Math.radians(d.angle))
	d.left=Math.around(d.point-Vector2.new(d.size*3,0),a,d.point)
	d.right=Math.around(d.point+Vector2.new(d.size*3,0),a,d.point)
end

function discs.new(physics,definitions,pumps)
	local self=setmetatable({physics=physics,pumps=pumps,objects={},order={},baselines={},bubbles={}},discs)
	for index,definition in ipairs(definitions or {}) do
		local d={index=index,point=definition.point,size=definition.size,angle=definition.angle,
			oneHandle=definition.oneHandle,radius=f(534*f(definition.size/167)),fade=.2,contained={}}
		handles(d)
		table.insert(self.objects,d) table.insert(self.order,d)
	end
	for index,point in ipairs(physics.bubbles) do self.bubbles[index]={point=point} end
	return self
end

function discs:press(point)
	for index,d in ipairs(self.order) do
		if d.copy then continue end
		local left,right=Math.length(point-d.left)<90,Math.length(point-d.right)<90
		if (left and not d.oneHandle) or right then
			d.activeLeft,d.activeRight,d.lastTouch=left,right,point
			self.held=d
			local nested,overlap=false,false
			for j=index+1,#self.order do
				local other=self.order[j]
				local distance=Math.length(other.point-d.point)
				if f(distance+other.radius)<=d.radius then nested=true end
				if distance<=f(d.radius+other.radius) then overlap=true end
			end
			if index<#self.order and overlap and not nested then
				local copy=table.clone(d)
				copy.copy,copy.fade,copy.activeLeft,copy.activeRight=true,0,false,false
				self.order[index]=copy
				d.fade=0
				table.insert(self.order,d)
			end
			return true
		end
	end
	return false
end

function discs:moveObject(object,point,d,previousAngle)
	local baseline=self.baselines[object]
	if not baseline or baseline.disc~=d then
		baseline={disc=d,point=point,angle=previousAngle}
		self.baselines[object]=baseline
	end
	return Math.around(baseline.point,bound(f(Math.radians(d.angle)-baseline.angle)),d.point)
end

function discs:drag(point)
	local d=self.held
	if not d then return false end
	local old=d.lastTouch-d.point
	local new=point-d.point
	local delta=f(f(math.atan2(new.Y,new.X))-f(math.atan2(old.Y,old.X)))
	local scratch=delta>0 and 1 or 2
	if math.abs(delta)>=.07 and d.soundPlaying~=scratch then
		d.soundPlaying=scratch
		if self.physics.audio then self.physics.audio:play(scratch==1 and "scratch_out" or "scratch_in") end
	end
	local previousAngle=Math.radians(d.angle)
	local turn=degrees(delta)
	d.angle=f(d.angle+turn)
	handles(d)
	for _,rope in ipairs(self.physics.ropes) do
		if follows(rope) and Math.length(rope.anchor-d.point)<=f(d.radius+5) then
			rope.anchor=self:moveObject(rope,rope.anchor,d,previousAngle)
			if rope.bodies[1] then rope.bodies[1].pos,rope.bodies[1].pin=rope.anchor,rope.anchor end
		end
	end
	for _,pump in ipairs(self.pumps) do
		if Math.length(pump.point-d.point)<=f(d.radius+5) then
			pump.point=self:moveObject(pump,pump.point,d,previousAngle)
			pump.angle=f(pump.angle+turn)
		end
	end
	for index,bubble in ipairs(self.bubbles) do
		if not self.physics.usedBubbles[index] and Math.length(bubble.point-d.point)<=f(d.radius+10) then
			bubble.point=self:moveObject(bubble,bubble.point,d,previousAngle)
			self.physics.bubbles[index]=bubble.point
		end
	end
	local target=self.physics.target
	local offset=target-d.point
	-- DX deliberately uses authored size here, NOT the rendered disc radius.
	if offset.X>=-d.size and offset.X<d.size and offset.Y>=-d.size and offset.Y<d.size then
		self.physics.target=Math.around(target,delta,d.point)
	end
	d.lastTouch=point
	self.physics:refresh()
	return true
end

function discs:release()
	if self.held then self.held.activeLeft,self.held.activeRight=false,false end
	self.held=nil
end

function discs:blocksCut(point)
	if self.held then return true end
	for _,d in ipairs(self.objects) do
		-- DX also protects the location of a hidden left handle in click-to-cut.
		if Math.length(point-d.left)<=90 or Math.length(point-d.right)<=90 then return true end
	end
	return false
end

function discs:update(delta)
	for index=#self.order,1,-1 do
		local d=self.order[index]
		d.fade=math.min(.216,d.fade+delta)
		if d.copy and d.fade>=.216 then table.remove(self.order,index) continue end
		local contained={}
		for _,rope in ipairs(self.physics.ropes) do
			if follows(rope) and Math.length(rope.anchor-d.point)<=f(d.radius+15) then contained[rope]=true end
		end
		for i,bubble in ipairs(self.bubbles) do
			if not self.physics.usedBubbles[i] and Math.length(bubble.point-d.point)<=f(d.radius+30) then contained[bubble]=true end
		end
		d.contained=contained
	end
end

function discs:shares(a,b)
	if a.point==b.point and a.size==b.size then return false end
	for object in pairs(a.contained) do if b.contained[object] then return true end end
	return false
end
function discs:sharesAny(d)
	for _,other in ipairs(self.order) do if self:shares(d,other) then return true end end
	return false
end
return discs
