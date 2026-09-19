local drawing = {}
local Session = require(script.Parent.SessionState)
local palettes = {
	{Color3.new(.475,.305,.185), Color3.new(.675555556,.44,.275555556)},
	{Color3.new(.624,.294,.114), Color3.new(1,.627,.463)},
	{Color3.new(.404,.612,.635), Color3.new(.773,.898,.902)},
	{Color3.new(.757,.533,0), Color3.new(.98,.843,.2)},
	{Color3.new(.980,.243,.243), Color3.new(.282,.525,.153)},
	{Color3.new(.176,.318,.659), Color3.new(1,1,1)},
	{Color3.new(.631,.957,1), Color3.new(.996,.631,.953)},
	{Color3.new(1,.329,.318), Color3.new(1,.992,.941)},
	{Color3.new(1,.831,.404), Color3.new(.251,.239,.278)},
}
local cache = setmetatable({}, { __mode = "k" })
local pathCache = setmetatable({}, { __mode = "k" })

local function trim(values, count)
	for index = #values, count + 1, -1 do values[index] = nil end
end

function drawing.paths(rope)
	local record = pathCache[rope]
	if not record then record = {paths = {}, head = {}, tail = {}} pathCache[rope] = record end
	local paths = record.paths
	table.clear(paths)
	if not rope.active then return paths end
	if not rope.cut then
		if #rope.points >= 3 then paths[1] = rope.points end
	else
		local head, tail = record.head, record.tail
		local headCount, tailCount = 0, 0
		for index, point in ipairs(rope.points) do
			if index <= rope.split then headCount += 1 head[headCount] = point
			else tailCount += 1 tail[tailCount] = point end
		end
		trim(head, headCount) trim(tail, tailCount)
		if headCount >= 3 then table.insert(paths, head) end
		if tailCount >= 3 and not rope.hideTailParts then table.insert(paths, tail) end
	end
	return paths
end

function drawing.samples(points)
	local record = cache[points]
	if not record then
		record = { previous = {}, samples = {}, work = {} }
		cache[points] = record
	end
	local previous, cached = record.previous, record.samples
	if #points < 2 then
		table.clear(previous) table.clear(cached) table.clear(record.work)
		if #points == 1 then previous[1], cached[1] = points[1], points[1] end
		return cached
	end
	local changed = #previous ~= #points
	for index, point in ipairs(points) do
		if previous[index] ~= point then changed = true end
	end
	if not changed and #cached > 0 then return cached end
	for index, point in ipairs(points) do previous[index] = point end
	trim(previous, #points)
	local count = (#points - 1) * 4
	local samples = record.samples
	local work = record.work
	trim(work, #points)
	trim(samples, count + 1)
	for index = 0, count do
		for position, point in ipairs(points) do work[position] = point end
		local fraction = index / count
		for remaining = #work - 1, 1, -1 do
			for position = 1, remaining do
				work[position] = work[position]:Lerp(work[position + 1], fraction)
			end
		end
		samples[index + 1] = work[1]
	end
	return samples
end

function drawing.style(points, rope, skin)
	skin = skin or Session.rope or 0
	if not palettes[skin + 1] then skin = 0 end
	local first = #points >= 2 and (points[2] - points[1]).Magnitude or 0
	local stretched = first > 112
	local palette = palettes[skin + 1]
	local base = stretched and skin ~= 0 and palettes[1] or palette
	local gain = rope.highlighted and 3 or 1
	local shade = {}
	for index = 1, 2 do
		local dark = (skin == 0 or stretched) and (index == 1 and .4 or .45) or 1
		local red = stretched and not rope.highlighted and first / 105 * 2 or 1
		shade[index] = Color3.new(palette[index].R * dark * gain * red, palette[index].G * dark * gain, palette[index].B * dark * gain)
	end
	return {base = {Color3.new(base[1].R * gain, base[1].G * gain, base[1].B * gain), Color3.new(base[2].R * gain, base[2].G * gain, base[2].B * gain)},
		shade = shade, alpha = rope.cut and not rope.pendingCut and math.clamp(rope.remaining / 1.95, 0, 1) or 1,
		white = rope.cut and rope.pendingCut ~= nil, outline = skin > 0}
end

function drawing.color(index, count, style)
	local group = math.floor((index - 1) / 3)
	local alternate = group % 2 == 0
	style = style or drawing.style({}, {})
	if style.white then return Color3.new(1, 1, 1) end
	local stripe = alternate and 2 or 1
	return style.shade[stripe]:Lerp(style.base[stripe], math.min(1, group * 3 / math.max(1, count - 1)))
end

return drawing
