local Frames = require(script.Parent.OmNomFrames)
local Atlas = require(script.Parent.AtlasSprite)
local animator = {}
animator.__index = animator
local states = {
	idle = "IdleLoop", variationone = "IdleVariationOne", variationtwo = "IdleVariationTwo",
	variationthree = "IdleVariationThree", opening = "MouthOpening", closing = "MouthClosing",
	chewing = "Chewing", excited = "Excited", greeting = "Greeting", sad = "Sad", sleeping = "Sleeping",
}

function animator.new(parent, slot, random)
	local data = assert(Frames[slot], "Unknown XML Om Nom skin")
	local groups = {}
	for id in pairs(data.timelines) do table.insert(groups, "t" .. id) end
	local self = setmetatable({parent = parent, data = data, random = random or Random.new(), mouth = false,
		closeafter = 1, visual = Atlas.new(parent, groups, data.library, true)}, animator)
	self.idlecount = self.random:NextInteger(5, 20)
	parent:SetAttribute("OmNomSkin", slot)
	self:play(data.config.startWithGreeting and "greeting" or "idle")
	return self
end

function animator:timeline(id)
	if not id or not self.data.timelines[tostring(id)] then return end
	self.id, self.time = id, 0
	self.nextIdleTick = self.data.idleCadence.first
	self.parent:SetAttribute("Timeline", id)
	self.visual:show("t" .. id, 0)
end

function animator:play(name)
	local id = self.data.config.timelines[states[name]]
	if not id then return end
	if self.onSound then self.onSound(name) end
	self.state = name
	self.parent:SetAttribute("Animation", name)
	self:timeline(id)
end

function animator:activatePreview()
	self:play(self.data.config.startWithGreeting and "greeting" or "idle")
	self:variant()
end

function animator:variant()
	local variants = self.data.config.idleVariants
	if #variants > 0 then
		self.state = "variation"
		self.parent:SetAttribute("Animation", self.state)
		self:timeline(variants[self.random:NextInteger(1, #variants)])
	end
end

function animator:preview()
	local config = self.data.config
	local id = config.id == "OM_NOM_ORIGINAL_FLASH" and config.timelines.IdleVariationThree or config.timelines.Excited
	self:timeline(id or config.timelines.IdleLoop)
	-- CandySelectionView skips 14 source frames (30 Hz) for static XML previews.
	local info = self.data.timelines[tostring(self.id)]
	self.visual:show("t" .. self.id, math.min(info.frames - 1, math.floor(14 / 30 * 20)))
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
	if self.id == self.data.config.timelines.IdleLoop and not self.mouth then self:play("excited") end
end

function animator:update(delta)
	local config = self.data.config
	local remaining = math.max(0, delta)
	-- Advance to each event boundary so a variant starts at the cadence edge,
	-- not a whole update early. A normal idle wrap does not rebind its driver;
	-- explicit Play/followups do, and reset the cadence clock in timeline().
	for _ = 1, 128 do
		local id = self.id
		local info = self.data.timelines[tostring(id)]
		local idle = id == config.timelines.IdleLoop
		local boundary = info.duration > 0 and info.duration or math.huge
		if idle then boundary = math.min(boundary, self.nextIdleTick) end
		local step = math.min(remaining, math.max(0, boundary - self.time))
		self.time += step
		remaining -= step
		if idle and self.time >= self.nextIdleTick - 1e-7 then
			self.nextIdleTick += self.data.idleCadence.period
			self.idlecount -= 1
			if self.idlecount <= 0 then
				self:variant()
				self.idlecount = self.random:NextInteger(5, 20)
			end
		end
		if self.id == id and info.duration > 0 and self.time >= info.duration - 1e-7 then
			if idle or id == config.timelines.Sleeping then
				self.time = 0
				self.nextIdleTick -= info.duration
			else
				local nextId = config.followups[tostring(id)]
				if not nextId then self.time = info.duration break end
				self:timeline(nextId)
				if nextId == config.timelines.IdleLoop or nextId == config.timelines.Sleeping then
					self.state = nextId == config.timelines.IdleLoop and "idle" or "sleeping"
					self.parent:SetAttribute("Animation", self.state)
				end
			end
		end
		if remaining <= 1e-7 then break end
	end
	local info = self.data.timelines[tostring(self.id)]
	self.visual:show("t" .. self.id, math.min(info.frames - 1, math.floor(self.time * info.fps)))
end

return animator
