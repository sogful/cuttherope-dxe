local frames = require(script.Parent.AnimationFrames)
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
local sprite = {}
sprite.__index = sprite
sprite.pages = frames.pages

function sprite.new(parent, groups, library, fixedFrames)
	library = library or frames
	local self = setmetatable({ parent = parent, labels = {}, transparency = 0, library = library }, sprite)
	if parent:IsA("ImageLabel") then parent.Image = "" end
	if fixedFrames then
		self.fixedFrames = {}
		self.warming, self.ready = {}, {}
		parent.Destroying:Connect(function()
			if self.waiting then self.waiting:Disconnect() self.waiting = nil end
		end)
		for _, group in ipairs(groups) do
			if type(fixedFrames)=="table" and fixedFrames[group] then
				for _,index in ipairs(fixedFrames[group]) do self:prepare(group,index) end
			else
				for index in ipairs(library[group]) do self:prepare(group, index - 1) end
			end
		end
		return self
	end
	for _, group in ipairs(groups) do
		for _, quad in ipairs(library[group]) do
			local page = quad[1]
			if not self.labels[page] then
				local label = Instance.new("ImageLabel")
				label.Name, label.BackgroundTransparency = "AtlasPage" .. page, 1
				label.Image, label.ScaleType = library.pages[page], Enum.ScaleType.Stretch
				label.ZIndex, label.Visible, label.Parent = parent.ZIndex, false, parent
				self.labels[page] = label
			end
		end
	end
	return self
end

function sprite:commit(group, index, label)
	label.ImageTransparency, label.Visible = self.transparency, true
	if self.current and self.current ~= label then self.current.Visible = false end
	self.group, self.index, self.current = group, index, label
	self.parent:SetAttribute("SpriteGroup", group)
	self.parent:SetAttribute("SpriteQuad", index)
end

function sprite:prepare(group, index)
	local key = group .. ":" .. index
	local label = self.fixedFrames[key]
	if label then return label end
	local quad = assert(self.library[group][index + 1], "Unknown DX quad: " .. key)
	label = Instance.new("ImageLabel")
	label.Name, label.BackgroundTransparency = "AtlasFrame_" .. group .. "_" .. index, 1
	label.Image, label.ScaleType = self.library.pages[quad[1]], Enum.ScaleType.Stretch
	label.ImageRectOffset, label.ImageRectSize = Vector2.new(quad[2], quad[3]), Vector2.new(quad[4], quad[5])
	label.Position = UDim2.fromScale(quad[6] / quad[8], quad[7] / quad[9])
	label.Size = UDim2.fromScale(quad[4] / quad[8], quad[5] / quad[9])
	-- A fetched atlas is not proof that a newly created GUI crop has drawn.
	-- Stage every immutable pose during screen loading, before any handoff.
	label.ImageTransparency = .999
	label.ZIndex, label.Visible, label.Parent = self.parent.ZIndex, true, self.parent
	self.fixedFrames[key], self.warming[label] = label, 0
	if not self.waiting then
		self.waiting = RunService.RenderStepped:Connect(function()
			for image, age in pairs(self.warming) do
				local loaded = image.IsLoaded
				age = loaded and age + 1 or 0
				self.warming[image] = age
				if age >= 2 then
					self.warming[image], self.ready[image] = nil, true
					image.Visible = false
				end
			end
			local pending = self.pending
			if pending and self.ready[pending.label] then
				self.pending = nil
				self:commit(pending.group, pending.index, pending.label)
			end
			if next(self.warming) == nil then self.waiting:Disconnect() self.waiting = nil end
		end)
	end
	return label
end

function sprite:show(group, index)
	if self.group == group and self.index == index then
		self.pending = nil
		return true
	end
	local quad = assert(self.library[group][index + 1], "Unknown DX quad: " .. group .. ":" .. index)
	if self.fixedFrames then
		local label = self:prepare(group, index)
		if not self.ready[label] then
			self.pending = {group = group, index = index, label = label}
			return false
		end
		self.pending = nil
		self:commit(group, index, label)
		return true
	end
	local label = assert(self.labels[quad[1]])
	-- Keep the previous drawable frame while a page is still arriving.
	if self.current and self.current ~= label and not label.IsLoaded and ContentProvider:GetAssetFetchStatus(label.Image) ~= Enum.AssetFetchStatus.Success then return end
	if self.current and self.current ~= label then self.current.Visible = false end
	label.ImageRectOffset = Vector2.new(quad[2], quad[3])
	label.ImageRectSize = Vector2.new(quad[4], quad[5])
	label.Position = UDim2.fromScale(quad[6] / quad[8], quad[7] / quad[9])
	label.Size = UDim2.fromScale(quad[4] / quad[8], quad[5] / quad[9])
	label.ImageTransparency, label.Visible = self.transparency, true
	self.group, self.index, self.current = group, index, label
	self.parent:SetAttribute("SpriteGroup", group)
	self.parent:SetAttribute("SpriteQuad", index)
end

function sprite:fade(value)
	self.transparency = value
	if self.current then self.current.ImageTransparency = value end
end

return sprite
