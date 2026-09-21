local Mover=require(script.Parent.PathMover)
local Drawing=require(script.Parent.RopeDrawing)
local Hazards=require(script.Parent.SpikeHazards)
local Wheel=require(script.Parent.WheelControl)
local Discs=require(script.Parent.DiscMechanics)
local Math=require(script.Parent.DxMath)
local mechanics={}
mechanics.__index=mechanics

local function rotate(point,angle)
	local c,s=math.cos(angle),math.sin(angle)
	return Vector2.new(point.X*c-point.Y*s,point.X*s+point.Y*c)
end

function mechanics.new(physics,level)
	local self=setmetatable({physics=physics,pumps={},hats={},spiders={},time=0,gravityButtons=level.gravityButtons or {}},mechanics)
	for _,definition in ipairs(level.pumps or {}) do
		table.insert(self.pumps,{point=definition.point,angle=definition.angle,timer=0,fired=-100,shots=0})
	end
	for _,definition in ipairs(level.socks or {}) do
		local motion=Mover.new(definition.point,definition.movement,definition.angle)
		if motion then motion.useInitialAngle=definition.resetAngle end
		table.insert(self.hats,{point=definition.point,angle=definition.angle,group=definition.group,
			mover=motion,timeout=0,state="idle",flash=-100})
	end
	for index,rope in ipairs(physics.ropes) do
		if rope.definition.movement then
			rope.mover=Mover.new(rope.anchor,rope.definition.movement,0)
			rope.beeAngle,rope.beeAge=0,0
		end
		if rope.definition.wheel then rope.wheel=Wheel.new(rope) end
		if rope.definition.spider then
			self.spiders[index]={state=rope.active and "arming" or "dormant",distance=0,age=0,
				point=rope.anchor,angle=0,quad=0}
		end
	end
	self.discs=Discs.new(physics,level.discs,self.pumps)
	return self
end

function mechanics:press(point)
	if self.physics.mice:press(point) then return true end
	if self.physics.steam:press(point) then return true end
	if self:gravityButtonAt(point) then self.heldGravity=true return true end
	for index,object in ipairs(self.physics.hazards.objects) do
		if self.physics.hazards:buttonContains(index,point) then
			self.heldSpike=index
			object.pressed=true
			return true
		end
	end
	for _,pump in ipairs(self.pumps) do
		local localpoint=rotate(point-pump.point,-math.rad(pump.angle))
		if localpoint.X>=-80.5 and localpoint.X<94.5 and localpoint.Y>=-80.5 and localpoint.Y<94.5 then
			pump.timer=.05
			self.heldPump,self.start=pump,point
			return true
		end
	end
	if self.physics.lanterns:press(point) then return true end
	if self.discs:press(point) then return true end
	if self.physics.ghosts:press(point) then return true end
	for _,rope in ipairs(self.physics.ropes) do
		if rope.wheel and rope.wheel:begin(point) then self.heldWheel=rope.wheel return true end
		local d=point-rope.anchor
		if rope.definition.rail and d.X>=-65 and d.X<65 and d.Y>=-65 and d.Y<65 then
			self.heldRail=rope
			return true
		end
	end
	return self.physics.conveyors:press(point)
end

function mechanics:drag(point)
	if self.physics.conveyors:drag(point) then return end
	if self.discs:drag(point) then return end
	if self.heldWheel then self.heldWheel:dragPointer(point) self.physics:refresh() return end
	if self.heldPump and (point-self.start).Magnitude>10 then self.heldPump.timer=0 end
	local rope=self.heldRail
	if rope then
		local rail=rope.definition.rail
		local origin=rope.definition.anchor
		if rail.vertical then
			rope.anchor=Vector2.new(origin.X,math.clamp(point.Y,origin.Y-rail.offset,origin.Y+rail.length-rail.offset))
		else
			rope.anchor=Vector2.new(math.clamp(point.X,origin.X-rail.offset,origin.X+rail.length-rail.offset),origin.Y)
		end
		if rope.active then rope.bodies[1].pos,rope.bodies[1].pin=rope.anchor,rope.anchor end
	end
end

function mechanics:gravityButtonAt(point)
	if not point then return false end
	for _,position in ipairs(self.gravityButtons) do
		local d=point-position
		if d.X>=-115.5 and d.X<115.5 and d.Y>=-116.5 and d.Y<116.5 then return true end
	end
	return false
end

