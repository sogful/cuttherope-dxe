-- CTRMover.FromXml + Framework.Helpers.Mover. Definitions contain world-space
-- offsets (authored *3) and integer desktop speed (authored *3.3, truncated).
local mover={}
local Dx=require(script.Parent.DxMath)
local f=Dx.float
mover.__index=mover

function mover.new(origin,definition,angle)
	if not definition then return nil end
	local path={origin}
	if definition.radius then
		local count=math.floor(definition.radius/2)
		if count>0 then
			table.clear(path)
			local step=f(f(2*math.pi)/count)*(definition.clockwise and 1 or -1)
			local angle=0
			for _=1,count do
				-- CTRMover uses Cosf/Sinf (MathF), unlike collision rotation's Fm table.
				local c,s=f(math.cos(angle)),f(math.sin(angle))
				table.insert(path,origin+Vector2.new(c,s)*definition.radius)
				angle=f(angle+step)
			end
		end
	else
		for _,offset in ipairs(definition.offsets or {}) do table.insert(path,origin+offset) end
	end
	return setmetatable({path=path,pos=path[1],target=#path>1 and 2 or 1,speed=definition.speed,
		rotateSpeed=definition.rotateSpeed or 0,angle=angle or 0,initialAngle=angle or 0,overrun=0},mover)
end

function mover:advance()
	self.target=(self.target-1+(self.reverse and -1 or 1))%#self.path+1
end

function mover:update(delta)
	if self.paused then return end
	local remaining=f(delta+self.overrun)
	self.overrun=0
	local noProgress=0
	while remaining>0 do
		local destination=self.path[self.target]
		local difference=destination-self.pos
		local distance=Dx.length(difference)
		if distance<=0 then
			self:advance()
			noProgress+=1
			if noProgress>#self.path+1 then break end
		else
			noProgress=0
			local speed=self.speeds and self.speeds[self.target] or self.speed
			if speed<=0 then break end
			local travel=f(distance/speed)
			if travel<=remaining then
				self.pos=destination
				remaining=f(remaining-travel)
				self:advance()
			else
				self.pos+=difference*f(1/distance)*f(speed*remaining)
				remaining=0
			end
		end
	end
	if remaining>0 then self.overrun=remaining end
	if self.rotateSpeed~=0 then
		if self.useInitialAngle and self.target==1 then self.angle=self.initialAngle
		else self.angle=f(self.angle+f(self.rotateSpeed*delta)) end
	end
end

return mover
