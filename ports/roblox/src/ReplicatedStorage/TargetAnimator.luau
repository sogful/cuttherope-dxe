local Atlas = require(script.Parent.AtlasSprite)
local PillowFrames = require(script.Parent.PillowFrames)
local animator = {}
animator.__index = animator

local function range(first, last)
	local result = {}
	for index = first, last do table.insert(result, index) end
	return result
end
-- OriginalTargetAnimationBackend.ConfigureTargetTimelines/Transitions, 20 fps.
local complex = {68}
for _ = 1, 2 do
	for index = 69, 83 do table.insert(complex, index) end
	if #complex == 16 then table.insert(complex, 68) end
end
local timelines = {
	idle = {"omnom", range(0, 18), "idle"},
	variationone = {"omnom", range(43, 67), "idle"},
	variationtwo = {"omnom", complex, "idle"},
	opening = {"omnom", range(19, 27)},
	closing = {"omnom", range(28, 31), "cheerful"},
	chewing = {"omnom", range(28, 31), "eating"},
	eating = {"omnom", range(32, 40), "eating"},
	excited = {"reactions", range(0, 19), "idle"},
	cheerful = {"reactions", range(20, 46), "idle"},
	greeting = {"reactions", range(47, 76), "idle"},
	sad = {"sad", range(0, 12)},
	sleeping = {"sleeping", range(0,6)},
}

function animator.new(parent, random)
	local self = setmetatable({ parent = parent, visual = Atlas.new(parent, {"omnom", "reactions", "sad"}, nil, true), random = random or Random.new(), blinkcount = 3, mouth = false, closeafter = 1 }, animator)
	self.idlecount = self.random:NextInteger(5, 20)
	self.sleepvisual=Atlas.new(parent,{"sleeping"},PillowFrames,true)
	self.sleepvisual:fade(1)
	local blink = Instance.new("Frame")
	blink.Name, blink.BackgroundTransparency, blink.Size = "Blink", 1, UDim2.fromScale(1, 1)
	blink.ZIndex, blink.Visible, blink.Parent = parent.ZIndex + 1, false, parent
	self.blink, self.blinkvisual = blink, Atlas.new(blink, {"omnom"}, nil, {omnom={41,42}})
	self:play("idle")
	return self
end

function animator:play(name)
	if self.onSound then self.onSound(name) end
	self.state, self.time, self.frame = name, 0, 1
	self.blink.Visible, self.blinktime = false, nil
	local timeline = timelines[name]
	self.visual:fade(name=="sleeping" and 1 or 0)
	self.sleepvisual:fade(name=="sleeping" and 0 or 1)
	local visual=name=="sleeping" and self.sleepvisual or self.visual
	visual:show(timeline[1], timeline[2][1])
	self.parent:SetAttribute("Animation", name)
end

function animator:proximity(distance, delta)
	if not self.mouth and distance < 200 then
		self.mouth, self.closeafter = true, 1
		self:play("opening")
	elseif self.mouth then
		self.closeafter = math.max(0, self.closeafter - delta)
		if self.closeafter == 0 then
			if distance < 200 then self.closeafter = 1
			else self.mouth = false self:play("closing") end
		end
	end
end

function animator:excited()
	if self.state == "idle" and not self.mouth then self:play("excited") end
end

function animator:update(delta)
	if self.blinktime then
		self.blinktime += delta
		-- The source hides the overlay at keyframe 2 (41, 41, 42, 42).
		if self.blinktime >= .1 then self.blink.Visible, self.blinktime = false, nil end
	end
	self.time += delta
	while self.time >= .05 do
		self.time -= .05
		local timeline = timelines[self.state]
		self.frame += 1
		if self.frame > #timeline[2] then
			if timeline[3] then
				local remainder = self.time
				self:play(timeline[3])
				self.time = remainder
				timeline = timelines[self.state]
			else self.frame = #timeline[2] self.time = 0 end
		end
		-- The source idle delegate fires only at keyframe 1 of each idle loop.
		if self.state == "idle" and self.frame == 2 then
			self.idlecount -= 1
			self.blinkcount -= 1
			if self.blinkcount <= 0 then
				self.blinkcount, self.blinktime, self.blink.Visible = 3, 0, true
				self.blinkvisual:show("omnom", 41)
			end
			if self.idlecount <= 0 then
				self.idlecount = self.random:NextInteger(5, 20)
				self:play(self.random:NextInteger(0, 1) == 0 and "variationone" or "variationtwo")
				timeline = timelines[self.state]
			end
		end
		local visual=self.state=="sleeping" and self.sleepvisual or self.visual
		visual:show(timeline[1], timeline[2][self.frame])
	end
end

return animator
