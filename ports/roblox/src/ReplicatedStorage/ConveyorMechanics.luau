local Math=require(script.Parent.DxMath)
local f=Math.float
local conveyors={}
conveyors.__index=conveyors
local function localpoint(b,p)
	local d=p-b.point
	return Vector2.new(f(f(b.c*d.X)-f(b.s*d.Y)),f(f(b.pc*d.X)+f(b.ps*d.Y)))
end
local function worldpoint(b,x,y)
	return Vector2.new(f(f(b.point.X+f(b.c*x))-f(b.s*y)),f(f(b.point.Y-f(b.s*x))-f(b.c*y)))
end
local function collides(b,p,r)
	local v=localpoint(b,p)
	return v.X>=-r and v.X<=f(b.length+r) and v.Y>=f(-b.width*.5-r) and v.Y<=f(b.width*.5+r)
end
function conveyors.move(position,delta,length)
	local value=f(position-delta)
	local span=f(length-36)
	local crossings=0
	if span>0 and value<18 then crossings=math.ceil(f(f(18-value)/span))
	elseif span>0 and value>f(length-18) then crossings=-math.ceil(f(f(value-f(length-18))/span)) end
	value=f(value+f(crossings*span))
	local side=value<f(length*.5) and 0 or 1
	return value,side==0 and value or f(length-value),side,crossings
end
function conveyors:get(item)
	local p,o=self.physics,item.object
	if item.kind=="bubble" then return p.bubbles[item.index]
	elseif item.kind=="star" then return p.starPositions[item.index]
	elseif item.kind=="hook" then return o.anchor
	elseif item.kind=="hat" then return o.point+Math.rotate(Vector2.new(-9,75)*(o.beltScale or .7),Math.radians(o.angle))
	elseif item.kind=="steam" then return o.point+Math.rotate(Vector2.new(0,f(f(168*.45)*(o.beltScale or 1))),Math.radians(o.angle))
	elseif item.kind=="pump" then return o.point+Math.rotate(Vector2.new(f(f(761*.01)*(o.beltScale or 1)),0),Math.radians(o.angle))
	end
	return o.point
end
function conveyors:set(item,point)
	local p,o=self.physics,item.object
	if item.kind=="bubble" then p.bubbles[item.index]=point
	elseif item.kind=="star" then p.starPositions[item.index]=point
	elseif item.kind=="hook" then o.anchor=point
	elseif item.kind=="hat" then o.point=point-Math.rotate(Vector2.new(-9,75)*(o.beltScale or .7),Math.radians(o.angle))
	elseif item.kind=="steam" then o.point=point-Math.rotate(Vector2.new(0,f(f(168*.45)*(o.beltScale or 1))),Math.radians(o.angle))
	elseif item.kind=="pump" then o.point=point-Math.rotate(Vector2.new(f(f(761*.01)*(o.beltScale or 1)),0),Math.radians(o.angle))
	else o.point=point end
end
function conveyors:sort()
	local last=#self.order
	for i=#self.order,1,-1 do
		if self.order[i].manual and self.order[i].active then
			for j=i,last-1 do self.order[j],self.order[j+1]=self.order[j+1],self.order[j] end
			last-=1
		end
	end
	last=#self.order
	for i=#self.order,1,-1 do
		if not self.order[i].manual then
			for j=i,last-1 do self.order[j],self.order[j+1]=self.order[j+1],self.order[j] end
			last-=1
		end
	end
end
function conveyors:bind(b,item)
	item.belt=b
	item.object.conveyor=item
	table.insert(b.items,item)
	local pos=localpoint(b,self:get(item)).X
	item.position=pos
	if pos<0 or pos>b.length then
		item.position=pos>=b.length*.5 and f(b.length-18) or 18
		self:set(item,worldpoint(b,item.position,0))
	end
	b.distributed=false
end
function conveyors:remove(item)
	if not item or not item.belt then return end
	local list=item.belt.items
	local index=table.find(list,item)
	if index then table.remove(list,index) end
	item.belt=nil
