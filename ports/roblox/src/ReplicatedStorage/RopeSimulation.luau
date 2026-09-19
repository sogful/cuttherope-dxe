-- Portable 2D Verlet rope simulation. No Roblox physics dependencies.
local Rope = {}
Rope.__index = Rope

function Rope.new(anchor, tail, count)
	local self = setmetatable({ points = {}, previous = {}, cut = false }, Rope)
	self.segmentLength = (tail - anchor).Magnitude / count
	for i = 0, count do
		local p = anchor:Lerp(tail, i / count)
		self.points[i + 1], self.previous[i + 1] = p, p
	end
	return self
end

function Rope:step(dt, gravity)
	if self.cut then return end
	for i = 2, #self.points do
		local current = self.points[i]
		local velocity = current - self.previous[i]
		self.previous[i] = current
		self.points[i] = current + velocity + gravity * dt * dt
	end
	for _ = 1, 8 do
		self.points[1] = self.previous[1]
		for i = 1, #self.points - 1 do
			local a, b = self.points[i], self.points[i + 1]
			local delta = b - a
			local d = delta.Magnitude
			if d > 0 then
				local correction = delta * ((d - self.segmentLength) / d)
				if i == 1 then
					self.points[i + 1] = b - correction
				else
					self.points[i] = a + correction * .5
					self.points[i + 1] = b - correction * .5
				end
			end
		end
	end
end

function Rope:cutBySwipe(a, b)
	if self.cut then return false end
	local function cross(u, v) return u.X * v.Y - u.Y * v.X end
	local r = b - a
	for i = 1, #self.points - 1 do
		local p, q = self.points[i], self.points[i + 1]
		local s = q - p
		local denominator = cross(r, s)
		if math.abs(denominator) > .001 then
			local t, u = cross(p - a, s) / denominator, cross(p - a, r) / denominator
			if t >= 0 and t <= 1 and u >= 0 and u <= 1 then
				self.cut = true
				return true
			end
		end
	end
	return false
end

function Rope:cutAt(point, radius)
	if self.cut then return false end
	for i = 1, #self.points - 1 do
		local a, b = self.points[i], self.points[i + 1]
		local delta = b - a
		local amount = math.clamp((point - a):Dot(delta) / math.max(delta:Dot(delta), .001), 0, 1)
		if (point - a - delta * amount).Magnitude <= (radius or 18) then
			self.cut = true
			return true
		end
	end
	return false
end

return Rope

