local clock = {}
clock.__index = clock
clock.step = 1 / 60

function clock.new()
	return setmetatable({remainder=0, ticks=0, dropped=0}, clock)
end

function clock:advance(delta, tick)
	if delta ~= delta or delta <= 0 or delta == math.huge then return 0 end
	-- A stalled client cannot run Lua. Bound catch-up work, never enlarge a
	-- physics step or fast-forward collision/timer state across the omitted time.
	local accepted = math.min(delta, .25)
	self.dropped += delta - accepted
	self.remainder += accepted
	local count = math.floor((self.remainder + 1e-9) / clock.step)
	self.remainder = math.max(0, self.remainder - count * clock.step)
	for _=1,count do
		self.ticks += 1
		tick(clock.step)
	end
	return count * clock.step
end

return clock