end
function conveyors.new(physics,definitions)
	local self=setmetatable({physics=physics,objects={},order={},items={},byKind={},revision=0,wraps=0,handoffs=0},conveyors)
	for i,d in ipairs(definitions or {}) do
		local angle=Math.radians(d.angle)
		-- ConveyorBelt uses Cosf/Sinf (MathF), not collision's Fm table.
		local c,s=f(math.cos(angle)),f(math.sin(angle))
		local perpendicular=f(-angle-f(f(math.pi)/2))
		local pc,ps=f(math.cos(perpendicular)),f(math.sin(perpendicular))
		local b={index=i,point=d.point,length=d.length,width=d.width,angle=d.angle,c=c,s=s,pc=pc,ps=ps,
			manual=d.manual,velocity=f(d.velocity),offset=0,delta=0,items={},active=false,activation=0,wraps=0}
		table.insert(self.objects,b) table.insert(self.order,b)
	end
	if #self.objects==0 then return self end
	self:sort()
	local function add(kind,index,object,radius,min,max)
		local item={kind=kind,index=index,object=object,radius=f(radius),min=f(min or .5),max=f(max or 1),scale=1}
		self.byKind[kind]=self.byKind[kind] or {}
		self.byKind[kind][index]=item
		table.insert(self.items,item)
		for _,b in ipairs(self.order) do if collides(b,self:get(item),f(item.radius*.6)) then self:bind(b,item) break end end
	end
	for i in ipairs(physics.bubbles) do add("bubble",i,{},85) end
	for i in ipairs(physics.starPositions) do add("star",i,{},60) end
	for i,o in ipairs(physics.bouncers.objects) do add("bouncer",i,o,40) end
	for i,o in ipairs(physics.mechanics.hats) do add("hat",i,o,90,.35,.7) end
	for i,o in ipairs(physics.steam.objects) do add("steam",i,o,52.5,.7,1) end
	for i,o in ipairs(physics.mechanics.pumps) do add("pump",i,o,f(761*.13)) end
	for i,o in ipairs(physics.ropes) do if not o.mover and not o.definition.rail and not o.definition.ghost then add("hook",i,o,40) end end
	return self
end
function conveyors:handoff(moving)
	for _,owner in ipairs(self.order) do
		if owner==moving then continue end
		for i=#owner.items,1,-1 do
			local item=owner.items[i]
			if owner.manual and collides(moving,self:get(item),f(item.radius*.6)) and (not moving.manual or moving.activation>=owner.activation) then
				self:remove(item) self:bind(moving,item) self.handoffs+=1
				if self.physics.audio then self.physics.audio:play("transporter_move") end
			end
		end
	end