function mechanics:toggleNearestGravity(center)
	local nearest,distance=nil,math.huge
	for index,position in ipairs(self.gravityButtons) do
		local difference=position-center
		local squared=difference:Dot(difference)
		if squared<distance then nearest,distance=index,squared end
	end
	if not nearest then return false end
	self.lastGravityButton=nearest
	self.physics:toggleGravity()
	return true
end

function mechanics:release(point)
	self.physics.conveyors:release(point)
	self.discs:release()
	if self.heldSpike then
		local hazards=self.physics.hazards
		local object=hazards.objects[self.heldSpike]
		object.pressed=false
		if hazards:buttonContains(self.heldSpike,point,15) then
			hazards:rotateGroup(object.group)
			if self.physics.audio then self.physics.audio:play(object.normal and "spike_rotate_in" or "spike_rotate_out") end
		end
		self.heldSpike=nil
	end
	if self.heldGravity and self:gravityButtonAt(point) then self.physics:toggleGravity() end
	if self.heldWheel then self.heldWheel.operating=false end
	self.heldGravity,self.heldWheel=nil,nil
	self.heldRail,self.heldPump=nil,nil
end

function mechanics:moveHook(rope,delta)
	if not rope.mover then return end
	rope.mover:update(delta)
	rope.anchor=rope.mover.pos
	if rope.active and rope.bodies[1] then rope.bodies[1].pos,rope.bodies[1].pin=rope.anchor,rope.anchor end
	local direction=rope.mover.path[rope.mover.target]-rope.mover.pos
	local target=direction.X>15 and 10 or direction.X< -15 and -10 or 0
	rope.beeAngle+=math.clamp(target-rope.beeAngle,-60*delta,60*delta)
	rope.beeAge+=delta
end

function mechanics:fire(pump)
	pump.fired,pump.shots=self.time,pump.shots+1
	local physics=self.physics
	if physics.audio then physics.audio:randomSound({"pump_1","pump_2","pump_3","pump_4"}) end
	if physics.disableCapture then return end
	for _,body in ipairs(physics:activeBodies()) do
		local localpoint=rotate(body.pos-pump.point,-math.rad(pump.angle))
		if localpoint.Y<0 and localpoint.Y+87.5>=-624 and math.abs(localpoint.X)<175 then
			local strength=2*(624+localpoint.Y)
			body.pos+=rotate(Vector2.new(0,-strength),math.rad(pump.angle))*.016
		end
	end
end

function mechanics:bust(index)
	local spider=self.spiders[index]
	if spider and (spider.state=="arming" or spider.state=="walking") then
		if self.physics.audio then self.physics.audio:play("spider_fall") end
		spider.state,spider.fell,spider.origin,spider.quad="busted",self.time,spider.point,11
		spider.angle,spider.fallRotation=0,math.random(-120,120)
		spider.fallSign=self.physics.gravityInverted and -1 or 1
	end
end

function mechanics:spider(index,spider,delta)
	local rope=self.physics.ropes[index]
	if spider.state=="dormant" then
		spider.point=rope.anchor
		if rope.active and not rope.cut and not self.physics.retired then spider.state="arming" end
		return
	end
	if spider.state=="arming" then
		spider.state,spider.age="walking",-delta
		if self.physics.audio then self.physics.audio:play("spider_activate") end
	end
	if spider.state~="walking" then
		if spider.fell then
			local age=self.time-spider.fell
			local jump=spider.state=="won" and 70 or 50
			local start=spider.state=="won" and -10 or 0
			local peak=-jump*(spider.fallSign or 1)
			local finish=1440*(spider.fallSign or 1)
			local y=age<.3 and start+(peak-start)*(1-(1-age/.3)^2) or peak+(finish-peak)*math.min(1,(age-.3))^2
			spider.point=spider.origin+Vector2.new(0,y)
			spider.angle=(spider.fallRotation or 0)*math.min(1,age)
			spider.hidden=age>=1.3
		end
		return
	end
	spider.age+=delta
	-- SetDelay(5, .4) delays arrival at frame 5, holding frame 4.
	if spider.age<.6 then
		spider.quad=math.min(4,math.floor(spider.age/.05))
	elseif spider.age<.65 then spider.quad=5
	elseif spider.age<.7 then spider.quad=6
	else
		spider.walkAge=spider.walkAge and spider.walkAge+delta or 0
		local phase=spider.walkAge%.4
		-- Timeline wraps after evaluating its last key, retaining quad 10 that tick.
		if phase<1e-6 and spider.walkAge>0 then phase=.4 end
		spider.quad=7+math.min(3,math.floor(phase/.1))
		spider.distance+=117*delta
	end
	local samples=Drawing.samples(rope.points)
	local traversed=0
	for i=1,#samples do
		local first=samples[i]
		local last=samples[i+1] or first
		local length=math.max(70,(last-first).Magnitude)
		if spider.distance<traversed+length or i==#samples then
			spider.point=first+(last-first)*((spider.distance-traversed)/length)
			if spider.age>=.7 then spider.angle=math.deg(math.atan2((last-first).Y,(last-first).X))+270 end
			if i==#samples and not self.physics.retired and not self.physics.transport then
				spider.state,spider.fell,spider.origin,spider.quad="won",self.time,spider.point,12
				spider.angle=0
				spider.fallSign=self.physics.gravityInverted and -1 or 1
				self.physics.stolen=index
				if self.physics.audio then self.physics.audio:play("spider_win") end
				self.physics:retireCandy()
			end
			break
		end
		traversed+=length
	end
