local Atlas = require(script.Parent.AtlasSprite)
local Layout = require(script.Parent.ViewportLayout)
local confetti = {}
confetti.__index = confetti

function confetti.new(parent, random)
	local self = setmetatable({ parent = parent, particles = {}, elapsed = 0 }, confetti)
	random = random or Random.new()
	-- BoxOpenClose.CreateConfettiParticleNear and ShowConfetti, retina design units.
	for index = 1, 70 do
		local object = Instance.new("Frame")
		object.Name, object.BackgroundTransparency = "Confetti" .. index, 1
		object.AnchorPoint, object.ZIndex, object.Parent = Vector2.new(.5, .5), 6, parent
		local particle = {
			object = object, sprite = Atlas.new(object, {"confetti"}),
			x = random:NextNumber(-200, 2560), y = random:NextNumber(-80, 200),
			fall = random:NextNumber(300, 800), duration = random:NextNumber(2, 5),
			rotation = random:NextInteger(-360, 360), finish = random:NextInteger(-360, 360),
			first = random:NextInteger(0, 2) * 9, offset = random:NextInteger(0, 7),
		}
		particle.sprite:show("confetti", particle.first + particle.offset)
		table.insert(self.particles, particle)
	end
	self:update(0)
	return self
end

function confetti:update(delta)
	self.elapsed += delta
	local view=Layout.compute(self.parent.AbsoluteSize)
	local v,s=view.visible,view.content
	local alive = 0
	for _, particle in ipairs(self.particles) do
		local progress = math.min(1, self.elapsed / particle.duration)
		local object = particle.object
		object.Visible = progress < 1
		if progress < 1 then
			alive += 1
			local scale = math.min(1, self.elapsed / .3)
			object.Size = UDim2.fromScale(290 / v.X * scale*s, 228 / v.Y * scale*s)
			object.Position = UDim2.fromScale(particle.x / 2560, (particle.y + particle.fall * progress)*s / v.Y)
			object.Rotation = particle.rotation + (particle.finish - particle.rotation) * progress
			particle.sprite:show("confetti", particle.first + (math.floor(self.elapsed * 20) + particle.offset) % 9)
			particle.sprite:fade(progress)
		end
	end
	self.parent:SetAttribute("ConfettiTime", self.elapsed)
	self.parent:SetAttribute("ConfettiAlive", alive)
end

return confetti
