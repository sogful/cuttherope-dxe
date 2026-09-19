local physics = {}
local Hazards = require(script.Parent.SpikeHazards)
local Mover = require(script.Parent.PathMover)
local BoxMechanics = require(script.Parent.BoxMechanics)
local Bouncers = require(script.Parent.BouncerMechanics)
local Ghosts = require(script.Parent.GhostMechanics)
local Steam = require(script.Parent.SteamMechanics)
local Lanterns = require(script.Parent.LanternMechanics)
local Mice = require(script.Parent.MouseMechanics)
local Night = require(script.Parent.NightMechanics)
local Conveyors = require(script.Parent.ConveyorMechanics)
local SimulationClock = require(script.Parent.SimulationClock)
local Math = require(script.Parent.DxMath)
local float = Math.float
physics.__index = physics
-- GameScene.Update deliberately overrides its supplied delta with 0.016.
local sceneDelta = float(.016)
local gravity = Vector2.new(0, 784)
-- GameScene.LoadMetadata: authored ropePhysicsSpeed * desktop multiplier.

local function point(position, mass, pinned)
	return { pos = position, previous = nil, mass=float(mass), inverse = float(1 / float(mass)), pin = pinned and position or nil, constraints = {}, velocity = Vector2.zero }
end
local function integrate(body, acceleration, timestep)
	-- DX initializes prevPos at the first integration, AFTER earlier rope constraints.
	local delta = body.pos - (body.previous or body.pos) + acceleration
	body.previous = body.pos
	body.pos += delta
	body.velocity = delta * float(1 / timestep)
end
local function satisfy(body)
	if body.pin then body.pos = body.pin return end
	for _, link in ipairs(body.constraints) do
		local other = link.other
		local delta = other.pos - body.pos
		if delta.X==0 and delta.Y==0 then if link.length==0 then continue end delta = Vector2.new(1, 1) end
		local length = delta.Magnitude
		if link.maximum and length <= link.length then continue end
		local factor=float(float(length-link.length)/float(math.max(length,1)*float(body.inverse+other.inverse)))
		body.pos += delta * float(body.inverse*factor)
		if not other.pin then other.pos -= delta * float(other.inverse*factor) end
	end
end

