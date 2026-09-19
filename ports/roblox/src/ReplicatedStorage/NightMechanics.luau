-- LightProximity, LightBulbDefinition and GameScene.CandyCollision.
local Math=require(script.Parent.DxMath)
local f=Math.float
local night={}
night.__index=night
function night.new(physics,level)
	return setmetatable({physics=physics,enabled=level.night==true,lit={},pickupLit={},awake=false,time=0},night)
end
function night:illuminated(point)
	for _,b in ipairs(self.physics.bulbs) do
		if not b.removed and not b.transport then
			local d=point-b.pos
			if f(f(d.X*d.X)+f(d.Y*d.Y))<f(b.radius*b.radius) then return true end
		end
	end
	return false
end
function night:update(delta)
	self.time=f(self.time+delta)
	for i,p in ipairs(self.physics.starPositions) do
		self.pickupLit[i]=self.lit[i]==true
		self.lit[i]=self:illuminated(p)
	end
	self.awake=self:illuminated(self.physics.target)
end
function night:collide()
	local p=self.physics
	local all=p:activeBodies()
	for i,a in ipairs(all) do for j=i+1,#all do
		local b=all[j]
		if not (a.isLight or b.isLight) or p.lanterns.inLantern then continue end
		local d=a.pos-b.pos
		local ds=f(f(d.X*d.X)+f(d.Y*d.Y))
		local radius=94.5 -- 2.25 * STAR_RADIUS (42)
		if ds>=radius*radius then continue end
		local distance=f(math.sqrt(ds))
		local penetration=f(radius-distance)
		local half=f(penetration*.5)
		local inv=distance>0 and f(1/distance) or 0
		local n=d*inv
		local speed=f(Math.length(a.velocity)+Math.length(b.velocity))
		local full=speed>0 and penetration>=f(2000/speed)
		if full then
			local dx,dy=-d.X,-d.Y
			local c,s=f(dx/radius),f(dy/radius)
			local av,bv=a.velocity,b.velocity
			local t28,t30=f(dx*av.X),f(dy*av.X)
			local t29=f(f(t28+f(dy*av.Y))/radius)
			local t31=f(f(t30+f(dx*bv.X))/radius)
			local t32=f(f(f(dx*av.Y)-t30)/radius)
			local t35=f(f(t28-f(bv.X*dy))/radius)
			a.velocity=Vector2.new(f(f(t31*c)-f(t32*s)),f(f(t32*c)+f(t31*s)))
			b.velocity=Vector2.new(f(f(t29*c)-f(t35*s)),f(f(t35*c)+f(t29*s)))
		end
		a.pos+=n*half b.pos-=n*half
		if full then
			a.previous=a.pos-Vector2.new(f(a.velocity.X/60),f(a.velocity.Y/60))
			b.previous=b.pos-Vector2.new(f(b.velocity.X/60),f(b.velocity.Y/60))
		end
	end end
end
return night