end

function mechanics:advanceTransport(delta)
	-- DelayedDispatcher fires before this frame's integration in GameScene.Update.
	local physics=self.physics
	local bodies={physics.candy}
	for _,b in ipairs(physics.bulbs) do table.insert(bodies,b) end
	for _,candy in ipairs(bodies) do
	local transport=candy==physics.candy and physics.transport or candy.transport
	if not transport then continue end
	transport.time-=delta
	if transport.time<=0 then
		local hat=transport.exit
		local angle=math.rad(hat.angle)
		candy.pos=hat.point+rotate(Vector2.new(0,-16),angle)
		candy.velocity=rotate(Vector2.new(0,-transport.speed),angle)
		candy.previous=candy.pos-candy.velocity/60
		if #physics.bulbs>0 then
			angle=Math.radians(hat.angle)
			candy.pos=hat.point+Math.rotate(Vector2.new(0,-16),angle)
			candy.velocity=Math.rotate(Vector2.new(0,-1),angle)*Math.float(transport.speed)
			candy.previous=candy.pos-Vector2.new(Math.float(candy.velocity.X/60),Math.float(candy.velocity.Y/60))
		end
		hat.flash=self.time+delta
		if candy==physics.candy then physics.transport=nil else candy.transport=nil end
		physics.teleports=(physics.teleports or 0)+1
	end
	end
end

function mechanics:tick(delta)
	self.discs:update(delta)
	self.time+=delta
	for _,pump in ipairs(self.pumps) do
		if pump.timer>0 then
			pump.timer=math.max(0,pump.timer-delta)
			if pump.timer==0 then self:fire(pump) end
		end
	end
	for index,spider in pairs(self.spiders) do self:spider(index,spider,delta) end
	self.physics.steam:update(delta)
	self.physics.lanterns:update(delta)
	self.physics.mice:update(delta)
	local physics=self.physics
	for _,hat in ipairs(self.hats) do
		if hat.mover then hat.mover:update(delta) hat.point,hat.angle=hat.mover.pos,hat.mover.angle end
		if hat.timeout>0 then
			hat.timeout=math.max(0,hat.timeout-delta)
			if hat.timeout==0 then hat.state="idle" end
		end
	end
	if physics.disableCapture then return end
	for _,hat in ipairs(self.hats) do
		for _,body in ipairs(physics:activeBodies()) do
		if body.part or (body==physics.candy and physics.lanterns.inLantern) then continue end
		local angle=math.rad(hat.angle)
		local p=hat.point
		local one,two=p+rotate(Vector2.new(-90,0),angle),p+rotate(Vector2.new(50,0),angle)
		local band=rotate(Vector2.new(0,15),angle)
		local motion=rotate(body.velocity,-angle)
		if hat.state=="idle" and motion.Y>=0 and (Hazards.linebox(one,two,body.pos,20)
			or Hazards.linebox(one+band,two+band,body.pos,20)) then
			for _,exit in ipairs(self.hats) do
				if exit~=hat and exit.group==hat.group then
					physics.mice:remove(body)
					local speed=body.velocity.Magnitude*.9*1.4
					if #physics.bulbs>0 then speed=Math.float(Math.float(Math.float(.9)*Math.length(body.velocity))*Math.float(1.4)) end
					local transport={time=.1,exit=exit,speed=speed}
					if body==physics.candy then physics.transport=transport else body.transport=transport end
					physics:releaseRopes(body,#physics.bulbs>0)
					exit.state,exit.timeout,hat.flash="throwing",.8,self.time
					if physics.audio then physics.audio:play("teleport") end
					return
				end
			end
		end
		end
	end
end

mechanics.rotate=rotate
return mechanics
