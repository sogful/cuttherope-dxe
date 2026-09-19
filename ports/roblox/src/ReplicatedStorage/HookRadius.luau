local Layers = require(script.Parent.GameplayLayers)
local radius = {}
radius.__index = radius

function radius.new(parent, index, definition)
	local count = math.floor(math.max(16, definition.radius) / 2)
	if count % 2 ~= 0 then count += 1 end
	local self = setmetatable({ parent = parent, definition = definition, segments = {} }, radius)
	for vertex = 0, count - 1, 2 do
		local a, b = vertex * math.pi * 2 / count, (vertex + 1) * math.pi * 2 / count
		local first = definition.anchor + Vector2.new(math.cos(a), math.sin(a)) * definition.radius
		local last = definition.anchor + Vector2.new(math.cos(b), math.sin(b)) * definition.radius
		local line = Instance.new("Frame")
		line.Name, line.AnchorPoint, line.BorderSizePixel = "HookRadius" .. index .. "Dash" .. vertex, Vector2.new(.5, .5), 0
		line.BackgroundColor3, line.ZIndex, line.Parent = Color3.new(.2, .5, .9), Layers.HookBack, parent
		line.Position = UDim2.fromScale((first.X + last.X) / 5120, (first.Y + last.Y) / 2880)
		table.insert(self.segments, { object = line, delta = last - first, offset = (first + last)*.5 - definition.anchor })
	end
	self:update(1)
	return self
end

function radius:update(alpha,anchor)
	local size = self.parent.AbsoluteSize
	for _, segment in ipairs(self.segments) do
		local line = segment.object
		local point=(anchor or self.definition.anchor)+segment.offset
		line.Position=UDim2.fromScale(point.X/2560,point.Y/1440)
		line.Visible, line.BackgroundTransparency = alpha > 0, 1 - alpha
		if alpha > 0 then
			local delta = Vector2.new(segment.delta.X * size.X / 2560, segment.delta.Y * size.Y / 1440)
			line.Size = UDim2.fromOffset(delta.Magnitude, math.max(1, 3 * size.X / 2560))
			line.Rotation = math.deg(math.atan2(delta.Y, delta.X))
		end
	end
end

return radius
