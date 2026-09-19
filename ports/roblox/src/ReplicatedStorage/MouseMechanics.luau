-- Mouse.cs / MiceObject.cs. Shared animation ownership follows authored update
-- order; handoff to a later-authored hole updates that mouse in this same tick.
local Math=require(script.Parent.DxMath)
local f=Math.float
local mice={}
mice.__index=mice
local sequences={entry={1,2,3,14},entryCandy={17,19,21,24},exit={14,15,16,18},exitCandy={24,26,28,18}}

local function path(object,kind)
	object.path,object.pathAge,object.offset=kind,0,object[kind][1]
end

local function animation(object,phase)
	object.phase,object.age=phase,0
	object.quad=sequences[phase] and sequences[phase][1] or (phase=="idle" and 4 or 24)
end

function mice.new(physics,definitions)
	local self=setmetatable({physics=physics,objects={},captures=0,releases=0,handoffs=0},mice)
	for i,d in ipairs(definitions or {}) do
		local angle=d.angle or 0
		local object={point=d.point,index=d.index or i,angle=angle,radius=d.radius or 240,duration=f(d.duration or 3),
			active=false,retreating=false,elapsed=0,entry={},exit={},offset=Vector2.zero,quad=18,age=0}
		for _,y in ipairs({-4.4,-61,-70,-66}) do table.insert(object.entry,Math.rotate(Vector2.new(0,y),Math.radians(angle))) end
		for _,y in ipairs({-36.4,-43.2,-9.2}) do table.insert(object.exit,Math.rotate(Vector2.new(0,y),Math.radians(angle))) end
		table.insert(self.objects,object)
		if object.index==1 or not self.active then
			local carry=self.active and self.active.carry
			if self.active then self.active.carry=nil end
			self:spawn(object,carry)
		end
	end
	self.ordered=table.clone(self.objects)
	table.sort(self.ordered,function(a,b) return a.index<b.index end)
	return self
end

function mice:spawn(object,carry)
	if self.physics.audio then self.physics.audio:play("mouse_rustle") end
	self.active=object
	-- Spawn changes Container.parent but does not remove it from the previous
	-- group's child table. A fallback hole registered before index 1 therefore
	-- advances the same animation twice until that shared reference is removed.
	object.hasContainer=true
	object.carry,object.active,object.retreating,object.elapsed=carry,false,false,0
	object.grabbing,object.bounce,object.eyes=false,nil,nil
	animation(object,carry and "entryCandy" or "entry")
	if carry then self:attach(object,carry) end
end

function mice:attach(object,body)
	object.carry=body
	body.disableGravity,body.velocity=true,Vector2.zero
	body.pos=object.point+object.entry[4]
	body.previous=body.pos
	-- A carried candy is parked. Stop the leftover rope-spin coast on capture
	-- and handoff; retain its current facing instead of spinning for seconds.
	body.residual=0
	path(object,"entry")
	object.grabbing=true
end

function mice:grab(object,body)
	self.physics:releaseRopes(body,true)
	self:attach(object,body)
	object.quad,object.bounce=24,0
	self.captures+=1
	if self.physics.audio then self.physics.audio:play("mouse_idle") end
end

function mice:drop(object)
	local body=object.carry
	if not body then return false end
	body.disableGravity=self.physics.lanterns.inLantern==true
	body.previous=body.pos
	object.carry,object.grabbing=nil,false
	self.releases+=1
	return true
end

function mice:retreat(object)
	if not object or object.retreating then return end
	if not object.carry then object.eyes=nil end
	object.retreating,object.active,object.elapsed,object.grabbing=true,false,0,false
	object.bounce=nil
	path(object,"exit")
	animation(object,object.carry and "exitCandy" or "exit")
end

function mice:advance()
	if self.locked or not self.active then return end
	local current=self.active
	local index=table.find(self.ordered,current)
	local nextMouse=self.ordered[index%#self.ordered+1]
	local carry=current.carry
	current.carry=nil
	self:spawn(nextMouse,carry)
	self.handoffs+=1
end

function mice:press(point)
	local object=self.active
	if not object or not object.active or object.retreating or not object.carry or Math.length(point-object.point)>=object.radius then return false end
	self:drop(object)
	self:retreat(object)
	if self.physics.audio then self.physics.audio:play("mouse_tap") end
	return true
end

function mice:remove(body)
	if self.active and self.active.carry==body then self:drop(self.active) self:retreat(self.active) end
end

function mice:shutdown()
	for _,object in ipairs(self.objects) do self:drop(object) end
	self:retreat(self.active)
	self.locked=true
	if self.active then self.active.active,self.active.retreating=false,true end
end

function mice:update(delta)
	for _,object in ipairs(self.objects) do
		if object.hasContainer then
			local owner=self.active
			owner.age=f(owner.age+delta)
			local sequence=sequences[owner.phase]
			if sequence then
				owner.quad=sequence[math.min(4,math.floor((owner.age+1e-7)/f(.05))+1)]
				if owner.age>=f(.15)-1e-6 then
					local phase=owner.phase
					if phase=="entry" or phase=="entryCandy" then
						owner.elapsed,owner.active=0,true
						if phase=="entryCandy" then animation(owner,"idleCandy")
						elseif math.random(0,1)==1 then animation(owner,"idle") owner.eyes=0
						else owner.phase="hold" end
					else
						owner.phase,owner.hasContainer="hidden",false
						self:advance()
					end
				end
			end
			owner=self.active
			if owner.eyes then owner.eyes=f(owner.eyes+delta) end
			if owner.bounce then
				owner.bounce=f(owner.bounce+delta)
				if owner.bounce>=f(.15)-1e-6 then owner.bounce=nil end
			end
		end
		if object.path then
			local offsets=object[object.path]
			local duration=f((#offsets-1)*f(.05))
			object.pathAge=f(object.pathAge+delta)
			if object.pathAge>=duration then
				object.offset=offsets[#offsets]
				object.path,object.grabbing=nil,false
			else
				local index=math.floor(object.pathAge/f(.05))+1
				local start,finish=f((index-1)*f(.05)),f(index*f(.05))
				local t=f(f(object.pathAge-start)/f(finish-start))
				object.offset=offsets[index]+(offsets[index+1]-offsets[index])*t
			end
		end
		if object.carry then
			object.carry.pos=object.point+object.offset
			object.carry.previous=object.carry.pos
		end
		if object.active and not object.retreating and not object.grabbing then
			object.elapsed=f(object.elapsed+delta)
			if object.elapsed>=object.duration and not object.bounce then self:retreat(object) end
		end
	end
	local p,object=self.physics,self.active
	if object and object.active and not object.carry and not p.retired and not p.transport and not p.disableCapture and not p.split and not p.lanterns.inLantern
		and Math.length(p.candy.pos-object.point)<object.radius then self:grab(object,p.candy) end
end

return mice