end
function conveyors:wrap(item)
	self.wraps+=1 item.belt.wraps+=1
	if self.physics.audio then self.physics.audio:play("transporter_drop") end
	if item.kind~="hook" then return end
	local rope=item.object
	if not rope.active then return end
	if (rope.definition.radius or -1)<0 then
		for _,other in ipairs(self.physics.ropes) do
			if other~=rope and other.active and not other.cut and other.tail==rope.tail then self.physics:sever(other,#other.bodies-1) end
		end
	end
	if not rope.cut then
		local offset=rope.anchor-rope.bodies[1].pos
		for _,body in ipairs(rope.bodies) do
			body.pos+=offset
			if body.previous then body.previous+=offset end
			if body.pin then body.pin+=offset end
		end
	end
end
function conveyors:movebelt(b,delta)
	b.offset=f(b.offset+delta)
	while b.offset>b.length do b.offset=f(b.offset-63) end
	while b.offset<0 do b.offset=f(b.offset+63) end
	for _,item in ipairs(b.items) do
		local sideOffset=localpoint(b,self:get(item)).Y
		local pos,distance,side,crossings=conveyors.move(item.position,delta,b.length)
		item.position=pos
		if crossings~=0 then b.distributed=false end
		local scale=item.max
		if distance<f(item.radius*item.max) then
			scale=f(item.min+f(f(distance*f(item.max-item.min))/f(item.radius*item.max)))
			pos=side==1 and f(b.length-f(scale*item.radius)) or f(scale*item.radius)
		end
		item.scale,item.object.beltScale=scale,scale
		self:set(item,worldpoint(b,pos,sideOffset))
		if crossings~=0 then self:wrap(item) end
	end
	self:handoff(b)
end
function conveyors:align(b)
	b.align=nil
	local nearest=math.huge
	for _,item in ipairs(b.items) do
		local right=item.position>=f(b.length*.5)
		local d=right and f(b.length-item.position) or item.position
		if d<item.radius and d<nearest then nearest=d b.align=right and 1 or -1 end
	end
end
function conveyors:distribute(b,dt)
	if b.distributed or #b.items<2 then return end
	b.distributed=true
	local function push(item,pos,d)
		local nextpos=f(pos+d)
		if nextpos<=18 or nextpos>=f(b.length-18) then nextpos=pos<b.length*.5 and 18 or f(b.length-18) end
		item.position=nextpos
	end
	for i,a in ipairs(b.items) do for j=i+1,#b.items do
		local v=b.items[j]
		local required=f(f(a.radius+v.radius)+6)
		local pa,pb=a.position,v.position
		local difference=f(pa-pb)
		local distance=math.abs(difference)
		if math.abs(f(required-distance))>=1 and distance<required then
			local norm=distance<=.0001 and 1 or f(difference/distance)
			local amount=f(f(f(required-distance)*norm)*dt)
			push(a,pa,f(amount*10)) push(v,pb,f(amount*-10)) b.distributed=false
		end
	end end
	if not b.distributed then self:movebelt(b,0) end
end
function conveyors:update(dt)
	if #self.objects==0 then return end
	for _,item in ipairs(self.byKind.bubble or {}) do if self.physics.usedBubbles[item.index] then self:remove(item) end end
	for _,b in ipairs(self.order) do
		if not b.manual then b.delta=f(dt*b.velocity) self:movebelt(b,b.delta) end
		b.active=math.abs(b.delta)>3
		if b.manual and b.active then
			b.audioTravel=(b.audioTravel or 0)+math.abs(b.delta)
			if b.audioTravel>=45 then
				b.audioTravel=0
				if self.physics.audio then self.physics.audio:randomSound({"con01","con02","con03","con04"}) end
			end
		end
		if b.manual and self.held~=b then
			if math.abs(b.delta)<=3 then b.delta=0 if not b.align then self:align(b) end
			else b.delta=f(b.delta*.75) if b.active then self:movebelt(b,b.delta) end end
		end
		for _,item in ipairs(b.items) do
			local p=localpoint(b,self:get(item))
			if math.abs(p.Y)>.01 then self:set(item,worldpoint(b,p.X,math.abs(p.Y)<=2 and 0 or f(p.Y*.8))) end
		end
		self:distribute(b,dt)
		if b.align then self:movebelt(b,f(f(b.align*240)*dt)) b.align=nil end
	end
	self:sort()
end
function conveyors:press(point)
	if self.held then return false end
	local candidates={}
	for _,b in ipairs(self.order) do if b.manual then table.insert(candidates,b) end end
	table.sort(candidates,function(a,b) return a.activation>b.activation end)
	for _,b in ipairs(candidates) do
		b.align=nil
		if collides(b,point,0) then
			self.revision+=1 b.activation=self.revision b.last=localpoint(b,point) b.delta=0 self.held=b return true
		end
	end
	return false
end
function conveyors:cancel()
	self.held=nil
	for _,b in ipairs(self.objects) do if b.manual then b.delta,b.active,b.align=0,false,nil end end
end
function conveyors:drag(point)
	local b=self.held if not b then return false end
	local p=localpoint(b,point)
	b.delta=f(b.last.X-p.X) self:movebelt(b,b.delta) b.last=p self.physics:refresh() return true
end
function conveyors:release(point)
	local b=self.held if not b then return end
	self.held=nil
	if not point then b.delta=0 b.active=false b.align=nil return end
	b.delta=f(b.last.X-localpoint(b,point).X)
	if math.abs(b.delta)<=3 then b.delta=0 if not b.align then self:align(b) end end
end
conveyors.localpoint,conveyors.worldpoint,conveyors.collides=localpoint,worldpoint,collides
return conveyors
