local Math=require(script.Parent.DxMath)
local f=Math.float
local steam={}
steam.__index=steam
local heights={32.9,94,141}

function steam.new(physics,definitions)
	local self=setmetatable({physics=physics,objects={},time=0},steam)
	for _,d in ipairs(definitions or {}) do
		table.insert(self.objects,{point=d.point,angle=d.angle,scale=d.scale or 3,state=0,phase=0,revision=0,valveAge=f(.55),valveRotation=0})
	end
	return self
end

function steam.height(tube,modulated)
	local height=f(f(heights[tube.state+1] or 0)*tube.scale)
	return modulated and f(height+f(tube.scale*f(math.sin(f(6*tube.phase))))) or height
end

function steam.valvePoint(tube)
	return tube.point+Math.rotate(Vector2.new(0,28*tube.scale),Math.radians(tube.angle))
end

function steam:touch(tube,point)
	if Math.length(point-steam.valvePoint(tube))>=40*tube.scale then return false end
	local reverse=tube.state==2
	tube.state=(tube.state+1)%3
	if self.physics.audio then self.physics.audio:play(({[0]="steam_end","steam_start2","steam_start"})[tube.state]) end
	tube.phase,tube.revision=0,tube.revision+1
	if tube.valveAge>=f(.55) then tube.valveAge,tube.valveSign=0,reverse and -1 or 1 end
	return true
end

function steam:press(point)
	for index,tube in ipairs(self.objects) do
		if self:touch(tube,point) then self.lastPressed=index return true end
	end
	return false
end

function steam:operate(tube,body,delta)
	local angle=Math.radians(tube.angle)
	local position=Math.around(body.pos,-angle,tube.point)
	local velocity=Math.rotate(body.velocity,-angle)
	local width,radius=f(10*tube.scale),f(17.5*tube.scale)
	local height=steam.height(tube,true)
	local left,right=f(tube.point.X-width/2),f(tube.point.X+width/2)
	local top,bottom=f(f(tube.point.Y-height)-tube.scale),f(tube.point.Y-radius)
	if f(position.X-radius)>right or f(position.X+radius)<left or f(position.Y-radius/2)>bottom or f(position.Y+radius)<top then return false end
	local aligned=tube.angle==0 and not self.physics.gravityInverted or tube.angle==180 and self.physics.gravityInverted
	local horizontal,damping=0,5
	if aligned then
		local dx=f(tube.point.X-position.X)
		if math.abs(dx)>width/4 then horizontal=f(f(-velocity.X/5)+f(.25*dx))
		else horizontal=math.abs(velocity.X)<1 and -velocity.X or f(-velocity.X/5) end
	end
	local compensation=f(f(-32/body.mass)*f(math.sqrt(tube.scale)))
	if not aligned then
		damping*=15
		compensation=f(compensation/((tube.angle==90 or tube.angle==270) and 4 or 2))
	end
	local impulse=Vector2.new(horizontal,f(f(-velocity.Y/damping)+compensation))
	local distance=f(tube.point.Y-position.Y)
	if distance>f(height+radius) then impulse*=f(math.exp(f(-2*f(distance-f(height+radius))))) end
	body.pos+=Math.rotate(impulse,angle)*delta
	return true
end

function steam:update(delta)
	self.time+=delta
	for _,tube in ipairs(self.objects) do
		tube.phase=f(tube.phase+delta)
		if tube.valveAge<f(.55) then
			tube.valveAge=math.min(f(.55),f(tube.valveAge+delta))
			tube.valveRotation=(tube.valveSign or 1)*180*tube.valveAge/f(.55)
		end
		if not self.physics.disableCapture then
			for _,body in ipairs(self.physics:activeBodies()) do self:operate(tube,body,delta) end
		end
	end
end

return steam
