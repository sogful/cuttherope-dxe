local Mover=require(script.Parent.PathMover)
local Hazards=require(script.Parent.SpikeHazards)
local Math=require(script.Parent.DxMath)
local bouncers={}
bouncers.__index=bouncers
local rotate=Math.rotate
function bouncers.new(definitions)
	local self=setmetatable({objects={},time=0},bouncers)
	for _,definition in ipairs(definitions or {}) do
		table.insert(self.objects,{point=definition.point,angle=definition.angle,size=definition.size,
			mover=Mover.new(definition.point,definition.movement,definition.angle),hit=-100,hits=0})
	end
	return self
end
function bouncers:update(delta,bodies)
	self.time+=delta
	for _,object in ipairs(self.objects) do
		if object.removed then continue end
		if object.mover then object.mover:update(delta) object.point,object.angle=object.mover.pos,object.mover.angle end
		local angle,point=Math.radians(object.angle),object.point
		local half=object.size==1 and 97 or 151
		local a=Math.around(point+Vector2.new(-half,-5),angle,point)
		local b=Math.around(point+Vector2.new(half,-5),angle,point)
		local c=Math.around(point+Vector2.new(-half,5),angle,point)
		local d=Math.around(point+Vector2.new(half,5),angle,point)
		for _,body in ipairs(bodies) do
			if Hazards.hits(a,b,c,d,body.pos,body.previous,40) then
				-- GameScene.HandleBouncePtDelta resets only normal Verlet motion,
				-- then applies the original min-840, speed-times-40 impulse.
				local old=Math.around(body.previous,-angle,point)
				local now=Math.around(body.pos,-angle,point)
				local sign=old.Y>=point.Y and 1 or -1
				local force=math.max((body.previous-body.pos).Magnitude*40,840)*sign
				body.previous=Math.around(Vector2.new(old.X,now.Y),angle,point)
				body.pos=Math.around(now,angle,point)+rotate(Vector2.new(0,1),angle)*Math.float(force)*Math.float(delta)
				object.hit,object.hits=self.time,object.hits+1
				if self.audio then self.audio:play("bouncer") end
				if object.ghostApp and not object.ghostApp.retiring then object.ghostApp.age=math.max(.36,object.ghostApp.age) end
			end
		end
	end
end
return bouncers
