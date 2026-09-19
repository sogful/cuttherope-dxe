-- Lantern.cs / LoadLanterns / GameScene.Update. Keep scene and object
-- dispatchers separate: release happens after integration, reveal before it.
local Math=require(script.Parent.DxMath)
local Mover=require(script.Parent.PathMover)
local f=Math.float
local lanterns={}
lanterns.__index=lanterns

local function truncate(p)
	local x,y=math.modf(p.X),math.modf(p.Y)
	return Vector2.new(x,y)
end

function lanterns.new(physics,definitions)
	local self=setmetatable({physics=physics,objects={},reveals={},captures=0,releases=0},lanterns)
	for _,d in ipairs(definitions or {}) do
		local object={point=d.point,previous=d.point,angle=d.angle or 0,state=0,phase="idle",age=0,
			mover=Mover.new(d.point,d.movement,d.angle or 0)}
		-- InitWithPosition resets the shared point for every authored lantern.
		self.shared=nil
		table.insert(self.objects,object)
		if d.captured then
			self.inLantern=true
			self:capture(object)
		end
	end
	return self
end

function lanterns:capture(object)
	if self.physics.audio then self.physics.audio:play("lantern_teleport_in") end
	local body=self.physics.candy
	self.shared=body
	body.disableGravity=true
	body.pos,body.previous=object.point,object.point
	self.captures+=1
	for _,other in ipairs(self.objects) do
		other.state,other.phase,other.age=1,"appear",0
		other.cooldown,other.releaseDelay=nil,nil
		other.fireStart,other.idleStart=f(.4*math.random()),f(.2+.2*math.random())
	end
end

function lanterns:beginCapture(object)
	local physics=self.physics
	physics.mice:remove(physics.candy)
	self.inLantern=true
	physics.candy.disableGravity=true
	self.visual={age=0,from=truncate(physics.candy.drawPosition or physics.candy.pos),to=truncate(object.point)}
	physics:releaseRopes(physics.candy,true)
	physics:popBubble(physics.candy)
	self.pending={object=object,delay=f(.05)}
end

function lanterns:advanceScene(delta)
	if self.pending then
		self.pending.delay=f(self.pending.delay-delta)
		if self.pending.delay<=0 then
			local ticket=self.pending
			self.pending=nil
			if self.inLantern and not self.physics.retired then self:capture(ticket.object) end
		end
	end
	-- A quick repeated touch queues more than one scene reveal in the source.
	for index=#self.reveals,1,-1 do
		self.reveals[index]=f(self.reveals[index]-delta)
		if self.reveals[index]<=0 then
			table.remove(self.reveals,index)
			self.inLantern=false
			self.visual=nil
		end
	end
end

function lanterns:advanceCandyVisual(delta)
	local visual=self.visual
	if not visual or visual.age>=f(.1) then return end
	visual.age=f(visual.age+delta)
	local progress=math.min(1,f(visual.age/f(.1)))
	self.physics.candy.drawPosition=visual.from+(visual.to-visual.from)*progress
end

function lanterns:touch(object,point)
	if object.state~=1 or not self.shared or Math.length(point-object.point)>=85 then return false end
	if self.physics.audio then self.physics.audio:play("lantern_teleport_out") end
	for _,other in ipairs(self.objects) do
		other.phase,other.age="hide",0
		other.cooldown,other.releaseDelay=f(.5),nil
	end
	object.releaseDelay=f(.01)
	table.insert(self.reveals,f(.1))
	return true
end

function lanterns:press(point)
	for index,object in ipairs(self.objects) do
		if self:touch(object,point) then self.lastPressed=index return true end
	end
	return false
end

function lanterns:update(delta)
	local physics=self.physics
	for _,object in ipairs(self.objects) do
		object.previous=object.point
		if object.mover then
			object.mover:update(delta)
			object.point,object.angle=object.mover.pos,object.mover.angle
		end
		object.age=f(object.age+delta)
		if object.cooldown then
			object.cooldown=f(object.cooldown-delta)
			if object.cooldown<=0 then object.state,object.cooldown=0,nil end
		end
		if object.releaseDelay then
			object.releaseDelay=f(object.releaseDelay-delta)
			if object.releaseDelay<=0 then
				object.releaseDelay=nil
				if self.shared then
					self.shared.disableGravity=false
					self.shared.pos,self.shared.previous=object.point,object.previous
					self.shared=nil
					self.releases+=1
				end
			end
		end
		-- Authored order matters: the last updated lantern owns the shared position.
		if self.shared then
			self.shared.pos,self.shared.previous=object.point,object.point
			object.state=1
		end
		if object.state==0 and not self.inLantern and not physics.retired and not physics.transport
			and not physics.split and not physics.disableCapture and Math.length(physics.candy.pos-object.point)<82 then
			self:beginCapture(object)
		end
	end
end

function lanterns:remove(body)
	if body~=self.physics.candy then return end
	self.pending,self.visual,self.inLantern=nil,nil,false
	table.clear(self.reveals)
	if self.shared~=body then return end
	self.shared=nil
	for _,object in ipairs(self.objects) do
		object.state,object.phase,object.age=0,"idle",0
		object.releaseDelay,object.cooldown=nil,nil
	end
end

return lanterns
