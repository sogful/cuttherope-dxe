local Math=require(script.Parent.DxMath)
local f=Math.float
local ghosts={}
ghosts.__index=ghosts

function ghosts.new(physics,definitions)
	local self=setmetatable({physics=physics,objects={},apps={},bubbleApps={},time=0,serial=0},ghosts)
	for index,d in ipairs(definitions or {}) do
		table.insert(self.objects,{index=index,point=d.point,forms=bit32.bor(d.forms,1),radius=d.radius,angle=d.angle,
			form=1,age=0,idleAge=0,idleAppearing=true,phase=math.random(),morphs=0})
	end
	return self
end

function ghosts:bubbleOwner(app)
	local body=app and app.owner
	if not body then return nil end
	local p=self.physics
	local index=body==p.candy and p.bubbleIndex or body.bubbleIndex
	if p:hasBubble(body) and index==app.index then return body end
	if self.parked==app then return body end
	return nil
end

function ghosts:reset(g,form)
	assert(bit32.band(g.forms,form)~=0,"Ghost form unavailable")
	local p,old=self.physics,g.app
	if old then
		old.retiring,old.retireAge=true,0
		if old.form==2 then p.usedBubbles[old.index]=true
		elseif old.form==4 and old.rope.active then
			local r=old.rope
			r.cut,r.cutIndex,r.split=true,r.cutIndex or 0,r.split or 1
			r.remaining,r.pendingCut=.36,(r.cutIndex or 0)+1
		end
	elseif g.idleAppearing then g.idleAppearing,g.idleAge=false,0 end
	g.form,g.age,g.app=form,0,nil
	g.morphs+=1
	if form==1 then g.idleAppearing,g.idleAge=true,0 return end
	self.serial+=1
	local app={ghost=g,form=form,age=0,serial=self.serial,point=g.point}
	g.app=app
	table.insert(self.apps,app)
	if form==2 then
		local index=#p.bubbles+1
		for slot,previous in pairs(self.bubbleApps) do if previous.removed then index=slot break end end
		p.bubbles[index],p.usedBubbles[index]=g.point,false
		app.index=index
		self.bubbleApps[index]=app
		table.insert(p.bubbleOrder,index)
	elseif form==4 then
		local r={definition={anchor=g.point,radius=g.radius,ghost=true},anchor=g.point,bodies={},points={},
			cut=false,remaining=2,active=false,captured=false,radiusAlpha=1,ghostApp=app}
		table.insert(p.ropes,r)
		app.rope=r
		if g.radius==-1 then
			local tail,distance=p.candy,math.huge
			for _,body in ipairs(p:activeBodies()) do
				if body.part and Math.length(body.pos-g.point)<distance then tail,distance=body,Math.length(body.pos-g.point) end
			end
			local length=Math.length(tail.pos-g.point)
			p:attach(r,length>0 and length or 105,tail)
		end
	else
		local object={point=g.point,angle=g.angle,size=1,hit=-100,hits=0,ghostApp=app}
		table.insert(p.bouncers.objects,object)
		app.bouncer=object
	end
	p:refresh()
	if p.audio then p.audio:play("ghost_puff") end
end

function ghosts:touch(g,point)
	if Math.length(point-g.point)<80 and not (g.form==2 and self:bubbleOwner(g.app)) then
		if g.forms~=1 then
			local nextform=g.form*2
			for _=1,4 do
				if nextform>=16 then nextform=2 end
				if bit32.band(g.forms,nextform)~=0 then break end
				nextform*=2
			end
			if nextform~=g.form then
				self:reset(g,nextform)
			end
		end
		return true
	end
	return false
end

function ghosts:press(point)
	for _,g in ipairs(self.objects) do if self:touch(g,point) then return true end end
	return false
end

function ghosts:release(index)
	local app=index and self.bubbleApps[index]
	if app and app.ghost.app==app then self:reset(app.ghost,1) end
end

function ghosts:releaseBody(body)
	local p=self.physics
	self:release(body==p.candy and p.bubbleIndex or body.bubbleIndex)
	if self.parked and self.parked.owner==body then self:release(self.parked.index) self.parked=nil end
end

function ghosts:capture(body,index)
	local p=self.physics
	if p:hasBubble(body) then self:releaseBody(body) end
	local app=self.bubbleApps[index]
	if app then app.owner=body end
end

function ghosts:merge(left,right)
	local l=left.bubble and self.bubbleApps[left.bubbleIndex]
	local r=right.bubble and self.bubbleApps[right.bubbleIndex]
	local chosen=l or r
	if chosen then
		chosen.owner=self.physics.candy
		self.physics.bubbleIndex=chosen.index
	end
	if l and r then self.parked=r r.owner=self.physics.candy end
end

function ghosts:advance(form,delta)
	for _,app in ipairs(self.apps) do if app.form==form then
		app.age=f(app.age+delta)
		if app.retiring then app.retireAge=f(app.retireAge+delta) end
	end end
end

function ghosts:update(delta)
	self.time=f(self.time+delta)
	for i=#self.apps,1,-1 do
		local app=self.apps[i]
		if app.retiring and app.retireAge>=f(.16) then
			app.removed=true
			if app.rope then
				local r=app.rope
				if r.tail then for j=#r.tail.constraints,1,-1 do
					if r.tail.constraints[j].rope==r then table.remove(r.tail.constraints,j) end
				end end
				r.removed,r.active=true,false
				table.clear(r.bodies) table.clear(r.points)
				table.remove(self.physics.ropes,table.find(self.physics.ropes,r))
			elseif app.bouncer then
				app.bouncer.removed=true
				table.remove(self.physics.bouncers.objects,table.find(self.physics.bouncers.objects,app.bouncer))
			elseif app.form==2 then
				table.remove(self.physics.bubbleOrder,table.find(self.physics.bubbleOrder,app.index))
			end
			table.remove(self.apps,i)
		end
	end
	for _,g in ipairs(self.objects) do
		g.age,g.idleAge=f(g.age+delta),f(g.idleAge+delta)
		if g.app and g.form==4 and g.app.rope.cut then self:reset(g,1) end
	end
end

function ghosts.alpha(app)
	if app.removed then return 0 end
	return app.retiring and math.max(0,1-app.retireAge/.16) or math.min(1,app.age/.36)
end

return ghosts
