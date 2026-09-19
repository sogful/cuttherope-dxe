local hazards={}
local Mover=require(script.Parent.PathMover)
local Dx=require(script.Parent.DxMath)
local f=Dx.float
hazards.__index=hazards
local widths={212,333,453,566,433}
local rotatableWidths={202,319,444,559}

local function linebox(a,b,point,radius)
	local first,last=0,1
	for _,axis in ipairs({"X","Y"}) do
		local delta=b[axis]-a[axis]
		local low,high=point[axis]-radius-a[axis],point[axis]+radius-a[axis]
		if math.abs(delta)<1e-12 then
			if low>0 or high<0 then return false end
		else
			local t,u=low/delta,high/delta
			first,last=math.max(first,math.min(t,u)),math.min(last,math.max(t,u))
			if first>last then return false end
		end
	end
	return true
end

local function lineline(a,b,c,d)
	-- CTRMathHelper.LineInLine, including its original collinear behavior.
	local dp,qa,qb=c-a+d-b,b-a,d-c
	local determinant=qa.Y*qb.X-qb.Y*qa.X
	return math.abs(qb.X*dp.Y-qb.Y*dp.X)<=math.abs(determinant)
		and math.abs(qa.X*dp.Y-qa.Y*dp.X)<=math.abs(determinant)
end

function hazards.hits(topone,toptwo,bottomone,bottomtwo,point,previous,radius)
	radius=radius or 15
	return linebox(topone,toptwo,point,radius) or linebox(bottomone,bottomtwo,point,radius)
		or lineline(previous,point,topone,toptwo) or lineline(previous,point,bottomone,bottomtwo)
end

function hazards.new(definitions)
	local self=setmetatable({bars={},objects={}},hazards)
	for _,definition in ipairs(definitions or {}) do
		local half=assert((definition.group~=nil and rotatableWidths or widths)[definition.size])*.5
		local object={point=definition.point,angle=definition.angle,half=half,
			origAngle=definition.angle,group=definition.group,normal=false,
			mover=Mover.new(definition.point,definition.movement,definition.angle),electric=definition.electric,on=false,
			timer=definition.electric and definition.electric.off+definition.electric.delay or 0,clock=0}
		table.insert(self.objects,object)
		table.insert(self.bars,{})
		self:rebuild(#self.objects)
	end
	return self
end

function hazards:rebuild(index)
	local object=self.objects[index]
	local angle=Dx.radians(object.angle)
	local p,bar=object.point,self.bars[index]
	bar[1]=Dx.around(p+Vector2.new(-object.half,-5),angle,p)
	bar[2]=Dx.around(p+Vector2.new(object.half,-5),angle,p)
	bar[3]=Dx.around(p+Vector2.new(-object.half,5),angle,p)
	bar[4]=Dx.around(p+Vector2.new(object.half,5),angle,p)
end

function hazards:buttonContains(index,point,padding)
	local object=self.objects[index]
	if not point or not object.group or object.group<=0 then return false end
	local d=point-object.point
	padding=padding or 0
	-- Button.IsInTouchZone uses unrotated draw bounds and integer half-extents.
	return d.X>=-99.5-padding and d.X<106.5+padding and d.Y>=-104-padding and d.Y<104+padding
end

function hazards:rotateGroup(group)
	for _,object in ipairs(self.objects) do
		if object.group==group then
			object.normal=not object.normal
			local target=object.origAngle+(object.normal and 90 or 0)
			object.turn={age=0,first=math.modf(object.angle),last=math.modf(target),duration=f(f(math.abs(f(target-object.angle))/90)*f(.3))}
			object.angle=object.turn.first
		end
	end
end

function hazards:update(delta)
	for index,object in ipairs(self.objects) do
		object.clock+=delta
		if object.turn then
			local turn=object.turn
			turn.age=f(turn.age+delta)
			local progress=turn.duration==0 and 1 or math.min(1,f(turn.age/turn.duration))
			object.angle=f(turn.first+f((turn.last-turn.first)*progress))
			if progress==1 then object.turn=nil end
			self:rebuild(index)
		end
		if object.electric then
			object.timer=math.max(0,object.timer-delta)
			if object.timer==0 then
				object.on=not object.on
				object.timer=object.on and object.electric.on or object.electric.off
				object.clock=0
			end
		end
		if object.mover then
			object.mover:update(delta)
			object.point,object.angle=object.mover.pos,object.mover.angle
			self:rebuild(index)
		end
	end
end

function hazards:hit(point,previous)
	for index,bar in ipairs(self.bars) do
		local object=self.objects[index]
		if (not object.electric or object.on) and hazards.hits(bar[1],bar[2],bar[3],bar[4],point,previous) then return index end
	end
	return nil
end

hazards.linebox=linebox
return hazards