function physics:attach(rope, length, tail)
		tail = tail or self.candy
		rope.tail = tail
		local definition = rope.definition
		local anchor = point(rope.anchor, .02, true)
		rope.bodies, rope.active, rope.captured = {anchor}, true, true
		local count = math.ceil(length / 105)
		local offset = (tail.pos - rope.anchor) / math.floor(length / 105 + 2)
		for index = 1, count do
			local previous = rope.bodies[#rope.bodies]
			-- RollplacingWithOffset adds to the previous point each time. A
			-- multiplied offset rounds differently and perturbs long near-vertical ropes.
			local body = point(previous.pos + offset, .02)
			body.constraints = {{ other = previous, length = 105 }}
			table.insert(rope.bodies, body)
		end
		local tailrest = length + 105 - count * 105
		table.insert(tail.constraints, { other = rope.bodies[#rope.bodies], length = tailrest, rope = rope })
		table.insert(rope.bodies, tail)
		rope.length = length
		if self.audio and (definition.radius or -1)>=0 then
			self.audio:play("rope_get")
			if rope.mover then self.audio:play("buzz") end
		end
end

function physics.new(level)
	local self = setmetatable({ candy = point(level.candyStart, 1), ropes = {}, accumulator = 0, bubble = false, speed = level.physicsSpeed or 1.4 }, physics)
	self.baseGravity,self.gravity,self.gravityAge=gravity,gravity,.3
	self.gravityInverted=false
	-- LoadMetadata initializes the candy explicitly; rope points remain undefined.
	self.candy.previous = level.candyStart
	self.candy.isCandy = true
	self.whole = {self.candy}
	self.bulbs={}
	for _,d in ipairs(level.bulbs or {}) do
		local b=point(d.point,1)
		b.isCandy,b.isLight,b.radius,b.number=true,true,d.radius,d.number
		table.insert(self.bulbs,b)
	end
	if level.halves then
		self.split={}
		for index,start in ipairs(level.halves) do
			local half=point(start,1)
			half.previous,half.drawPosition,half.isCandy,half.part=start,start,true,index
			self.split[index]=half
		end
	end
	self.bubbles, self.usedBubbles = table.clone(level.bubbles or {}), {}
	self.bubbleOrder={}
	for index in ipairs(self.bubbles) do self.bubbleOrder[index]=index end
	self.target = level.target
	self.hazards = Hazards.new(level.spikes)
	self.bouncers = Bouncers.new(level.bouncers)
	self.starPositions,self.starMovers={},{}
	for index,position in ipairs(level.stars or {}) do
		self.starPositions[index]=position
		local definition=level.starMotion and level.starMotion[index]
		self.starMovers[index]=Mover.new(position,definition and definition.movement)
	end
	local startsCaptured=false
	for _,definition in ipairs(level.lanterns or {}) do if definition.captured then startsCaptured=true end end
	for _, definition in ipairs(level.ropes) do
		local rope = { definition = definition, anchor = definition.anchor, bodies = {}, points = {}, cut = false, remaining = 2, active = false, captured = false, radiusAlpha = 1 }
		table.insert(self.ropes, rope)
		if not startsCaptured and (definition.radius or -1) < 0 then
			local tail=self.split and self.split[definition.part or 1]
			if definition.bulb then
				for _,b in ipairs(self.bulbs) do tail=b if string.lower(b.number)==string.lower(definition.bulb) then break end end
			end
			self:attach(rope,definition.length,tail)
		end
	end
	self.mechanics = BoxMechanics.new(self, level)
	self.ghosts = Ghosts.new(self, level.ghosts)
	self.steam = Steam.new(self, level.steamTubes)
	self.lanterns = Lanterns.new(self, level.lanterns)
	self.mice = Mice.new(self, level.mice)
	self.night = Night.new(self,level)
	self.conveyors = Conveyors.new(self,level.conveyors)
	self.scheduler=SimulationClock.new()
	self:refresh()
	self:refreshRopeRotation()
	return self
end

function physics:activeBodies()
	if #self.bulbs>0 then
		local all={}
		if not self.retired and not self.transport then
			for _,b in ipairs(self.split or self.whole) do if not b.removed then table.insert(all,b) end end
		end
		for _,b in ipairs(self.bulbs) do if not b.removed and not b.transport then table.insert(all,b) end end
		return all
	end
	if self.retired or self.transport then return {} end
	if not self.split then return self.whole end
	local bodies={}
	for _,body in ipairs(self.split) do if not body.removed then table.insert(bodies,body) end end
	return bodies
end

function physics:focus()
	local first=self:activeBodies()[1]
	return first and first.pos or self.candy.pos
end

function physics:hasBubble(body)
	if body==self.candy then return self.bubble end
	return body.bubble
end

function physics:popBubble(body)
	if self.audio and self:hasBubble(body) then self.audio:play("bubble_break") end
	if self.ghosts and self:hasBubble(body) then self.ghosts:releaseBody(body) end
	if body==self.candy then self.bubble,self.bubbleIndex=false,nil else body.bubble,body.bubbleIndex=false,nil end
end

function physics:merge(touched)
	local split=self.split
	if not split or split[1].removed or split[2].removed then return end
	local left,right=split[1],split[2]
	if split.distance then
		for _=1,30 do satisfy(left) satisfy(right) end
		if split.distance>0 then
			split.distance=math.max(0,split.distance-200*sceneDelta)
			if split.distance==0 then
				local whole=self.candy
				whole.pos=left.pos
				whole.previous=whole.pos-((left.pos-left.previous)+(right.pos-right.previous))*.5
				whole.residual,left.residual,right.residual=0,0,0
				self.bubble=left.bubble or right.bubble or false
				self.bubbleIndex=left.bubble and left.bubbleIndex or right.bubbleIndex
				self.ghosts:merge(left,right)
				left.bubble,right.bubble=false,false
				for _,rope in ipairs(self.ropes) do
					if (rope.tail==left or rope.tail==right) and (rope.cutIndex or -1)~=#rope.bodies-3 and #rope.bodies>=2 then
						local previous=rope.bodies[#rope.bodies-1]
						for _,link in ipairs(rope.tail.constraints) do
							if link.other==previous then table.insert(whole.constraints,{other=previous,length=math.floor(link.length),rope=rope}) break end
						end
						rope.tail,rope.bodies[#rope.bodies]=whole,whole
						rope.chosen,rope.initialAngle=false,0
					end
				end
				self.split,self.merged=nil,true
				if self.audio then self.audio:play("candy_link") end
				return
			end
			for _,body in ipairs(split) do
				for _,link in ipairs(body.constraints) do if link.maximum then link.length=split.distance end end
			end
		end
	elseif touched then
		split.distance=(left.pos-right.pos).Magnitude
		table.insert(left.constraints,{other=right,length=split.distance,maximum=true})
		table.insert(right.constraints,{other=left,length=split.distance,maximum=true})
	end
end

function physics:refresh()
	for _, rope in ipairs(self.ropes) do
		for index, body in ipairs(rope.bodies) do rope.points[index] = body.pos end
		for index=#rope.points,#rope.bodies+1,-1 do rope.points[index]=nil end
	end
end

function physics:refreshRopeRotation()
	for _,rope in ipairs(self.ropes) do
		rope.relaxed=#rope.points>=2 and (rope.points[2]-rope.points[1]).Magnitude>105.3
	end
end

function physics:toggleGravity()
	self.gravityInverted=not self.gravityInverted
	if self.audio then self.audio:play(self.gravityInverted and "gravity_on" or "gravity_off") end
	self.gravity=Vector2.new(self.baseGravity.X,self.baseGravity.Y*(self.gravityInverted and -1 or 1))
	self.gravityAge=0
end

function physics:earthRotation()
	local progress=math.min(1,self.gravityAge/.3)
	return 180*(self.gravityInverted and progress or 1-progress)
end

function physics:tick()
	local physicsDelta = float(sceneDelta * float(self.speed))
	local gravity=self.gravity
	self.gravityAge+=sceneDelta
	local rotated={}
	self.mechanics:advanceTransport(sceneDelta)
	self.lanterns:advanceScene(sceneDelta)
	self.ghosts:advance(4,sceneDelta)
	for _, rope in ipairs(self.ropes) do
		if rope.removed then continue end
		self.mechanics:moveHook(rope,sceneDelta)
		if rope.conveyor and rope.bodies[1] then rope.bodies[1].pos,rope.bodies[1].pin=rope.anchor,rope.anchor end
		local radius = rope.definition.radius or -1
		if radius >= 0 then
			if rope.captured then rope.radiusAlpha = math.max(0, rope.radiusAlpha - 1.5 * sceneDelta) end
		end
		if rope.active and (not rope.cut or rope.remaining > 0) then
			if rope.cut then
				rope.remaining = math.max(0, rope.remaining - physicsDelta)
				if rope.pendingCut and rope.remaining < 1.95 then self:detach(rope) end
			end
			for _, body in ipairs(rope.bodies) do
				if not body.isCandy then integrate(body, (gravity*body.mass)*body.inverse * float(physicsDelta*sceneDelta), physicsDelta) end
			end
			for _ = 1, 30 do
				for _, body in ipairs(rope.bodies) do satisfy(body) end
			end
			-- Inert source ropes stop updating but retain their tail constraints
			-- until disposal. Other ropes may still satisfy that shared endpoint.
		end
		-- GameScene updates the rope captured at the START of this hook's turn,
		-- then checks its radius. A newly created rope waits until the next tick.
		if radius >= 0 and not rope.captured and not self.disableCapture then
			for _,body in ipairs(self:activeBodies()) do
				if (body.pos-rope.anchor).Magnitude<=radius+42 then self:attach(rope,radius+42,body) break end
			end
		end
		local body=rope.tail
		if body and not body.isLight and not body.removed and not self.retired and not rotated[body] and not rope.cut and rope.relaxed then
			local direction=rope.anchor-body.pos
			local angle=math.deg(math.atan2(direction.Y,direction.X))%360
			if not rope.chosen then rope.initialAngle=(body.rotation or 0)-angle end
			body.residual=angle+rope.initialAngle-(body.rotation or 0)
			body.rotation=angle+rope.initialAngle
			rope.chosen,rotated[body]=true,true
		else rope.chosen=false end
	end
	for _,body in ipairs(self:activeBodies()) do
		if body.isLight then body.residual=0
		elseif not rotated[body] then body.rotation=(body.rotation or 0)+math.min(5,body.residual or 0) body.residual=(body.residual or 0)*.98 end
	end
	local touched=false
	if self.split then
		local difference=self.split[1].drawPosition-self.split[2].drawPosition
		touched=math.abs(difference.X)<=88 and math.abs(difference.Y)<=76
	end
	for _,body in ipairs(self:activeBodies()) do
		integrate(body,body.disableGravity and Vector2.zero or gravity*float(physicsDelta*physicsDelta),physicsDelta)
		body.drawPosition=body.pos
	end
	self.lanterns:advanceCandyVisual(sceneDelta)
	self.night:collide()
	self:merge(touched)
	self.night:update(sceneDelta)
	self.conveyors:update(sceneDelta)
	for index,mover in pairs(self.starMovers) do
		mover:update(sceneDelta)
		self.starPositions[index]=mover.pos
	end
	-- GameScene.Update captures after integration and BEFORE applying that frame's lift.
	self.ghosts:advance(2,sceneDelta)
	if not self.disableCapture then
		local captured=false
		for _, index in ipairs(self.bubbleOrder) do
			local position=self.bubbles[index]
			for _,body in ipairs(self:activeBodies()) do
				local d=(body==self.candy and self.lanterns.visual and body.drawPosition or body.pos)-position
				if not self.usedBubbles[index] and d.X>=-85 and d.X<85 and d.Y>=-85 and d.Y<85 then
					self.ghosts:capture(body,index)
					if body==self.candy then self.bubble,self.bubbleIndex=true,index else body.bubble,body.bubbleIndex=true,index end
					body.bubbleCaptureTime=self.mechanics.time
					self.usedBubbles[index],captured=true,true
					if self.audio then self.audio:play("bubble") end
					self.conveyors:remove((self.conveyors.byKind.bubble or {})[index])
					break
				end
			end
			if captured then break end
		end
	end
	self.ghosts:update(sceneDelta)
	-- DX processes pumps and hats before barriers, so transported candy is
	-- already absent and pump-displaced candy uses its new position for collision.
	self:refresh()
	self.mechanics:tick(sceneDelta)
	self.hazards:update(sceneDelta)
	if not self.retired and not self.transport and not self.disableCapture and not self.lanterns.inLantern then
		for _,body in ipairs(self:activeBodies()) do
			if body.isLight then continue end
			local hazard=self.hazards:hit(body.pos,body.previous)
			if hazard then self.hazard,self.failedBody=hazard,body self:retireCandy(body) break end
		end
	end
	self.ghosts:advance(8,sceneDelta)
	self.bouncers:update(sceneDelta,self.disableCapture and {} or self:activeBodies())
	-- GameScene applies buoyancy AFTER barriers/bouncers, using this tick's
	-- integrated velocity. Changing this order changes repeated rebound impulses.
	for _,body in ipairs(self:activeBodies()) do
		if self:hasBubble(body) then body.pos+=Vector2.new(-body.velocity.X/14,float(-body.velocity.Y/14)+(self.gravityInverted and 40 or -40))*sceneDelta end
	end
	self:refresh()
	self:refreshRopeRotation()
end

function physics:retireCandy(body)
	self.mice:remove(body or self.candy)
	self.lanterns:remove(body or self.candy)
	self:popBubble(body or self.candy)
	if body and body~=self.candy then
		body.removed,body.bubble=true,false
		self:releaseRopes(body)
		return
	end
	self.retired, self.bubble = true, false
	self:releaseRopes()
end

function physics:releaseRopes(body,deferred)
	body=body or self.candy
	-- Lantern capture retains the source cut fade and its 1.95s detachment
	-- threshold. Clearing constraints here erases the last two incoming ticks.
	if not deferred then table.clear(body.constraints) end
	for _, rope in ipairs(self.ropes) do
		if rope.active and rope.bodies[#rope.bodies] == body then
			if not rope.cut then self:sever(rope, #rope.bodies - 1)
			elseif deferred then rope.hideTailParts=true end
			if not deferred then
				table.remove(rope.bodies)
				table.remove(rope.points)
			end
		end
	end
end

function physics:update(delta)
	self.scheduler:advance(delta,function() self:tick() end)
	self.accumulator=self.scheduler.remainder
	self:refresh()
end

function physics:sever(rope, index)
	if not rope.active or rope.cut then return false end
	rope.cut, rope.split, rope.pendingCut = true, index, index
	rope.cutIndex=index-1
	if self.mechanics then
		for number, candidate in ipairs(self.ropes) do if candidate == rope then self.mechanics:bust(number) break end end
	end
	return true
end

function physics:detach(rope)
	local index = rope.pendingCut
	rope.pendingCut = nil
	local nextbody = rope.bodies[index + 1]
	local previous = rope.bodies[index]
	if not nextbody then return end
	for i = #nextbody.constraints, 1, -1 do
		if nextbody.constraints[i].other == previous then
			table.remove(nextbody.constraints, i)
			-- Bungee.RemovePart preserves a lightweight endpoint on the head fragment.
			local tip = point(nextbody.pos, .00001)
			tip.previous = nextbody.previous
			tip.constraints = {{other = previous, length = 105}}
			table.insert(rope.bodies, index + 1, tip)
			rope.split = index + 1
			break
		end
	end
	for _, body in ipairs(rope.bodies) do
		if not body.isCandy then body.mass,body.inverse = float(.00001),100000 end
	end
end

local function cross(a, b) return a.X * b.Y - a.Y * b.X end
function physics:cut(a, b, radius)
	if self.mechanics.discs.held or (radius and self.mechanics.discs:blocksCut(a)) then return false end
	local cut = false
	for _, rope in ipairs(self.ropes) do
		if rope.active and not rope.cut then
			-- Grab.CutExclusionZone protects the entire stroke crossing the wheel.
			if rope.wheel and (radius and rope.wheel:inside(a) or not radius and Hazards.linebox(a,b,rope.anchor,110)) then continue end
			for index = 1, #rope.points - 1 do
				local p, q = rope.points[index], rope.points[index + 1]
				local hit = false
				if radius then
					local difference = q - p
					local fraction = math.clamp((a - p):Dot(difference) / math.max(.001, difference:Dot(difference)), 0, 1)
					local closest=p+difference*fraction
					hit = (a-closest).Magnitude <= radius and not (rope.wheel and rope.wheel:inside(closest))
				else
					local direction, edge = b - a, q - p
					local denominator = cross(direction, edge)
					if math.abs(denominator) > .001 then
						local t, u = cross(p - a, edge) / denominator, cross(p - a, direction) / denominator
						hit = t >= 0 and t <= 1 and u >= 0 and u <= 1
					end
				end
				if hit then
					local severed=self:sever(rope,index)
					if severed and self.audio then
						local length=#rope.points>=2 and (rope.points[2]-rope.points[1]).Magnitude or 0
						self.audio:play("rope_bleak_"..(length<=105.3 and 1 or length<=106 and 2 or length<=109 and 3 or 4))
					end
					cut=severed or cut break
				end
			end
		end
	end
	return cut
end

return physics
